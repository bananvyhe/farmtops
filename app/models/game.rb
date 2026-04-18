class Game < ApplicationRecord
  has_many :news_article_games, dependent: :nullify
  has_many :news_game_bookmarks, dependent: :destroy
  has_many :shards, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  before_validation :normalize_name

  def self.find_or_match_by_identified_name!(identified_game_name:, slug:, external_game_id: nil)
    normalized = normalize_identified_name(identified_game_name)
    game = match_by_external_game_id(external_game_id)
    game ||= find_by(slug: slug) if slug.present?
    game ||= find_by(normalized_name: normalized) if normalized.present?
    game ||= where("LOWER(TRIM(name)) = ?", normalized).order(:created_at, :id).first if normalized.present?

    return game if game.present?

    create!(
      name: identified_game_name,
      slug: slug,
      normalized_name: normalized,
      external_game_id: external_game_id.presence
    )
  end

  def self.normalize_identified_name(value)
    value.to_s.downcase.strip.presence
  end

  def self.match_by_external_game_id(external_game_id)
    return nil if external_game_id.blank?

    find_by(external_game_id: external_game_id)
  end

  def followers_count
    news_game_bookmarks.count
  end

  def self.search_candidates(query:, limit: 20)
    normalized = normalize_identified_name(query)
    scope = all

    if normalized.present?
      pattern = "#{ActiveRecord::Base.sanitize_sql_like(normalized)}%"
      scope = scope.where(
        "normalized_name LIKE :pattern OR LOWER(slug) LIKE :pattern",
        pattern:
      )
    end

    scope.order(Arel.sql("normalized_name ASC NULLS LAST"), :id).limit(limit)
  end

  private

  def normalize_name
    self.normalized_name = self.class.normalize_identified_name(name)
  end
end
