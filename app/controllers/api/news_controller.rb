require "base64"
require "json"
require "net/http"
require "uri"

module Api
  class NewsController < BaseController
    def index
      articles = filtered_articles.limit(limit_param + 1)
      has_more = articles.size > limit_param
      articles = articles.first(limit_param)
      render json: {
        articles: articles.map { |article| news_article_payload(article) },
        sources: NewsSource.crawlable.order(:name).includes(:news_sections).map { |source| news_source_payload(source) },
        sections: NewsSection.active.joins(:news_source).merge(NewsSource.crawlable).includes(:news_source).map { |section| news_section_payload(section) },
        next_cursor: has_more ? news_cursor_for(articles.last) : nil,
        has_more:
      }
    end

    def show
      article = NewsArticle.includes(:news_source, :news_section).joins(:news_source).merge(NewsSource.crawlable).find(params[:id])
      render json: { article: news_article_payload(article) }
    end

    def image
      article = NewsArticle.joins(:news_source).merge(NewsSource.crawlable).find(params[:id])
      url = article.image_url.to_s.strip

      return render_error("Image not available", status: :not_found) if url.blank?

      response = fetch_image_response(url)
      unless response.is_a?(Net::HTTPSuccess)
        return render_error("Image not available", status: :bad_gateway)
      end

      content_type = response["content-type"].presence || "application/octet-stream"
      send_data response.body.to_s, type: content_type, disposition: "inline"
    rescue StandardError => e
      Rails.logger.warn("[Api::NewsController] image proxy failed for #{params[:id]}: #{e.class} #{e.message}")
      render_error("Image not available", status: :bad_gateway)
    end

    private

    def filtered_articles
      scope = NewsArticle.includes(:news_source, :news_section).joins(:news_source).merge(NewsSource.crawlable).recent
      scope = scope.where(news_source_id: params[:source_id]) if params[:source_id].present?
      scope = scope.where(news_section_id: params[:section_id]) if params[:section_id].present?
      scope = apply_cursor(scope) if params[:cursor].present?
      scope
    end

    def limit_param
      value = params.fetch(:limit, 24).to_i
      value = 24 if value <= 0
      [value, 100].min
    end

    def apply_cursor(scope)
      timestamp, article_id = decode_cursor(params[:cursor])
      return scope if timestamp.blank? || article_id.blank?

      sort_sql = "COALESCE(published_at, fetched_at, created_at)"
      scope.where(
        "(#{sort_sql} < :timestamp) OR (#{sort_sql} = :timestamp AND id < :article_id)",
        timestamp: timestamp,
        article_id: article_id.to_i
      )
    rescue ArgumentError, JSON::ParserError
      scope
    end

    def news_cursor_for(article)
      return if article.blank?

      encode_cursor(article_sort_timestamp(article), article.id)
    end

    def article_sort_timestamp(article)
      article.published_at || article.fetched_at || article.created_at
    end

    def encode_cursor(timestamp, article_id)
      Base64.urlsafe_encode64([timestamp.iso8601, article_id].to_json)
    end

    def decode_cursor(cursor)
      values = JSON.parse(Base64.urlsafe_decode64(cursor.to_s))
      [Time.zone.parse(values[0].to_s), values[1].to_i]
    end

    def fetch_image_response(url)
      uri = URI.parse(url)
      raise ArgumentError, "Unsupported image URL" unless %w[http https].include?(uri.scheme)

      redirects = 0
      loop do
        response = perform_image_request(uri)
        case response
        when Net::HTTPSuccess
          return response
        when Net::HTTPRedirection
          redirects += 1
          raise ArgumentError, "Too many redirects" if redirects > 5

          location = response["location"]
          raise ArgumentError, "Redirect without location" if location.blank?

          uri = URI.parse(location)
          uri = URI.join(url, location) if uri.relative?
        else
          return response
        end
      end
    end

    def perform_image_request(uri)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 20) do |http|
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = ENV.fetch("NEWS_USER_AGENT", "FarmspotNewsCrawler/1.0")
        request["Accept"] = "image/avif,image/webp,image/*,*/*;q=0.8"
        request["Accept-Language"] = "en-US,en;q=0.9"
        request["Cache-Control"] = "no-cache"
        request["Pragma"] = "no-cache"
        http.request(request)
      end
    end
  end
end
