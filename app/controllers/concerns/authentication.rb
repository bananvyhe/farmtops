module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :set_current_request_details
  end

  private

  def authenticate_from_jwt_session
    return if Current.user.present?

    result = Auth::JwtCookieSession.authenticate(
      access_token: cookies[JWTSessions.access_cookie],
      refresh_token: cookies[JWTSessions.refresh_cookie]
    )
    return unless result

    Current.user = result.user
    write_auth_cookies(result.tokens) if result.refreshed?
  rescue JWTSessions::Errors::Unauthorized, JWT::DecodeError, JWT::ExpiredSignature
    clear_auth_cookies
  end

  def current_user
    Current.user
  end

  def user_signed_in?
    current_user.present?
  end

  def require_authentication
    return if user_signed_in?

    redirect_to new_session_path, alert: "Сначала войдите в систему."
  end

  def require_admin!
    return if current_user&.admin?

    redirect_to dashboard_path, alert: "Раздел доступен только администратору."
  end

  def sign_in!(user)
    tokens = Auth::JwtCookieSession.issue_for(user)
    write_auth_cookies(tokens)
    Current.user = user
  end

  def sign_out!
    Auth::JwtCookieSession.flush(cookies[JWTSessions.refresh_cookie])
    clear_auth_cookies
    Current.reset
  end

  def write_auth_cookies(tokens)
    cookie_options = {
      httponly: true,
      secure: Rails.env.production?,
      same_site: :lax
    }

    cookies[JWTSessions.access_cookie] = cookie_options.merge(value: tokens[:access], expires: tokens[:access_expires_at])
    cookies[JWTSessions.refresh_cookie] = cookie_options.merge(value: tokens[:refresh], expires: tokens[:refresh_expires_at])
    cookies[:farmspot_csrf] = {
      value: tokens[:csrf],
      expires: tokens[:refresh_expires_at],
      secure: Rails.env.production?,
      same_site: :lax
    }
  end

  def clear_auth_cookies
    cookies.delete(JWTSessions.access_cookie)
    cookies.delete(JWTSessions.refresh_cookie)
    cookies.delete(:farmspot_csrf)
  end

  def set_current_request_details
    Current.request_id = request.request_id
  end

  def verify_frontend_csrf!
    return if request.get? || request.head? || request.options?
    return if request.headers["X-CSRF-Token"].present? && request.headers["X-CSRF-Token"] == cookies[:farmspot_csrf]

    render json: { error: "Invalid CSRF token" }, status: :unauthorized
  end
end
