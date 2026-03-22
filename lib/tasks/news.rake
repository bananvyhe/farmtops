require "uri"

namespace :news do
  desc "Import source and section URLs from a text file"
  task import_sites: :environment do
    file = ENV.fetch("FILE", Rails.root.join("sites.txt").to_s)
    unless File.exist?(file)
      abort("File not found: #{file}")
    end

    urls = File.readlines(file, chomp: true)
      .map(&:strip)
      .reject(&:blank?)

    urls.each do |url|
      uri = URI.parse(url)
      host = uri.host.to_s.sub(/\Awww\./, "")
      next if host.blank?

      source = NewsSource.find_or_initialize_by(name: host)
      source.base_url = source_base_url_for(host)
      source.active = true if source.new_record?
      source.crawl_delay_min_seconds = source.crawl_delay_min_seconds.presence || 1
      source.crawl_delay_max_seconds = source.crawl_delay_max_seconds.presence || 3
      source.config = (source.config || {}).merge(source_config_for(host))
      source.save!

      normalized_url = normalized_section_url_for(host, url)
      path = uri.path.to_s.split("/").reject(&:blank?)
      section_name = path.last.to_s.tr("-", " ").titleize
      section_name = "Home" if section_name.blank?

      section = source.news_sections.find_or_initialize_by(url: normalized_url)
      section.name = section_name
      section.active = true if section.new_record?
      section.config = (section.config || {}).merge(section_config_for(host))
      section.save!
    end

    puts "Imported #{urls.size} URLs."
  end

  def source_config_for(host)
    case host
    when "massivelyop.com"
      {
        "article_title_selector" => "h1",
        "article_body_selector" => ".td-post-content",
        "article_body_exclude_selectors" => ".td-post-content .td-page-meta, .td-post-content .td-author-name, .td-post-content .td-social-sharing, .td-post-content .td-post-sharing, .td-post-content .td-post-source-tags, .td-post-content .td-post-share-title, .td-post-content .td-post-sharing-bottom, .td-post-content .td-post-footer, .td-post-content .td-post-related, .td-post-content .related, .td-post-content .related-posts, .td-post-content .post-tags, .td-post-content .tags, .td-post-content .share, .td-post-content .social-share, .td-post-content footer, .td-post-content .footer, .td-post-content div[style*='Montserrat']",
        "article_image_selector" => "meta[property='og:image'], .td-post-content img, img.wp-post-image, img",
        "pagination_mode" => "feed"
      }
    when "playtoearn.com"
      {
        "list_item_selector" => "article",
        "listing_url_selector" => "h2 a[href], h3 a[href], a[href]",
        "listing_title_selector" => "h2 a, h3 a",
        "listing_preview_selector" => "p",
        "listing_image_selector" => "img[data-src], img[data-lazy-src], img[data-original], img[srcset], img",
        "article_title_selector" => "h1",
        "article_body_selector" => "article",
        "article_body_exclude_selectors" => ".__Info, footer, .footer, .related, .related-posts, .post-tags, .tags, .share, .social-share, .entry-footer, .post-tags-wrap, .wp-block-separator, .wp-block-group.has-background",
        "article_image_selector" => "meta[property='og:image'], meta[property='twitter:image'], article img[data-src], article img[data-lazy-src], article img[data-original], article img[srcset], article img, img[data-src], img[data-lazy-src], img[data-original], img[srcset], img",
        "next_page_selector" => "a[rel='next']",
        "pagination_mode" => "query"
      }
    when "theblock.co"
      {
        "list_item_selector" => "article",
        "listing_url_selector" => "a[href*='/post/']",
        "listing_title_selector" => "h2 a, h3 a, a[href*='/post/']",
        "listing_preview_selector" => "p",
        "listing_image_selector" => "img[data-src], img[data-lazy-src], img[data-original], img[srcset], img",
        "article_title_selector" => "h1",
        "article_body_selector" => "article",
        "article_image_selector" => "meta[property='og:image'], meta[property='twitter:image'], article img[data-src], article img[data-lazy-src], article img[data-original], article img[srcset], article img, img[data-src], img[data-lazy-src], img[data-original], img[srcset], img",
        "next_page_selector" => "a[rel='next']",
        "pagination_mode" => "start",
        "pagination_step" => 10
      }
    else
      {}
    end
  end

  def section_config_for(host)
    case host
    when "playtoearn.com"
      {
        "pagination_mode" => "query"
      }
    when "massivelyop.com"
      {
        "pagination_mode" => "feed"
      }
    when "theblock.co"
      {
        "pagination_mode" => "start",
        "pagination_step" => 10
      }
    else
      {}
    end
  end

  def source_base_url_for(host)
    case host
    when "theblock.co"
      "https://stage.theblock.co"
    else
      "https://#{host}"
    end
  end

  def normalized_section_url_for(host, url)
    return url unless host == "theblock.co"

    uri = URI.parse(url)
    uri.host = "stage.theblock.co"
    uri.scheme = "https"
    uri.to_s
  rescue URI::InvalidURIError, URI::Error
    url
  end
end
