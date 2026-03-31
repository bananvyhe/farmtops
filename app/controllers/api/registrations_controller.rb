module Api
  class RegistrationsController < BaseController
    skip_before_action :verify_frontend_csrf!, only: :create

    def create
      visitor_uuid = cookies.signed[:farmspot_visitor_id].presence
      user = User.new(
        email: params[:email],
        password: params[:password],
        password_confirmation: params[:password_confirmation],
        role: :client,
        active: true
      )

      if user.save
        sign_in!(user)
        merge_news_reads_to_user!(user, visitor_uuid)
        merge_news_game_bookmarks_to_user!(user, visitor_uuid)
        render json: {
          authenticated: true,
          csrf_token: cookies[:farmspot_csrf],
          user: user_payload(user)
        }, status: :created
      else
        render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
      end
    end
  end
end
