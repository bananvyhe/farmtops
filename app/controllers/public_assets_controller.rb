require "cgi"

class PublicAssetsController < ActionController::Base
  layout false

  def robots
    render plain: robots_txt, content_type: "text/plain; charset=utf-8"
  end

  def sitemap
    render xml: sitemap_xml
  end

  private

  def robots_txt
    <<~TXT
      User-agent: *
      Allow: /
      Disallow: /admin
      Disallow: /dashboard
      Disallow: /login
      Disallow: /profile
      Disallow: /sidekiq
      Sitemap: #{site_origin}/sitemap.xml
    TXT
  end

  def sitemap_xml
    urls = [
      sitemap_entry(path: "/", lastmod: site_lastmod, priority: "1.0", changefreq: "daily"),
      sitemap_entry(path: "/news", lastmod: site_lastmod, priority: "0.9", changefreq: "hourly")
    ]

    sitemap_articles.each do |article|
      urls << sitemap_entry(
        path: "/news/#{article.id}",
        lastmod: article.updated_at || article.translated_at || article.published_at || article.fetched_at,
        priority: "0.7",
        changefreq: "weekly"
      )
    end

    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      #{urls.map { |entry| indent(entry, 2) }.join("\n")}
      </urlset>
    XML
  end

  def sitemap_articles
    blocked_source_ids = NewsSource.blocked_source_ids

    NewsArticle
      .includes(:news_source)
      .where.not(news_source_id: blocked_source_ids)
      .where(translation_status: "translated")
      .where.not(translated_at: nil)
      .recent
      .limit(50_000)
  end

  def sitemap_entry(path:, lastmod:, priority:, changefreq:)
    lastmod_tag = lastmod.present? ? "      <lastmod>#{CGI.escapeHTML(lastmod.utc.iso8601)}</lastmod>\n" : ""

    <<~XML.chomp
      <url>
        <loc>#{CGI.escapeHTML("#{site_origin}#{path}")}</loc>
#{lastmod_tag}        <changefreq>#{changefreq}</changefreq>
        <priority>#{priority}</priority>
      </url>
    XML
  end

  def site_lastmod
    sitemap_articles.maximum(:updated_at) || Time.current
  end

  def site_origin
    Rails.application.credentials.dig(:app, :base_url).presence ||
      ENV["APP_BASE_URL"].presence ||
      request.base_url
  end

  def indent(text, spaces)
    padding = " " * spaces
    text.lines.map { |line| line.blank? ? line : "#{padding}#{line}" }.join
  end
end
