module Api
  class NewsController < BaseController
    def index
      articles = filtered_articles.limit(limit_param)
      render json: {
        articles: articles.map { |article| news_article_payload(article) },
        sources: NewsSource.active.includes(:news_sections).map { |source| news_source_payload(source) },
        sections: NewsSection.active.includes(:news_source).map { |section| news_section_payload(section) }
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
      scope
    end

    def limit_param
      value = params.fetch(:limit, 24).to_i
      value = 24 if value <= 0
      [value, 100].min
    end
  end
end
