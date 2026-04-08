module Api
  class SessionsController < BaseController
    skip_before_action :verify_frontend_csrf!, only: :create

    def show
      return render json: { authenticated: false, csrf_token: cookies[:farmspot_csrf] } unless user_signed_in?

      render json: {
        authenticated: true,
        csrf_token: cookies[:farmspot_csrf],
        user: user_payload(current_user)
      }
    end

    def create
      user = User.find_by(email: params[:email].to_s.downcase)

      if user&.authenticate(params[:password]) && user.active?
        sign_in!(user)
        clear_news_visitor_identity
        render json: {
          authenticated: true,
          csrf_token: cookies[:farmspot_csrf],
          user: user_payload(user)
        }
      else
        render_error("Invalid email or password", status: :unauthorized)
      end
    end

    def destroy
      sign_out!
      render json: { authenticated: false }
    end
  end
end
