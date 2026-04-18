require "base64"
require "json"
require "net/http"
require "uri"

module Api
  class NewsController < BaseController
    skip_before_action :verify_frontend_csrf!, only: %i[reads bookmark_game unbookmark_game]

    def index
      base_scope = base_articles_scope
      articles = filtered_articles(base_scope).limit(limit_param + 1)
      has_more = articles.size > limit_param
      articles = articles.first(limit_param)
      read_ids = news_article_read_ids_for(articles.map(&:id))
      bookmarked_game_ids = news_game_bookmark_ids_for(articles.filter_map { |article| article.news_article_game&.game_id })
      game_bookmark_counts = news_game_bookmark_counts_for(articles.filter_map { |article| article.news_article_game&.game_id })
      blocked_source_ids = NewsSource.blocked_source_ids
      render json: {
        articles: articles.map { |article| news_article_payload(article, read: read_ids.include?(article.id), bookmarked_game_ids:, game_bookmark_counts:) },
        sources: NewsSource.active.where.not(id: blocked_source_ids).includes(:news_sections).map { |source| news_source_payload(source) },
        sections: NewsSection.active.where.not(news_source_id: blocked_source_ids).includes(:news_source).map { |section| news_section_payload(section) },
        tags: news_tags_payload(base_scope),
        next_cursor: has_more ? news_cursor_for(articles.last) : nil,
        has_more:
      }
    end

    def show
      article = NewsArticle.includes(:news_source, :news_section, :news_tags, news_article_game: :game).find(params[:id])
      return render_error("Article not available", status: :not_found) if article.news_source.blocked_source?

      bookmarked_game_ids = news_game_bookmark_ids_for([article.news_article_game&.game_id].compact)
      game_bookmark_counts = news_game_bookmark_counts_for([article.news_article_game&.game_id].compact)
      render json: { article: news_article_payload(article, read: news_article_read?(article), bookmarked_game_ids:, game_bookmark_counts:) }
    end

    def reads
      article_ids = Array(params[:article_ids]).presence || Array(params[:id]).presence
      upsert_news_article_reads(article_ids)
      render json: { ok: true, read_article_ids: news_article_read_ids_for(article_ids) }
    end

    def bookmark_game
      article = NewsArticle.includes(news_article_game: :game).find(params[:id])
      return render_error("Game not available", status: :not_found) if article.news_source.blocked_source?

      game = article.news_article_game&.game
      return render_error("Game not available", status: :not_found) if game.blank?

      bookmark = upsert_news_game_bookmark(game.id)
      render json: { ok: true, game: news_game_payload(game, bookmarked: bookmark.present?, bookmarks_count: news_game_bookmark_count_for(game)) }
    end

    def unbookmark_game
      article = NewsArticle.includes(news_article_game: :game).find(params[:id])
      return render_error("Game not available", status: :not_found) if article.news_source.blocked_source?

      game = article.news_article_game&.game
      return render_error("Game not available", status: :not_found) if game.blank?

      delete_news_game_bookmark(game.id)
      render json: { ok: true, game: news_game_payload(game, bookmarked: false, bookmarks_count: news_game_bookmark_count_for(game)) }
    end

    def image
      article = NewsArticle.find(params[:id])
      return render_error("Image not available", status: :not_found) if article.news_source.blocked_source?

      url = article.image_url.to_s.strip

      return render_error("Image not available", status: :not_found) if url.blank?

      proxy_article_image(url)
    rescue StandardError => e
      Rails.logger.warn("[Api::NewsController] image proxy failed for #{params[:id]}: #{e.class} #{e.message}")
      render_error("Image not available", status: :bad_gateway)
    end

    def preview_image
      article = NewsArticle.find(params[:id])
      return render_error("Image not available", status: :not_found) if article.news_source.blocked_source?

      urls = [
        article.raw_payload.to_h["source_listing_image_url"].presence,
        article.image_url.to_s.strip
      ].compact.uniq
      return render_error("Image not available", status: :not_found) if urls.blank?

      urls.each do |url|
        begin
          response = fetch_image_response(url)
          next unless response.is_a?(Net::HTTPSuccess)

          content_type = response["content-type"].presence || "application/octet-stream"
          return send_data response.body.to_s, type: content_type, disposition: "inline"
        rescue StandardError
          next
        end
      end

      render_error("Image not available", status: :bad_gateway)
    rescue StandardError => e
      Rails.logger.warn("[Api::NewsController] preview image proxy failed for #{params[:id]}: #{e.class} #{e.message}")
      render_error("Image not available", status: :bad_gateway)
    end

    private

    def base_articles_scope
      blocked_source_ids = NewsSource.blocked_source_ids
      scope = NewsArticle.includes(:news_source, :news_section, :news_tags, news_article_game: :game).where.not(news_source_id: blocked_source_ids).recent
      scope = scope.where.not(news_source_id: NewsSource.general_feed_hidden_source_ids) if params[:source_id].blank? && params[:section_id].blank?
      scope = scope.where(news_source_id: params[:source_id]) if params[:source_id].present?
      scope = scope.where(news_section_id: params[:section_id]) if params[:section_id].present?
      scope
    end

    def filtered_articles(scope)
      scope = scope.joins(:news_article_tags).where(news_article_tags: { news_tag_id: selected_tag_ids }) if selected_tag_ids.any?
      scope = scope.joins(:news_article_game).where(news_article_games: { game_id: selected_game_id }) if selected_game_id.present?
      scope = scope.distinct if selected_tag_ids.any?
      scope = apply_cursor(scope) if params[:cursor].present?
      scope
    end

    def selected_tag_ids
      @selected_tag_ids ||= Array(params[:tag_ids]).flat_map { |value| value.to_s.split(",") }.map(&:to_i).reject(&:zero?).uniq
    end

    def selected_game_id
      value = Array(params[:game_id]).first
      return if value.blank?

      parsed = value.to_i
      parsed.positive? ? parsed : nil
    end

    def news_tags_payload(scope)
      article_scope = scope.except(:includes, :order, :limit, :offset, :select)
      tagged_counts = NewsTag.joins(news_article_tags: :news_article)
        .merge(article_scope)
        .group("news_tags.id")
        .count("news_articles.id")

      selected_tags = NewsTag.where(id: selected_tag_ids).order(:name)
      visible_tags = NewsTag.where(id: tagged_counts.keys).order(:name)
      (selected_tags + visible_tags).uniq(&:id).map do |tag|
        news_tag_payload(tag, articles_count: tagged_counts[tag.id] || 0)
      end
    end

    def limit_param
      value = params.fetch(:limit, 24).to_i
      value = 24 if value <= 0
      [value, 100].min
    end

    def apply_cursor(scope)
      timestamp, article_id = decode_cursor(params[:cursor])
      return scope if timestamp.blank? || article_id.blank?

      sort_sql = "COALESCE(news_articles.published_at, news_articles.fetched_at, news_articles.created_at)"
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

    def proxy_article_image(url)
      response = fetch_image_response(url)
      unless response.is_a?(Net::HTTPSuccess)
        return render_error("Image not available", status: :bad_gateway)
      end

      content_type = response["content-type"].presence || "application/octet-stream"
      send_data response.body.to_s, type: content_type, disposition: "inline"
    end
  end
end
