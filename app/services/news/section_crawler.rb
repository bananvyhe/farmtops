require "digest"
require "erb"
require "nokogiri"
require "set"
require "securerandom"

module News
  class SectionCrawler
    Result = Struct.new(:pages_visited, :articles_found, :articles_saved, :articles_skipped, :errors, keyword_init: true)

    DEFAULT_MAX_ARTICLES = 7
    DEFAULT_MAX_PAGES = 20
    DEFAULT_MAX_RETRIES = 3
    DEFAULT_SOURCE_LANG = "en"
    DEFAULT_TARGET_LANG = "ru"

    def initialize(section:, client: nil, sleeper: PoliteSleeper.new, logger: Rails.logger,
      max_articles: DEFAULT_MAX_ARTICLES, max_pages: DEFAULT_MAX_PAGES, max_retries: DEFAULT_MAX_RETRIES,
      translator: nil, source_lang: DEFAULT_SOURCE_LANG, target_lang: DEFAULT_TARGET_LANG)
      @section = section
      @source = section.news_source
      @client = client || HttpClient.new(
        open_timeout: timeout_config_value("http_open_timeout_seconds", ENV.fetch("NEWS_HTTP_OPEN_TIMEOUT_SECONDS", "10").to_i),
        read_timeout: timeout_config_value("http_read_timeout_seconds", ENV.fetch("NEWS_HTTP_READ_TIMEOUT_SECONDS", "20").to_i)
      )
      @sleeper = sleeper
      @logger = logger
      @max_articles = max_articles
      @max_pages = max_pages
      @max_retries = max_retries
      @translator = translator
      @source_lang = source_lang
      @target_lang = target_lang
    end

    def call
      result = Result.new(pages_visited: 0, articles_found: 0, articles_saved: 0, articles_skipped: 0, errors: [])
      seen_keys = Set.new
      page_url = listing_page_url
      visited = 0

      while page_url.present? && visited < max_pages && result.articles_saved < max_articles
        document = fetch_document(page_url, xml: feed_mode?)
        result.pages_visited += 1
        visited += 1

        candidates = extract_listing_items(document, page_url)

        candidates.each do |candidate|
          result.articles_found += 1
          break if result.articles_saved >= max_articles

          save_result = crawl_article(candidate, page_url, seen_keys)
          if save_result[:saved]
            result.articles_saved += 1
          else
            result.articles_skipped += 1
            result.errors << save_result[:error] if save_result[:error].present?
          end
        end

        next_page = next_page_url(document, page_url, article_count: candidates.size)
        break if next_page.blank? || next_page == page_url

        page_url = next_page
      end

      section.update_column(:last_crawled_at, Time.current)
      result
    end

    private

    attr_reader :section, :source, :client, :sleeper, :logger, :max_articles, :max_pages, :max_retries,
      :translator, :source_lang, :target_lang

    Candidate = Struct.new(:url, :title, :preview_text, :preview_html, :image_url, :source_article_id, :raw_payload, keyword_init: true)

    def fetch_document(url, xml: false)
      html = with_retry(url) { client.fetch(url) }
      sleep_between_requests
      xml ? Nokogiri::XML(html) : Nokogiri::HTML(html)
    end

    def with_retry(url)
      attempts = 0
      begin
        attempts += 1
        yield
      rescue StandardError => e
        raise if attempts >= max_retries

        logger.warn("[News::SectionCrawler] retrying #{url}: #{e.class} #{e.message}")
        sleep((attempts * 0.4) + rand * 0.4)
        retry
      end
    end

    def sleep_between_requests
      sleeper.pause!
    end

    def extract_listing_items(document, page_url)
      return extract_feed_items(document, page_url) if feed_mode?

      list_selector = config_value("list_item_selector", "article")
      title_selector = config_value("listing_title_selector", "h1, h2, h3, a")
      url_selector = config_value("listing_url_selector", "a[href]")
      preview_selector = config_value("listing_preview_selector", "p")
      image_selector = config_value("listing_image_selector", "img")

      document.css(list_selector).filter_map do |node|
        link = node.at_css(url_selector) || node.at_css("a[href]")
        href = link&.[]("href").presence
        next if href.blank?

        Candidate.new(
          url: normalize_url(href, page_url),
          title: extract_text(node, title_selector) || link&.text.to_s.strip,
          preview_text: extract_text(node, preview_selector),
          preview_html: extract_preview_html(node, preview_selector, page_url),
          image_url: extract_image_url(node, image_selector, page_url),
          source_article_id: extract_source_article_id(node, href, page_url),
          raw_payload: {
            listing_title: extract_text(node, title_selector),
            listing_url: href,
            listing_preview: extract_text(node, preview_selector),
            listing_preview_html: extract_preview_html(node, preview_selector, page_url)
          }
        )
      end
    end

    def extract_feed_items(document, page_url)
      items = document.css("item, entry")
      items.filter_map do |node|
        link = feed_item_link(node)
        href = link.presence
        next if href.blank?

        Candidate.new(
          url: normalize_url(href, page_url),
          title: extract_text(node, "title") || feed_item_title(node),
          preview_text: extract_text(node, "description, summary, content") || feed_item_preview(node),
          preview_html: feed_item_preview_html(node),
          image_url: feed_item_image_url(node, page_url),
          source_article_id: feed_item_id(node, href, page_url),
          raw_payload: {
            feed_title: extract_text(node, "title"),
            feed_link: href,
            feed_preview: extract_text(node, "description, summary, content"),
            feed_preview_html: feed_item_preview_html(node),
            feed_description_html: node.at_css("description")&.inner_html.to_s,
            published_at: feed_item_published_at(node)
          }
        )
      end
    end

    def extract_image_url(node, selector, page_url)
      image_node = node.at_css(selector) || node.at_css("img")
      return unless image_node

      image = image_node["content"].presence ||
        image_node["data-src"].presence ||
        image_node["data-lazy-src"].presence ||
        image_node["data-original"].presence ||
        srcset_first_url(image_node["data-srcset"]) ||
        srcset_first_url(image_node["srcset"]) ||
        image_node["src"].presence
      normalize_url(image, page_url)
    end

    def crawl_article(candidate, page_url, seen_keys)
      if feed_mode? && candidate.raw_payload[:feed_description_html].present?
        begin
          article_document = fetch_document(candidate.url)
          article_data = extract_article(article_document, candidate, page_url)
          return save_article(article_data, seen_keys, candidate)
        rescue StandardError => e
          logger.warn("[News::SectionCrawler] article page fallback for #{candidate.url}: #{e.class} #{e.message}")
        end

        article_data = extract_feed_article(candidate, page_url)
        return save_article(article_data, seen_keys, candidate)
      end

      article_document = fetch_document(candidate.url)
      article_data = extract_article(article_document, candidate, page_url)
      save_article(article_data, seen_keys, candidate)
    end

    def save_article(article_data, seen_keys, candidate)
      unique_keys = [article_data[:source_article_id].presence, article_data[:content_hash]].compact

      return { saved: false, duplicate: true } if unique_keys.any? { |key| seen_keys.include?(key) }

      existing = find_existing_article(article_data)
      if existing.present?
        unique_keys.each { |key| seen_keys << key }
        return { saved: false, duplicate: true }
      end

      article_data = original_article_data(article_data)
      article = section.news_articles.build(article_data)
      article.save!
      unique_keys.each { |key| seen_keys << key }
      { saved: true, article: }
    rescue StandardError => e
      logger.warn("[News::SectionCrawler] skipped #{candidate.url}: #{e.class} #{e.message}")
      { saved: false, error: "#{candidate.url}: #{e.class} #{e.message}" }
    ensure
      sleep_between_requests
    end

    def original_article_data(article_data)
      article_data.merge(
        source_title: article_data[:title],
        source_preview_text: article_data[:preview_text],
        source_body_text: article_data[:body_text],
        translated_at: nil,
        translation_model: nil,
        translation_status: :pending,
        translation_completed_at: nil,
        translation_error: nil,
        translation_target_locale: target_lang,
        translation_source_locale: source_lang,
        raw_payload: article_data[:raw_payload].merge(
          "source_title" => article_data[:title],
          "source_preview_text" => article_data[:preview_text],
          "source_preview_html" => article_data[:preview_html],
          "source_body_text" => article_data[:body_text],
          "source_body_html" => article_data[:body_html],
          "translation_status" => "pending"
        ).compact
      )
    end

    def extract_feed_article(candidate, page_url)
      fragment = Nokogiri::HTML.fragment(candidate.raw_payload[:feed_description_html].to_s)
      title = candidate.title
      body_html = sanitize_news_html(rewrite_fragment_urls(fragment.to_html, candidate.url))
      body_text = extract_fragment_body_text(Nokogiri::HTML.fragment(body_html))
      preview_text = preview_excerpt(body_text, candidate.preview_text)
      image_url = image_node_url(fragment.at_css("img")).presence || candidate.image_url
      published_at = candidate.raw_payload[:published_at]
      source_article_id = candidate.source_article_id.presence || candidate.url
      content_hash = Digest::SHA256.hexdigest([
        source.id,
        title,
        body_text,
        image_url
      ].map(&:to_s).join("|"))

      {
        news_source: source,
        news_section: section,
        source_article_id:,
        canonical_url: candidate.url,
        title: normalize_text(title),
        preview_text: normalize_text(preview_text),
        preview_html: sanitize_news_html(rewrite_fragment_urls(candidate.preview_html.to_s.presence || fragment.to_html, candidate.url)),
        body_text: body_text.to_s.strip.presence,
        body_html: strip_duplicate_leading_featured_image(body_html, [image_url, candidate.image_url]),
        image_url: normalize_url(image_url, candidate.url),
        published_at:,
        fetched_at: Time.current,
        content_hash:,
        raw_payload: {
          source_page_url: page_url,
          article_url: candidate.url,
          canonical_url: candidate.url,
          source_article_id: source_article_id,
          source_listing_image_url: candidate.image_url,
          title: title,
          preview_text: preview_text,
          preview_html: candidate.preview_html
        }.compact
      }
    end

    def extract_article(document, candidate, page_url)
      article_url = canonical_url(document, candidate.url)
      title = extract_text(document, config_value("article_title_selector", "h1")) ||
        meta_content(document, "og:title") ||
        candidate.title
      body_html = extract_body_html(document, candidate.url)
      body_text = extract_body_text_from_html(body_html).presence || extract_body_text(document)
      preview_html = extract_preview_html(document, config_value("article_preview_selector", "header p, .lead, .excerpt"), candidate.url)
      preview_text = preview_excerpt(body_text, candidate.preview_text)
      image_url = article_image_url(document, candidate)
      published_at = extract_datetime(document)
      source_article_id = candidate.source_article_id.presence ||
        extract_source_article_id_from_document(document, article_url)
      content_hash = Digest::SHA256.hexdigest([
        source.id,
        title,
        body_text,
        image_url
      ].map(&:to_s).join("|"))

      {
        news_source: source,
        news_section: section,
        source_article_id:,
        canonical_url: article_url,
        title: normalize_text(title),
        preview_text: normalize_text(preview_text),
        preview_html: sanitize_news_html(rewrite_fragment_urls(preview_html.to_s, candidate.url)),
        body_text: body_text.to_s.strip.presence,
        body_html: strip_duplicate_leading_featured_image(body_html, [image_url, candidate.image_url]),
        image_url: better_image_url(image_url, candidate.image_url),
        published_at:,
        fetched_at: Time.current,
        content_hash:,
        raw_payload: {
          source_page_url: page_url,
          article_url: candidate.url,
          canonical_url: article_url,
          source_article_id: source_article_id,
          source_listing_image_url: candidate.image_url,
          title: title,
          preview_text: preview_text,
          preview_html: preview_html
        }.compact
      }
    end

    def translate_article_data(article_data, candidate)
      translated = translate_article(article_data, candidate)
      translated_title = translated.translated_title.to_s.strip.presence || article_data[:title]
      translated_preview_text = translated.translated_preview_text.to_s.strip.presence || article_data[:preview_text]
      translated_body_text = translated.translated_body_text.to_s.strip.presence || article_data[:body_text]

      translated_article_data(article_data, translated_title, translated_preview_text, translated_body_text, translated)
    rescue News::Translation::Error => e
      logger.warn("[News::SectionCrawler] translation unavailable for #{candidate.url}: #{e.class} #{e.message}")
      untranslated_article_data(article_data, candidate, e)
    end

    def translate_article(article_data, candidate)
      with_retry("translation for #{candidate.url}") do
        translator.translate_article(
          request_id: SecureRandom.uuid,
          source_lang: source_lang,
          target_lang: target_lang,
          title: article_data[:title],
          preview_text: article_data[:preview_text],
          body_text: article_data[:body_text]
        )
      end
    end

    def translated_article_data(article_data, translated_title, translated_preview_text, translated_body_text, translated)
      article_data.merge(
        title: normalize_text(translated_title),
        preview_text: normalize_text(translated_preview_text),
        body_text: translated_body_text.to_s.strip.presence,
        body_html: build_translated_body_html(translated_body_text, source_html: article_data[:body_html]),
        source_title: article_data[:title],
        source_preview_text: article_data[:preview_text],
        source_body_text: article_data[:body_text],
        translated_at: Time.current,
        translation_model: translated.model.presence,
        translation_target_locale: target_lang,
        translation_source_locale: source_lang,
        raw_payload: article_data[:raw_payload].merge(
          "source_title" => article_data[:title],
          "source_preview_text" => article_data[:preview_text],
          "source_preview_html" => article_data[:preview_html],
          "source_body_text" => article_data[:body_text],
          "source_body_html" => article_data[:body_html],
          "translation_request_id" => translated.request_id,
          "translation_model" => translated.model,
          "translation_status" => translated.status
        ).compact
      )
    end

    def untranslated_article_data(article_data, candidate, error)
      article_data.merge(
        source_title: article_data[:title],
        source_preview_text: article_data[:preview_text],
        source_body_text: article_data[:body_text],
        translated_at: nil,
        translation_model: nil,
        translation_target_locale: target_lang,
        translation_source_locale: source_lang,
        raw_payload: article_data[:raw_payload].merge(
          "source_title" => article_data[:title],
          "source_preview_text" => article_data[:preview_text],
          "source_preview_html" => article_data[:preview_html],
          "source_body_text" => article_data[:body_text],
          "source_body_html" => article_data[:body_html],
          "translation_status" => "fallback",
          "translation_error" => error.message,
          "translation_error_class" => error.class.name,
          "translation_fallback_url" => candidate.url
        ).compact
      )
    end

    def build_translated_body_html(body_text, source_html:)
      News::Translation::HtmlBodyRenderer.new(source_html:).call(body_text)
    end

    def strip_duplicate_leading_featured_image(html, image_urls)
      fragment = Nokogiri::HTML.fragment(html.to_s)
      first_block = fragment.children.find { |node| node.element? }
      return html if first_block.blank?

      featured_class = first_block["class"].to_s
      return html unless featured_class.match?(/\btd-post-featured-image\b|\b__NewsImage\b/)

      first_image = first_block.at_css("img[src]") || first_block.at_css("img[data-src]")
      return html if first_image.blank?

      normalized_src = normalize_url(first_image["src"].presence || first_image["data-src"].presence, image_urls.compact.first || "")
      comparison_urls = image_urls.compact.map { |url| normalize_url(url, normalized_src) }.compact
      return html unless comparison_urls.include?(normalized_src)

      first_block.remove
      fragment.to_html
    rescue StandardError
      html
    end

    def find_existing_article(article_data)
      scope = source.news_articles
      scope.find_by(source_article_id: article_data[:source_article_id]) ||
        scope.find_by(content_hash: article_data[:content_hash])
    end

    def next_page_url(document, page_url, article_count: nil)
      return nil if feed_mode?

      selector = config_value("next_page_selector", "a[rel='next'], .next a, a.next")
      link = document.at_css(selector) || document.at_css("a[rel='next']")
      return normalize_url(link["href"], page_url) if link&.[]("href").present?

      return nil unless pagination_mode_configured?
      return nil if article_count.to_i <= 0

      derive_next_page_url(page_url, config_value("pagination_mode", "path"))
    end

    def extract_body_text(document)
      selector = config_value("article_body_selector", "[itemprop='articleBody'], .article-body, article")
      nodes = document.css(selector)
      paragraphs = nodes.flat_map do |node|
        block_texts_from_node(node)
      end
      paragraphs = [extract_text(document, selector)] if paragraphs.empty?
      paragraphs = paragraphs.compact.map { |text| normalize_text(text) }.reject(&:blank?)
      filter_body_paragraphs(paragraphs).join("\n\n")
    end

    def extract_body_text_from_html(html)
      fragment = Nokogiri::HTML.fragment(html.to_s)
      extract_fragment_body_text(fragment)
    end

    def extract_fragment_body_text(fragment)
      paragraphs = block_texts_from_fragment(fragment)
      paragraphs = [fragment.text] if paragraphs.empty?
      paragraphs = paragraphs.compact.map { |text| normalize_text(text) }.reject(&:blank?)
      filter_body_paragraphs(paragraphs).join("\n\n")
    end

    def extract_body_html(document, base_url)
      selector = config_value("article_body_selector", "[itemprop='articleBody'], .article-body, article")
      node = best_body_node(document, selector)
      if node.present?
        html = sanitize_news_html(normalize_lazy_images(strip_article_noise(node.inner_html), base_url))
        return html if html.present?
      end

      fallback_html = extract_body_html_from_document(document, base_url)
      return fallback_html if fallback_html.present?

      json_ld_body = extract_json_ld_article_body(document)
      return "" if json_ld_body.blank?

      sanitize_news_html(normalize_lazy_images(strip_article_noise(json_ld_body), base_url))
    end

    def article_image_url(document, candidate)
      selector = config_value("article_image_selector", "meta[property='og:image'], img")
      image = prioritized_image_url(document, selector)
      normalize_url(image, candidate.url)
    end

    def extract_datetime(document)
      time_tag = document.at_css("time[datetime]")
      Time.zone.parse(time_tag["datetime"]) if time_tag&.[]("datetime").present?
    rescue StandardError
      nil
    end

    def meta_content(document, property_name)
      document.at_css(%(meta[property="#{property_name}"]))&.[]("content").to_s.strip.presence
    end

    def canonical_url(document, fallback_url)
      meta_content(document, "og:url").presence ||
        document.at_css('link[rel="canonical"]')&.[]("href").to_s.strip.presence ||
        fallback_url
    end

    def extract_source_article_id(node, href, page_url)
      node["data-id"].presence || node["data-article-id"].presence || normalize_url(href, page_url)
    end

    def extract_source_article_id_from_document(document, fallback_url)
      meta_content(document, "article:id").presence || fallback_url
    end

    def extract_text(node, selector)
      node.at_css(selector)&.text.to_s.strip.presence
    end

    def normalize_text(value)
      value.to_s.gsub(/\s+/, " ").strip.presence
    end

    def block_texts_from_node(node)
      block_texts_from_fragment(Nokogiri::HTML.fragment(node.inner_html.to_s))
    end

    def block_texts_from_fragment(fragment)
      block_selector = "p, li, h1, h2, h3, h4, h5, h6, blockquote, figcaption, pre"
      paragraphs = fragment.css(block_selector).map(&:text)
      paragraphs += fragment.css("div").map(&:text) if fragment.css("p").empty? && fragment.css("div").any?
      paragraphs = fragment.children.map(&:text) if paragraphs.empty?
      paragraphs
    end

    def extract_body_html_from_document(document, base_url)
      body = document.at_css("body")
      return "" unless body

      fragment = Nokogiri::HTML::DocumentFragment.parse(body.inner_html.to_s)
      fragment.css("h1, h2, h3, h4, h5, h6, time, script, style, noscript, meta, link").each(&:remove)

      html = sanitize_news_html(normalize_lazy_images(strip_article_noise(fragment.to_html), base_url))
      html.presence
    end

    def best_body_node(document, selector)
      base_nodes = document.css(selector)
      base_nodes = document.css("article, main, section, .article-body, .post-content, .entry-content, .td-post-content") if base_nodes.empty?
      base_nodes = [document.at_css("body")].compact if base_nodes.empty?

      scored = base_nodes.flat_map do |node|
        body_node_candidates(node).map do |candidate|
          [candidate, score_body_node(candidate)]
        end
      end

      scored = scored.reject { |node, score| score <= 0 }
      scored.max_by { |node, score| score }&.first
    end

    def body_node_candidates(node)
      candidates = [node]
      candidates.concat(node.css("article, main, section, div, figure, blockquote, .content, .article-content, .story-body, .post-content, .td-post-content, .entry-content"))
      candidates.compact.uniq
    end

    def score_body_node(node)
      text = normalize_text(node.text)
      return 0 if text.blank?

      paragraph_count = node.css("p, li, blockquote, figcaption").length
      image_count = node.css("img").length
      link_count = node.css("a").length
      noise_count = node.css("footer, nav, aside, .related, .share, .tags, .comments, .social, .author, .meta, .subscribe, .newsletter").length

      text.length + (paragraph_count * 160) + (image_count * 20) - (link_count * 4) - (noise_count * 250)
    end

    def strip_article_noise(html)
      fragment = Nokogiri::HTML.fragment(html.to_s)
      article_body_exclude_selectors.each do |selector|
        fragment.css(selector).each(&:remove)
      end
      fragment.to_html
    end

    def article_body_exclude_selectors
      selectors = Array(config_value("article_body_exclude_selectors", "")).flat_map { |value| value.to_s.split(",") }
      selectors += massivelyop_article_body_exclude_selectors if massivelyop_source?
      selectors.map(&:strip).reject(&:blank?).uniq
    end

    def massivelyop_article_body_exclude_selectors
      [".td-post-content .swiper"]
    end

    def massivelyop_source?
      URI.parse(source.base_url.to_s).host.to_s.sub(/\Awww\./, "") == "massivelyop.com"
    rescue URI::InvalidURIError, URI::Error
      false
    end

    def prioritized_image_url(document, selector_list)
      selectors = selector_list.to_s.split(",").map(&:strip).reject(&:blank?)

      selectors.each do |selector|
        if selector.start_with?("meta[")
          image = document.at_css(selector)&.[]("content").presence
          return image if image.present? && !image_placeholder?(image)
          next
        end

        document.css(selector).each do |node|
          image = image_node_url(node)
          return image if image.present? && !image_placeholder?(image)
        end
      end

      document.css("img").each do |node|
        image = image_node_url(node)
        return image if image.present? && !image_placeholder?(image)
      end

      nil
    end

    def image_node_url(node)
      return unless node

      node["data-src"].presence ||
        node["data-lazy-src"].presence ||
        node["data-original"].presence ||
        node["data-url"].presence ||
        node["data-zoom-image"].presence ||
        node["src"].presence ||
        srcset_first_url(node["srcset"])
    end

    def srcset_first_url(value)
      value.to_s.split(",").map(&:strip).map { |part| part.split(/\s+/).first }.compact.first.presence
    end

    def better_image_url(primary, fallback)
      primary = primary.presence
      fallback = fallback.presence

      return fallback if primary.blank? || image_placeholder?(primary)
      return primary if fallback.blank? || image_placeholder?(fallback)

      primary
    end

    def image_placeholder?(url)
      value = url.to_s
      value.match?(%r{\Ahttps?://(?:assets\.playtoearn\.com/img/load\.png|www\.tbstat\.com/cdn-cgi/image/format=webp)\z}i) ||
        value.match?(%r{playtoearn\.com/blog_images/.*\.(?:png|jpg|jpeg|webp)\z}i) ||
        value.match?(%r{cdn-cgi/image/format=webp\z}i)
    end

    def normalize_lazy_images(html, base_url)
      fragment = Nokogiri::HTML.fragment(html.to_s)
      fragment.css("img").each do |img|
        image = img["src"].presence
        lazy_image = img["data-src"].presence ||
          img["data-lazy-src"].presence ||
          img["data-original"].presence ||
          img["data-url"].presence ||
          srcset_first_url(img["data-srcset"]) ||
          srcset_first_url(img["srcset"])

        if lazy_image.present? && (image.blank? || image.match?(/load\.png|placeholder|data:/i))
          img["src"] = lazy_image
        end

        img.remove_attribute("data-src")
        img.remove_attribute("data-lazy-src")
        img.remove_attribute("data-original")
        img.remove_attribute("data-url")
        img.remove_attribute("data-srcset")
      end

      dedupe_article_images(fragment)

      rewrite_fragment_urls(fragment.to_html, base_url)
    end

    def dedupe_article_images(fragment)
      images_by_key = {}

      fragment.css("img").each do |img|
        key = image_family_key(img)
        next if key.blank?

        score = image_variant_score(img)
        existing = images_by_key[key]

        if existing.present?
          if score > existing[:score]
            existing[:node].remove
            images_by_key[key] = { node: img, score: }
          else
            img.remove
          end
        else
          images_by_key[key] = { node: img, score: }
        end
      end
    end

    def image_family_key(node)
      url = node["src"].presence || node["data-src"].presence || node["data-lazy-src"].presence || node["data-original"].presence
      return if url.blank?

      normalized = url.to_s.split("?").first
      normalized = normalized.sub(%r{-\d+x\d+(?=\.[a-zA-Z0-9]+$)}, "")
      normalized
    end

    def image_variant_score(node)
      width = node["width"].to_i
      height = node["height"].to_i
      area = width.positive? && height.positive? ? width * height : 0

      if area.zero?
        url = node["src"].presence || node["data-src"].presence || node["data-lazy-src"].presence || node["data-original"].presence || ""
        if (match = url.match(/-(\d+)x(\d+)(?=\.[a-zA-Z0-9]+(?:\?|$))/))
          area = match[1].to_i * match[2].to_i
        end
      end

      area.zero? ? 1 : area
    end

    def filter_body_paragraphs(paragraphs)
      markers = [
        /\Ashare\z/i,
        /\Asource:/i,
        /\Aprevious article/i,
        /\Anext article/i,
        /\Atags?\z/i,
        /\Asubscribe/i,
        /\Aload all comments/i,
        /\Acommenting faq/i
      ]

      paragraphs.reject do |paragraph|
        markers.any? { |marker| paragraph.match?(marker) }
      end
    end

    def normalize_url(url, base_url)
      return if url.blank?

      uri = URI.parse(url)
      uri = URI.join(base_url.to_s, url) if uri.relative?
      uri.fragment = nil
      if uri.query.present?
        params = URI.decode_www_form(uri.query).reject { |key, _| key.to_s.start_with?("utm_") || key == "fbclid" }
        uri.query = params.any? ? URI.encode_www_form(params) : nil
      end
      uri.to_s
    rescue URI::InvalidURIError, URI::Error
      url.to_s
    end

    def config_value(key, fallback)
      section.config[key] || source.config[key] || fallback
    end

    def timeout_config_value(key, fallback)
      value = section.config[key].presence || source.config[key].presence
      value.present? ? value.to_i : fallback
    end

    def pagination_mode_configured?
      section.config.key?("pagination_mode") ||
        source.config.key?("pagination_mode") ||
        section.config.key?("feed_url") ||
        source.config.key?("feed_url")
    end

    def listing_page_url
      return feed_url if feed_mode?

      section.url
    end

    def feed_mode?
      config_value("pagination_mode", "path").to_s == "feed" || explicit_feed_url.present?
    end

    def feed_url
      explicit_feed_url.presence || derived_feed_url
    end

    def explicit_feed_url
      section.config["feed_url"].presence || source.config["feed_url"].presence
    end

    def derived_feed_url
      base = section.url.to_s.sub(%r{/?\z}, "/")
      return if base.blank?

      "#{base}feed/"
    end

    def feed_item_link(node)
      node.at_css("link[rel='alternate']")&.[]("href").presence ||
        node.at_css("link")&.[]("href").presence ||
        node.at_css("link")&.text.to_s.strip.presence ||
        node.at_css("guid")&.text.to_s.strip.presence
    end

    def feed_item_title(node)
      extract_text(node, "title")
    end

    def feed_item_preview(node)
      extract_text(node, "description, summary")
    end

    def feed_item_preview_html(node)
      node.at_css("description, summary, content")&.inner_html.to_s.presence
    end

    def feed_item_published_at(node)
      value = extract_text(node, "pubDate, published, updated")
      return if value.blank?

      Time.zone.parse(value)
    rescue StandardError
      nil
    end

    def feed_item_image_url(node, page_url)
      enclosure = node.at_css("enclosure")
      image = enclosure&.[]("url").presence ||
        node.at_xpath(".//*[local-name()='content']")&.[]("url").presence
      normalize_url(image, page_url)
    end

    def feed_item_id(node, href, page_url)
      node.at_css("guid")&.text.to_s.strip.presence ||
        node["id"].presence ||
        extract_source_article_id(node, href, page_url)
    end

    def derive_next_page_url(page_url, mode = "path")
      uri = URI.parse(page_url)
      path = uri.path.to_s

      if mode.to_s == "query"
        current_page = uri.query.to_s[/\bpage=(\d+)/, 1].to_i
        next_page = current_page > 0 ? current_page + 1 : 2
        params = uri.query.present? ? URI.decode_www_form(uri.query) : []
        params.reject! { |key, _| key == "page" }
        params << ["page", next_page.to_s]
        uri.query = URI.encode_www_form(params)
        uri.fragment = nil
        uri.to_s
      elsif mode.to_s == "start"
        current_start = uri.query.to_s[/\bstart=(\d+)/, 1].to_i
        step = config_value("pagination_step", 20).to_i
        next_start = current_start.positive? ? current_start + step : step
        params = uri.query.present? ? URI.decode_www_form(uri.query) : []
        params.reject! { |key, _| key == "start" }
        params << ["start", next_start.to_s]
        uri.query = URI.encode_www_form(params)
        uri.fragment = nil
        uri.to_s
      else
        if path.match?(%r{/page/\d+/?\z})
          next_path = path.sub(%r{/page/(\d+)/?\z}) { "/page/#{$1.to_i + 1}/" }
        else
          next_path = path.end_with?("/") ? "#{path}page/2/" : "#{path}/page/2/"
        end

        uri.path = next_path
        uri.query = nil
        uri.fragment = nil
        uri.to_s
      end
    rescue URI::InvalidURIError, URI::Error
      nil
    end

    def rewrite_fragment_urls(html, base_url)
      fragment = Nokogiri::HTML.fragment(html.to_s)
      fragment.css("a[href], img[src], img[data-src], source[src], iframe[src], video[poster]").each do |node|
        %w[href src data-src poster].each do |attribute|
          next if node[attribute].blank?

          node[attribute] = normalize_url(node[attribute], base_url) if %w[href src data-src poster].include?(attribute)
        end
      end
      fragment.to_html
    end

    def sanitize_news_html(html)
      ActionController::Base.helpers.sanitize(
        html.to_s,
        tags: %w[p br div span strong em b i u s ul ol li blockquote figure figcaption a img h1 h2 h3 h4 h5 h6 iframe video source],
        attributes: %w[href src alt title width height class style allow allowfullscreen frameborder loading referrerpolicy rel target data-src data-lazy-src poster]
      )
    end

    def extract_json_ld_article_body(document)
      document.css('script[type="application/ld+json"]').each do |script|
        json = JSON.parse(script.text)
        next unless json.present?

        articles = json.is_a?(Array) ? json : [json]
        articles.each do |entry|
          next unless entry.is_a?(Hash)
          next unless entry["@type"].to_s == "NewsArticle" || entry["@type"].to_s == "Article"

          body = entry["articleBody"].to_s
          return body if body.present?
        end
      rescue JSON::ParserError
        next
      end

      nil
    end

    def preview_excerpt(body_text, fallback)
      text = body_text.to_s.strip.presence || fallback.to_s.strip
      return if text.blank?

      normalized = text.gsub(/\s+/, " ").strip
      normalized.truncate(380, omission: "…")
    end

    def extract_preview_html(node, selector, base_url)
      return unless selector.present?

      preview_node = node.at_css(selector)
      return if preview_node.blank?

      html = normalize_lazy_images(strip_article_noise(preview_node.inner_html), base_url)
      sanitize_news_html(html).presence
    end
  end
end
