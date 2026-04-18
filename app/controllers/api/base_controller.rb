module Api
  class BaseController < ApplicationController
    skip_forgery_protection
    before_action :verify_frontend_csrf!
    before_action :ensure_news_visitor_identity

    private

    def render_error(message, status:)
      render json: { error: message }, status:
    end

    def ensure_authenticated!
      return if user_signed_in?

      render_error("Authentication required", status: :unauthorized)
    end

    def ensure_admin!
      return if current_user&.admin?

      render_error("Admin access required", status: :forbidden)
    end

    def user_payload(user)
      {
        id: user.id,
        email: user.email,
        role: user.role,
        active: user.active,
        nickname: user.nickname,
        nickname_change_used: user.nickname_change_used,
        can_change_nickname: user.can_change_nickname?,
        balance_cents: user.balance_cents,
        tariff_id: user.tariff_id,
        tariff_name: user.tariff_name,
        hourly_rate_cents: user.effective_hourly_rate_cents,
        manual_hourly_rate_cents: user.hourly_rate_cents,
        remaining_days: user.remaining_days,
        last_hourly_charge_at: user.last_hourly_charge_at,
        prime_time_zone: user.prime_time_zone,
        prime_slots_utc: user.prime_slots_utc,
        prime_slots_count: user.prime_slots_utc.size,
        world_level: user.world_level,
        world_xp_total: user.world_xp_total,
        world_xp_to_next_level: user.world_xp_to_next_level,
        world_xp_bank: user.world_xp_bank,
        world_boss_kills: user.world_boss_kills
      }
    end

    def tariff_payload(tariff)
      {
        id: tariff.id,
        name: tariff.name,
        monthly_price_cents: tariff.monthly_price_cents,
        hourly_rate_cents: tariff.hourly_rate_cents,
        billing_period_days: tariff.billing_period_days,
        description: tariff.description,
        active: tariff.active
      }
    end

    def payment_payload(payment)
      {
        id: payment.id,
        label: payment.label,
        status: payment.status,
        requested_amount_cents: payment.requested_amount_cents,
        credited_amount_cents: payment.credited_amount_cents,
        provider_net_amount_cents: payment.provider_net_amount_cents,
        paid_at: payment.paid_at,
        created_at: payment.created_at
      }
    end

    def ledger_payload(entry)
      {
        id: entry.id,
        kind: entry.kind,
        amount_cents: entry.amount_cents,
        balance_after_cents: entry.balance_after_cents,
        metadata: entry.metadata,
        created_at: entry.created_at
      }
    end

    def news_source_payload(source)
      {
        id: source.id,
        name: source.name,
        base_url: source.base_url,
        active: source.active,
        crawl_delay_min_seconds: source.crawl_delay_min_seconds,
        crawl_delay_max_seconds: source.crawl_delay_max_seconds,
        config: source.config,
        sections: source.news_sections.order(:name).map { |section| news_section_payload(section) },
        last_crawl_run: news_crawl_run_payload(source.news_crawl_runs.order(started_at: :desc).first)
      }
    end

    def news_section_payload(section)
      {
        id: section.id,
        news_source_id: section.news_source_id,
        source_name: section.news_source.name,
        name: section.name,
        url: section.url,
        active: section.active,
        config: section.config,
        last_crawled_at: section.last_crawled_at,
        articles_count: section.news_articles.size
      }
    end

    def news_article_payload(article, read: nil, bookmarked_game_ids: nil, game_bookmark_counts: nil)
      game = article.news_article_game&.game
      {
        id: article.id,
        news_source_id: article.news_source_id,
        news_section_id: article.news_section_id,
        source_name: article.news_source.name,
        section_name: article.news_section.name,
        source_article_id: article.source_article_id,
        canonical_url: article.canonical_url,
        title: article.title,
        preview_text: article.preview_text,
        preview_html: sanitized_news_html(article.preview_html),
        preview_image_url: news_article_preview_image_url(article),
        body_text: article.body_text,
        body_html: sanitized_news_html(news_article_body_html(article)),
        image_url: news_article_image_url(article),
        published_at: article.published_at,
        fetched_at: article.fetched_at,
        translated_at: article.translated_at,
        translation_model: article.translation_model,
        translation_status: article.translation_status,
        translation_error: article.translation_error,
        translation_started_at: article.translation_started_at,
        translation_completed_at: article.translation_completed_at,
        translation_request_id: article.translation_request_id,
        translation_attempts: article.translation_attempts,
        translation_target_locale: article.translation_target_locale,
        translation_source_locale: article.translation_source_locale,
        content_hash: article.content_hash,
        raw_payload: article.raw_payload,
        tags: article.news_tags.sort_by(&:name).map { |tag| news_tag_payload(tag) },
        game: game.present? ? news_game_payload(
          game,
          bookmarked: bookmarked_game_ids.nil? ? news_game_bookmarked?(game) : bookmarked_game_ids.include?(game.id),
          bookmarks_count: game_bookmark_counts.nil? ? news_game_bookmark_count_for(game) : game_bookmark_counts.fetch(game.id, 0)
        ) : nil,
        read: read.nil? ? news_article_read?(article) : read
      }
    end

    def news_tag_payload(tag, articles_count: nil)
      {
        id: tag.id,
        name: tag.name,
        slug: tag.slug,
        articles_count:
      }
    end

    def news_game_payload(game, bookmarked:, bookmarks_count:)
      {
        id: game.id,
        name: game.name,
        slug: game.slug,
        external_game_id: game.external_game_id,
        bookmarked:,
        bookmarks_count:,
        can_create_shard: bookmarks_count.to_i > 0
      }
    end

    def news_article_read?(article)
      news_article_read_ids_for([article.id]).include?(article.id)
    end

    def news_article_read_ids_for(article_ids)
      ids = Array(article_ids).map(&:to_i).reject(&:zero?).uniq
      return [] if ids.blank?

      scope = NewsArticleRead.where(news_article_id: ids)
      scope = if current_user.present?
        scope.where(user_id: current_user.id)
      elsif news_identity_uuid.present?
        scope.where(visitor_uuid: news_identity_uuid)
      else
        NewsArticleRead.none
      end

      scope.pluck(:news_article_id)
    end

    def ensure_news_visitor_identity
      return if cookies.signed[:farmspot_visitor_id].present?

      cookies.signed[:farmspot_visitor_id] = {
        value: SecureRandom.uuid,
        expires: 1.year.from_now,
        same_site: :lax,
        secure: Rails.env.production?
      }
    end

    def news_identity_uuid
      cookies.signed[:farmspot_visitor_id].presence
    end

    def news_read_identity_attrs
      if current_user.present?
        { user_id: current_user.id }
      elsif news_identity_uuid.present?
        { visitor_uuid: news_identity_uuid }
      end
    end

    def news_game_bookmark_identity_attrs
      if current_user.present?
        { user_id: current_user.id }
      elsif news_identity_uuid.present?
        { visitor_uuid: news_identity_uuid }
      end
    end

    def news_game_bookmarked?(game)
      news_game_bookmark_ids_for([game.id]).include?(game.id)
    end

    def news_game_bookmark_count_for(game)
      news_game_bookmark_counts_for([game.id]).fetch(game.id, 0)
    end

    def news_game_bookmark_ids_for(game_ids)
      ids = Array(game_ids).map(&:to_i).reject(&:zero?).uniq
      return [] if ids.blank?

      scope = NewsGameBookmark.where(game_id: ids)
      scope = if current_user.present?
        scope.where(user_id: current_user.id)
      elsif news_identity_uuid.present?
        scope.where(visitor_uuid: news_identity_uuid)
      else
        NewsGameBookmark.none
      end

      scope.pluck(:game_id)
    end

    def news_game_bookmark_counts_for(game_ids)
      ids = Array(game_ids).map(&:to_i).reject(&:zero?).uniq
      return {} if ids.blank?

      NewsGameBookmark.where(game_id: ids).group(:game_id).count
    end

    def upsert_news_article_reads(article_ids)
      ids = Array(article_ids).map(&:to_i).reject(&:zero?).uniq
      return if ids.blank?

      attrs = news_read_identity_attrs
      return if attrs.blank?

      now = Time.current
      ids.each do |article_id|
        read = NewsArticleRead.find_or_initialize_by(news_article_id: article_id, **attrs)
        read.read_at ||= now
        read.save!
      end
    end

    def merge_news_reads_to_user!(user, visitor_uuid)
      return if user.blank? || visitor_uuid.blank?

      NewsArticleRead.transaction do
        NewsArticleRead.for_visitor(visitor_uuid).find_each do |read|
          existing = NewsArticleRead.find_by(news_article_id: read.news_article_id, user_id: user.id)
          if existing
            existing.update!(read_at: [existing.read_at, read.read_at].compact.max)
            read.destroy!
          else
            read.update!(user_id: user.id, visitor_uuid: nil)
          end
        end
      end
    end

    def upsert_news_game_bookmark(game_id)
      attrs = news_game_bookmark_identity_attrs
      return if attrs.blank?

      bookmark = NewsGameBookmark.find_or_initialize_by(game_id: game_id, **attrs)
      bookmark.bookmarked_at ||= Time.current
      bookmark.save!
      bookmark
    end

    def delete_news_game_bookmark(game_id)
      attrs = news_game_bookmark_identity_attrs
      return if attrs.blank?

      bookmark = NewsGameBookmark.find_by(game_id: game_id, **attrs)
      bookmark&.destroy!
      bookmark
    end

    def merge_news_game_bookmarks_to_user!(user, visitor_uuid)
      return if user.blank? || visitor_uuid.blank?

      NewsGameBookmark.transaction do
        NewsGameBookmark.for_visitor(visitor_uuid).find_each do |bookmark|
          existing = NewsGameBookmark.find_by(game_id: bookmark.game_id, user_id: user.id)
          if existing
            existing.update!(bookmarked_at: [existing.bookmarked_at, bookmark.bookmarked_at].compact.max)
            bookmark.destroy!
          else
            bookmark.update!(user_id: user.id, visitor_uuid: nil)
          end
        end
      end
    end

    def sanitized_news_html(html)
      html = rewrite_twitch_embed_parents(html.to_s)

      ActionController::Base.helpers.sanitize(
        html,
        tags: %w[p br div span strong em b i u s ul ol li blockquote figure figcaption a img h1 h2 h3 h4 h5 h6 iframe video source],
        attributes: %w[href src alt title width height class style allow allowfullscreen frameborder loading referrerpolicy rel target data-src data-lazy-src poster]
      )
    end

    def rewrite_twitch_embed_parents(html)
      fragment = Nokogiri::HTML::DocumentFragment.parse(html)
      fragment.css("iframe[src]").each do |iframe|
        iframe["src"] = rewrite_twitch_embed_src(iframe["src"])
      end
      fragment.to_html
    end

    def rewrite_twitch_embed_src(src)
      uri = URI.parse(src)
      return src unless %w[player.twitch.tv www.twitch.tv twitch.tv].include?(uri.host)

      params = URI.decode_www_form(uri.query.to_s)
      params.reject! { |key, _value| key == "parent" }

      parent = normalized_twitch_parent(request.host)
      params << ["parent", parent] if parent.present?

      uri.query = params.any? ? URI.encode_www_form(params) : nil
      uri.to_s
    rescue URI::InvalidURIError
      src
    end

    def normalized_twitch_parent(host)
      return if host.blank?

      host = host.to_s.downcase.strip
      return if host.blank?
      return if host.include?("/") || host.include?(":") || host.include?("?") || host.include?("#")

      host if host.match?(/\A[a-z0-9.-]+\z/)
    end

    def news_article_image_url(article)
      return if article.image_url.blank?

      "/api/news/#{article.id}/image"
    end

    def news_article_preview_image_url(article)
      return if article.image_url.blank? && article.raw_payload.to_h["source_listing_image_url"].blank?

      "/api/news/#{article.id}/preview_image"
    end

    def news_article_body_html(article)
      strip_duplicate_leading_featured_image(
        article.body_html.to_s,
        [article.image_url, article.raw_payload.to_h["source_listing_image_url"]]
      )
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

    def news_crawl_run_payload(run)
      return unless run

      {
        id: run.id,
        news_source_id: run.news_source_id,
        news_section_id: run.news_section_id,
        status: run.status,
        started_at: run.started_at,
        finished_at: run.finished_at,
        pages_visited: run.pages_visited,
        articles_found: run.articles_found,
        articles_saved: run.articles_saved,
        articles_skipped: run.articles_skipped,
        crawl_errors: run.crawl_errors,
        metadata: run.metadata
      }
    end
  end
end
