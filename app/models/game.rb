class Game < ApplicationRecord
  has_many :news_article_games, dependent: :nullify
  has_many :news_game_bookmarks, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

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
end
