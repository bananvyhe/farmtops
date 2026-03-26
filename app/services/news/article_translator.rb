require "erb"
require "securerandom"

module News
  class ArticleTranslator
    def initialize(article:, translator: News::Translation::Client.new, logger: Rails.logger)
      @article = article
      @translator = translator
      @logger = logger
    end

    def call
      return article if article.translated?
      return mark_failed!("Article is missing source text") if source_body_text.blank? && source_title.blank?

      translated = translator.translate_article(
        request_id: SecureRandom.uuid,
        source_lang: source_lang,
        target_lang: target_lang,
        title: source_title,
        preview_text: source_preview_text,
        body_text: source_body_text
      )

      apply_translation!(translated)
      article
    rescue News::Translation::Error => e
      mark_failed!(e.message)
      article
    end

    private

    attr_reader :article, :translator, :logger

    def source_lang
      article.translation_source_locale.presence || "en"
    end

    def target_lang
      article.translation_target_locale.presence || "ru"
    end

    def source_title
      article.source_title.presence || article.title.to_s
    end

    def source_preview_text
      article.source_preview_text.presence || article.preview_text.to_s
    end

    def source_body_text
      article.source_body_text.presence || article.body_text.to_s
    end

    def apply_translation!(translated)
      translated_title = translated.translated_title.to_s.strip.presence || source_title
      translated_preview_text = translated.translated_preview_text.to_s.strip.presence || source_preview_text
      translated_body_text = translated.translated_body_text.to_s.strip.presence || source_body_text

      article.update!(
        title: normalize_text(translated_title),
        preview_text: normalize_text(translated_preview_text),
        body_text: translated_body_text.presence,
        body_html: build_translated_body_html(translated_body_text),
        source_title: source_title,
        source_preview_text: source_preview_text,
        source_body_text: source_body_text,
        translated_at: Time.current,
        translation_model: translated.model.presence,
        translation_status: :translated,
        translation_completed_at: Time.current,
        translation_error: nil,
        translation_target_locale: target_lang,
        translation_source_locale: source_lang,
        raw_payload: article.raw_payload.merge(
          "source_title" => source_title,
          "source_preview_text" => source_preview_text,
          "source_preview_html" => article.preview_html,
          "source_body_text" => source_body_text,
          "source_body_html" => article.body_html,
          "translation_request_id" => translated.request_id,
          "translation_model" => translated.model,
          "translation_status" => translated.status
        ).compact
      )
    end

    def mark_failed!(message)
      logger.warn("[News::ArticleTranslator] translation failed for #{article.canonical_url}: #{message}")
      article.update!(
        source_title: source_title,
        source_preview_text: source_preview_text,
        source_body_text: source_body_text,
        translation_status: :failed,
        translation_completed_at: Time.current,
        translation_error: message,
        translation_target_locale: target_lang,
        translation_source_locale: source_lang,
        raw_payload: article.raw_payload.merge(
          "source_title" => source_title,
          "source_preview_text" => source_preview_text,
          "source_preview_html" => article.preview_html,
          "source_body_text" => source_body_text,
          "source_body_html" => article.body_html,
          "translation_status" => "failed",
          "translation_error" => message
        ).compact
      )
    end

    def normalize_text(value)
      value.to_s.strip
    end

    def build_translated_body_html(body_text)
      paragraphs = body_text.to_s.strip.split(/\n{2,}/).map(&:strip).reject(&:blank?)
      return "" if paragraphs.empty?

      paragraphs.map do |paragraph|
        "<p>#{ERB::Util.html_escape(paragraph).gsub(/\n/, "<br>")}</p>"
      end.join
    end
  end
end
