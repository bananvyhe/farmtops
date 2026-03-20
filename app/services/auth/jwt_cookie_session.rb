module Auth
  class JwtCookieSession
    Result = Struct.new(:user, :tokens, :refreshed, keyword_init: true) do
      def refreshed?
        refreshed
      end
    end

    class << self
      def authenticate(access_token:, refresh_token:)
        begin
          if access_token.present?
            user = user_from_access_token(access_token)
            return Result.new(user:, refreshed: false) if user
          end
        rescue JWTSessions::Errors::Unauthorized, JWT::DecodeError, JWT::ExpiredSignature
          nil
        end

        refresh(refresh_token)
      end

      def issue_for(user)
        session_for(user).login
      end

      def flush(refresh_token)
        return if refresh_token.blank?

        session = JWTSessions::Session.new
        session.flush_by_token(refresh_token)
      rescue JWTSessions::Errors::Unauthorized, JWT::DecodeError
        nil
      end

      private

      def user_from_access_token(access_token)
        payload = JWTSessions::Token.decode(access_token).first
        user = User.find_by(id: payload["user_id"], active: true)
        return if user.blank?

        session = session_for(user, payload:)
        return unless session.session_exists?(access_token, :access)

        user
      end

      def refresh(refresh_token)
        return if refresh_token.blank?

        refresh_payload = JWTSessions::Token.decode(refresh_token).first
        user = User.find_by(id: refresh_payload["user_id"], active: true)
        return if user.blank?

        session = session_for(user, payload: refresh_payload)
        tokens = session.refresh(refresh_token)
        Result.new(user:, tokens:, refreshed: true)
      rescue JWTSessions::Errors::Unauthorized, JWT::DecodeError, JWT::ExpiredSignature
        nil
      end

      def session_for(user, payload: nil)
        payload ||= { user_id: user.id, role: user.role }
        JWTSessions::Session.new(
          payload:,
          refresh_payload: { user_id: user.id, role: user.role },
          namespace: user.jwt_namespace,
          refresh_by_access_allowed: true
        )
      end
    end
  end
end
