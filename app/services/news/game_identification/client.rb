require "json"
require "net/http"
require "securerandom"
require "uri"

module News
  module GameIdentification
    Error = Class.new(StandardError)

    class Client
      DEFAULT_BASE_URL = "http://127.0.0.1:19192"
      DEFAULT_TASK = "Identify the game mentioned in the article body and return only the English title or unknown."

      def initialize(base_url: game_identification_base_url,
        token: game_identification_token,
        open_timeout: game_identification_open_timeout,
        read_timeout: game_identification_read_timeout)
        @base_url = base_url
        @token = token
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      def identify_game(request_id: SecureRandom.uuid, article_id:, title: nil, preview_text: nil, body_text:, task: DEFAULT_TASK)
        response = post_json(
          game_identification_path,
          {
            request_id: request_id,
            article_id: article_id,
            title: title.to_s,
            preview_text: preview_text.to_s,
            body_text: body_text.to_s,
            task: task.to_s
          }.compact
        )

        result = Result.new(
          request_id: response.fetch("request_id", request_id),
          article_id: response.fetch("article_id", article_id),
          status: response["status"].to_s,
          identified_game_name: response["identified_game_name"].to_s.presence || "unknown",
          confidence: response["confidence"],
          model: response["model"].to_s,
          external_game_id: response["external_game_id"].presence,
          slug: response["slug"].presence,
          error: response["error"].presence
        )
        validate_result!(result)
        result
      end

      private

      attr_reader :base_url, :token, :open_timeout, :read_timeout

      def game_identification_path
        RuntimeConfig.env_or_credential("NEWS_GAME_ID_PATH", :game_identification, :path, default: "/identify/game")
      end

      def game_identification_base_url
        if Rails.env.development?
          return ENV["NEWS_GAME_ID_BASE_URL"].presence || RuntimeConfig.env_or_credential("NEWS_TRANSLATOR_BASE_URL", :translation, :base_url, default: DEFAULT_BASE_URL)
        end

        RuntimeConfig.env_or_credential(
          "NEWS_GAME_ID_BASE_URL",
          :game_identification,
          :base_url,
          default: RuntimeConfig.env_or_credential("NEWS_TRANSLATOR_BASE_URL", :translation, :base_url, default: DEFAULT_BASE_URL)
        )
      end

      def game_identification_token
        token = RuntimeConfig.env_or_credential("NEWS_GAME_ID_TOKEN", :game_identification, :token)
        token ||= RuntimeConfig.env_or_credential("NEWS_TRANSLATOR_TOKEN", :translation, :token)
        return token if token.present?

        raise Error, "Game identification token is not configured. Set NEWS_GAME_ID_TOKEN or credentials.game_identification.token." if Rails.env.production?

        nil
      end

      def game_identification_open_timeout
        RuntimeConfig.env_or_credential("NEWS_GAME_ID_OPEN_TIMEOUT_SECONDS", :game_identification, :open_timeout, default: 10).to_i
      end

      def game_identification_read_timeout
        RuntimeConfig.env_or_credential("NEWS_GAME_ID_READ_TIMEOUT_SECONDS", :game_identification, :read_timeout, default: 2400).to_i
      end

      def post_json(path, payload)
        uri = URI.join(base_url.end_with?("/") ? base_url : "#{base_url}/", path.delete_prefix("/"))

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout:, read_timeout:) do |http|
          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/json"
          request["Accept"] = "application/json"
          request["X-Game-Id-Token"] = token if token.present?
          request["X-Translation-Token"] = token if token.present?
          request["Authorization"] = "Bearer #{token}" if token.present?
          request.body = JSON.generate(payload)
          http.request(request)
        end

        body_text = response.body.to_s
        parsed_body = JSON.parse(body_text) rescue {}
        raise Error, parsed_body["error"].to_s.presence || "Game identification returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(body_text)
      rescue URI::InvalidURIError => e
        raise Error, "Game identification base URL is invalid: #{e.message}"
      rescue JSON::ParserError => e
        raise Error, "Game identification returned invalid JSON: #{e.message}"
      rescue SocketError, SystemCallError, Timeout::Error, Errno::ECONNREFUSED => e
        raise Error, "Game identification unavailable: #{e.message}"
      end

      def validate_result!(result)
        raise Error, result.error if result.status != "ok" && result.error.present?
        raise Error, "Game identification response missing identified_game_name" if result.identified_game_name.blank?
      end
    end
  end
end
