module Api
  module Admin
    class NewsQueueController < BaseController
      before_action :ensure_authenticated!
      before_action :ensure_admin!

      def kick
        translation = News::Translation::Recovery.new.call
        games = News::GameIdentification::Recovery.new.call

        render json: { kicked: true, translation:, games: }
      end
    end
  end
end
