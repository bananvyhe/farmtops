require "json"
require "net/http"
require "securerandom"
require "uri"

module News
  module Translation
    Error = Class.new(StandardError)

    class Client
      DEFAULT_PATH = "/translate/news"
      DEFAULT_BASE_URL = "http://127.0.0.1:19090"

      def initialize(base_url: translation_base_url,
        token: translation_token,
        open_timeout: translation_open_timeout,
        read_timeout: translation_read_timeout)
        @base_url = base_url
        @token = token
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      def translate_article(request_id: SecureRandom.uuid, source_lang:, target_lang:, title:, preview_text:, body_text:)
        response = post_json(
          DEFAULT_PATH,
          {
            request_id: request_id,
            source_lang: source_lang,
            target_lang: target_lang,
            title: title.to_s,
            preview_text: preview_text.to_s,
            body_text: body_text.to_s,
          }.compact
        )

        result = Result.new(
          request_id: response.fetch("request_id", request_id),
          translated_title: response["translated_title"].to_s,
          translated_preview_text: response["translated_preview_text"].to_s,
          translated_body_text: response["translated_body_text"].to_s,
          model: response["model"].to_s,
          latency_ms: response["latency_ms"],
          status: response["status"].to_s,
          error: response["error"].presence
        )
        validate_result!(result)
        result
      end

      private

      attr_reader :base_url, :token, :open_timeout, :read_timeout

      def translation_base_url
        RuntimeConfig.env_or_credential("NEWS_TRANSLATOR_BASE_URL", :translation, :base_url, default: DEFAULT_BASE_URL)
      end

      def translation_token
        token = RuntimeConfig.env_or_credential("NEWS_TRANSLATOR_TOKEN", :translation, :token)
        return token if token.present?

        raise Error, "Translation token is not configured. Set NEWS_TRANSLATOR_TOKEN or credentials.translation.token." if Rails.env.production?

        nil
      end

      def translation_open_timeout
        RuntimeConfig.env_or_credential("NEWS_TRANSLATOR_OPEN_TIMEOUT_SECONDS", :translation, :open_timeout, default: 10).to_i
      end

      def translation_read_timeout
        RuntimeConfig.env_or_credential("NEWS_TRANSLATOR_READ_TIMEOUT_SECONDS", :translation, :read_timeout, default: 900).to_i
      end

      def post_json(path, payload)
        uri = URI.join(base_url.end_with?("/") ? base_url : "#{base_url}/", path.delete_prefix("/"))

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout:, read_timeout:) do |http|
          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/json"
          request["Accept"] = "application/json"
          request["X-Translation-Token"] = token if token.present?
          request.body = JSON.generate(payload)
          http.request(request)
        end

        body_text = response.body.to_s
        parsed_body = JSON.parse(body_text) rescue {}
        raise Error, parsed_body["error"].to_s.presence || "Translator returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(body_text)
      rescue URI::InvalidURIError => e
        raise Error, "Translator base URL is invalid: #{e.message}"
      rescue JSON::ParserError => e
        raise Error, "Translator returned invalid JSON: #{e.message}"
      rescue SocketError, SystemCallError, Timeout::Error, Errno::ECONNREFUSED => e
        raise Error, "Translator unavailable: #{e.message}"
      end

      def validate_result!(result)
        raise Error, result.error if result.status != "ok" && result.error.present?
        raise Error, "Translator response missing translated_title" if result.translated_title.blank?
        raise Error, "Translator response missing translated_body_text" if result.translated_body_text.blank?
      end
    end
  end
end
