module Api
  module Admin
    class NewsSourcesController < BaseController
      before_action :ensure_authenticated!
      before_action :ensure_admin!
      before_action :set_news_source, only: %i[update destroy crawl]

      def index
        render json: {
          news_sources: NewsSource.includes(:news_crawl_runs, news_sections: :news_articles).order(:name).map { |source| news_source_payload(source) }
        }
      end

      def create
        source = NewsSource.new(news_source_params)
        if source.save
          render json: { news_source: news_source_payload(source) }, status: :created
        else
          render json: { errors: source.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @news_source.update(news_source_params)
          render json: { news_source: news_source_payload(@news_source) }
        else
          render json: { errors: @news_source.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @news_source.destroy!
        head :no_content
      end

      def crawl
        @news_source.news_sections.active.find_each do |section|
          NewsCrawlSectionJob.perform_async(section.id)
        end

        render json: { news_source: news_source_payload(@news_source), queued: true }
      end

      private

      def set_news_source
        @news_source = NewsSource.find(params[:id])
      end

      def news_source_params
        params.permit(
          :name,
          :base_url,
          :active,
          :crawl_delay_min_seconds,
          :crawl_delay_max_seconds,
          config: {}
        )
      end
    end
  end
end
