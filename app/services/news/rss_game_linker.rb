require "digest"

module News
  class RssGameLinker
    def initialize(article:, game_name:, logger: Rails.logger)
      @article = article
      @game_name = game_name.to_s.strip.presence
      @logger = logger
    end

    def call
      return unless game_name
      return if article.news_article_game.present?

      normalized = Game.normalize_identified_name(game_name)
      game = Game.find_by(normalized_name: normalized)
      game ||= Game.where("LOWER(TRIM(name)) = ?", normalized).order(:created_at, :id).first
      game ||= Game.find_or_match_by_identified_name!(identified_game_name: game_name, slug: game_slug(game_name))

      article.create_news_article_game!(
        game: game,
        request_id: "rss:#{article.id}",
        identified_game_name: game_name,
        slug: game.slug,
        confidence: 1.0,
        model: "rss",
        raw_response: { "source" => "rss", "game_name" => game_name }
      )
    rescue StandardError => e
      logger.warn("[News::RssGameLinker] failed for article #{article.id}: #{e.class} #{e.message}")
      nil
    end

    private

    attr_reader :article, :game_name, :logger

    def game_slug(name)
      base = name.to_s.parameterize.presence || "rss-game-#{Digest::SHA256.hexdigest(name.to_s)[0, 12]}"
      return base unless Game.exists?(slug: base)

      "#{base}-#{Digest::SHA256.hexdigest(name.to_s)[0, 8]}"
    end
  end
end
