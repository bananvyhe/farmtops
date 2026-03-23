require "securerandom"

module News
  module Translation
    class NullClient
      def translate_article(request_id: SecureRandom.uuid, source_lang:, target_lang:, title:, preview_text:, body_text:,
        canonical_url: nil, source_article_id: nil, content_hash: nil)
        Result.new(
          request_id: request_id,
          translated_title: title.to_s,
          translated_preview_text: preview_text.to_s,
          translated_body_text: body_text.to_s,
          model: "noop",
          latency_ms: 0,
          status: "ok",
          error: nil
        )
      end
    end
  end
end
