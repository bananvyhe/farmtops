module Api
  class RegistrationsController < BaseController
    skip_before_action :verify_frontend_csrf!, only: :create

    def create
      user = User.new(
        email: params[:email],
        password: params[:password],
        password_confirmation: params[:password_confirmation],
        role: :client,
        active: true
      )

      if user.save
        sign_in!(user)
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
