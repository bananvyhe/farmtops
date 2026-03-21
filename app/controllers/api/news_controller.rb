require "base64"
require "json"

module Api
  class NewsController < BaseController
    def index
      articles = filtered_articles.limit(limit_param + 1)
      has_more = articles.size > limit_param
      articles = articles.first(limit_param)
      render json: {
        articles: articles.map { |article| news_article_payload(article) },
        sources: NewsSource.active.includes(:news_sections).map { |source| news_source_payload(source) },
        sections: NewsSection.active.includes(:news_source).map { |section| news_section_payload(section) },
        next_cursor: has_more ? news_cursor_for(articles.last) : nil,
        has_more:
      }
    end

    def show
      article = NewsArticle.includes(:news_source, :news_section).find(params[:id])
      render json: { article: news_article_payload(article) }
    end

    private

    def filtered_articles
      scope = NewsArticle.includes(:news_source, :news_section).recent
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
  end
end
