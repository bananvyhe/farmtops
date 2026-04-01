class NewsArticle < ApplicationRecord
  belongs_to :news_source
  belongs_to :news_section
  belongs_to :news_crawl_run, optional: true
  has_one :news_article_game, dependent: :destroy

  enum :translation_status, {
    pending: "pending",
    translating: "translating",
    translated: "translated",
    failed: "failed"
  }

  validates :canonical_url, presence: true
  validates :fetched_at, presence: true
  validates :content_hash, presence: true, uniqueness: { scope: :news_source_id }
  validates :source_article_id, uniqueness: { scope: :news_source_id, allow_nil: true }
  validates :translation_status, presence: true

  scope :recent, -> { order(Arel.sql("COALESCE(published_at, fetched_at, created_at) DESC"), id: :desc) }
  scope :pending_translation, -> { pending }
  scope :pending_translation_for_crawl_run, ->(crawl_run_id) do
    pending_translation.where(news_crawl_run_id: crawl_run_id)
  end
  scope :translating_for_crawl_run, ->(crawl_run_id) do
    translating.where(news_crawl_run_id: crawl_run_id)
  end
  scope :pending_game_identification, -> { translated.left_outer_joins(:news_article_game).where(news_article_games: { id: nil }) }
  scope :pending_game_identification_for_crawl_run, ->(crawl_run_id) do
    pending_game_identification.where(news_crawl_run_id: crawl_run_id)
  end

  def self.latest_pending_translation_crawl_run_id
    pending_translation.where.not(news_crawl_run_id: nil).order(news_crawl_run_id: :desc, created_at: :desc, id: :desc).pick(:news_crawl_run_id)
  end
end
