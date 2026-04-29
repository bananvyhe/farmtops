require "securerandom"

module News
  class ArticleTranslator
    def initialize(article:, translator: News::Translation::Client.new, logger: Rails.logger)
      @article = article
      @translator = translator
      @logger = logger
    end

    def call(request_id: SecureRandom.uuid)
      return article if article.translated?
      return mark_failed!("Article is missing source text") if source_body_text.blank? && source_title.blank?

      source_tag_names = source_tag_names_for_translation
      translated = translator.translate_article(
        request_id: request_id,
        source_lang: source_lang,
        target_lang: target_lang,
        title: source_title,
        preview_text: source_preview_text,
        body_text: source_body_text
      )

      translated_tag_names = translate_tag_names(source_tag_names, request_id: request_id)

      apply_translation!(translated, source_tag_names: source_tag_names, translated_tag_names: translated_tag_names)
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

    def source_tag_names_for_translation
      article.news_tags.order(:name).map(&:name)
    end

    def translate_tag_names(source_tag_names, request_id:)
      normalized = Array(source_tag_names).map { |value| value.to_s.strip }.reject(&:blank?).uniq
      return normalized if normalized.blank? || source_lang == target_lang

      translated = translator.translate_article(
        request_id: "#{request_id}-tags",
        source_lang: source_lang,
        target_lang: target_lang,
        title: normalized.first,
        preview_text: normalized.join("\n"),
        body_text: normalized.join("\n\n")
      )
      parsed = split_tag_translations(
        translated.translated_body_text.presence || translated.translated_preview_text.presence || translated.translated_title.presence
      )
      parsed.presence || normalized
    rescue News::Translation::Error => e
      logger.warn("[News::ArticleTranslator] tag translation failed for #{article.canonical_url}: #{e.message}")
      normalized.presence || Array(source_tag_names)
    end

    def split_tag_translations(text)
      text.to_s
        .split(/\r?\n+/)
        .map { |value| value.to_s.strip }
        .reject(&:blank?)
        .uniq
    end

    def apply_translation!(translated, source_tag_names:, translated_tag_names:)
      translation_request_id = translated.request_id.presence || article.translation_request_id.presence
      translated_title = translated.translated_title.to_s.strip.presence || source_title
      translated_preview_text = translated.translated_preview_text.to_s.strip.presence || source_preview_text
      translated_body_text = translated.translated_body_text.to_s.strip.presence || source_body_text
      source_tags = Array(source_tag_names).map { |value| value.to_s.strip }.reject(&:blank?).uniq
      translated_tags = Array(translated_tag_names).map { |value| value.to_s.strip }.reject(&:blank?).uniq

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
        translation_request_id: translation_request_id,
        translation_target_locale: target_lang,
        translation_source_locale: source_lang,
        raw_payload: article.raw_payload.merge(
          "source_title" => source_title,
          "source_preview_text" => source_preview_text,
          "source_preview_html" => article.preview_html,
          "source_body_text" => source_body_text,
          "source_body_html" => article.body_html,
          "source_tag_names" => source_tags,
          "translated_tag_names" => translated_tags,
          "translation_request_id" => translation_request_id,
          "translation_model" => translated.model,
          "translation_status" => translated.status
        ).compact
      )
      article.replace_news_tags!(translated_tags.presence || source_tags) if source_tags.present?
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
        translation_request_id: article.translation_request_id.presence,
        translation_target_locale: target_lang,
        translation_source_locale: source_lang,
        raw_payload: article.raw_payload.merge(
          "source_title" => source_title,
          "source_preview_text" => source_preview_text,
          "source_preview_html" => article.preview_html,
          "source_body_text" => source_body_text,
          "source_body_html" => article.body_html,
          "translation_request_id" => article.translation_request_id,
          "translation_status" => "failed",
          "translation_error" => message
        ).compact
      )
    end

    def normalize_text(value)
      value.to_s.strip
    end

    def build_translated_body_html(body_text)
      News::Translation::HtmlBodyRenderer.new(source_html: article.body_html).call(body_text)
    end
  end
end
