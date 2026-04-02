require "securerandom"

module News
  class ArticleGameIdentifier
    def initialize(article:, client: News::GameIdentification::Client.new, logger: Rails.logger)
      @article = article
      @client = client
      @logger = logger
    end

    def call(request_id: SecureRandom.uuid)
      return article if article.news_article_game.present?
      return article if source_body_text.blank?

      result = client.identify_game(
        request_id: request_id,
        article_id: article.id,
        title: source_title,
        preview_text: source_preview_text,
        body_text: source_body_text
      )
      apply_result!(result)
      article
    rescue News::GameIdentification::Error => e
      logger.warn("[News::ArticleGameIdentifier] game identification failed for #{article.canonical_url}: #{e.message}")
      article
    end

    private

    attr_reader :article, :client, :logger

    def source_body_text
      article.source_body_text.presence || article.body_text.to_s
    end

    def source_title
      article.source_title.presence || article.title.to_s
    end

    def source_preview_text
      article.source_preview_text.presence || article.preview_text.to_s
    end

    def apply_result!(result)
      identified_game_name = result.identified_game_name.to_s.strip.presence || "unknown"
      slug = result.slug.to_s.strip.presence || normalized_slug(identified_game_name)
      game = game_for_result(identified_game_name, slug, result.external_game_id)

      article_game = article.news_article_game || article.build_news_article_game
      article_game.update!(
        game: game,
        request_id: result.request_id.presence || article_game.request_id.presence || SecureRandom.uuid,
        identified_game_name: identified_game_name,
        confidence: result.confidence,
        model: result.model.presence,
        external_game_id: result.external_game_id.presence,
        slug: slug,
        raw_response: result_to_raw_response(result)
      )
    end

    def game_for_result(identified_game_name, slug, external_game_id)
      return nil if identified_game_name.casecmp("unknown").zero?

      game = Game.find_or_match_by_identified_name!(
        identified_game_name: identified_game_name,
        slug: slug,
        external_game_id: external_game_id
      )

      updates = {}
      updates[:name] = identified_game_name if game.name.blank?
      updates[:external_game_id] = external_game_id if external_game_id.present? && game.external_game_id.blank?
      updates[:normalized_name] = normalized_name(identified_game_name) if game.respond_to?(:normalized_name) && game.normalized_name.blank?
      game.update!(updates) if updates.present?
      game
    end

    def normalized_slug(value)
      value.to_s.parameterize
    end

    def normalized_name(value)
      value.to_s.downcase.strip
    end

    def result_to_raw_response(result)
      {
        "request_id" => result.request_id,
        "article_id" => result.article_id,
        "status" => result.status,
        "identified_game_name" => result.identified_game_name,
        "confidence" => result.confidence,
        "model" => result.model,
        "external_game_id" => result.external_game_id,
        "slug" => result.slug,
        "error" => result.error
      }.compact
    end
  end
end
