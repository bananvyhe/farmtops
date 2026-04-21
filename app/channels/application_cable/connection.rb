module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = authenticate_user
      reject_unauthorized_connection if current_user.blank?
    end

    private

    def authenticate_user
      result = Auth::JwtCookieSession.authenticate(
        access_token: cookies[JWTSessions.access_cookie],
        refresh_token: cookies[JWTSessions.refresh_cookie]
      )
      result&.user
    rescue JWTSessions::Errors::Unauthorized, JWT::DecodeError, JWT::ExpiredSignature
      nil
    end
  end
end
