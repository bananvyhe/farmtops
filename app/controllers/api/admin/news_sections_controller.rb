module Api
  module Admin
    class NewsSectionsController < BaseController
      before_action :ensure_authenticated!
      before_action :ensure_admin!
      before_action :set_news_source
      before_action :set_news_section, only: %i[update destroy]

      def create
        section = @news_source.news_sections.new(news_section_params)
        if section.save
          render json: { news_section: news_section_payload(section) }, status: :created
        else
          render json: { errors: section.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @news_section.update(news_section_params)
          render json: { news_section: news_section_payload(@news_section) }
        else
          render json: { errors: @news_section.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @news_section.destroy!
        head :no_content
      end

      private

      def set_news_source
        @news_source = NewsSource.find(params[:news_source_id])
      end

      def set_news_section
        @news_section = @news_source.news_sections.find(params[:id])
      end

      def news_section_params
        params.permit(:name, :url, :active, config: {})
      end
    end
  end
end
