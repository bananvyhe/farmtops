class NewsArticle < ApplicationRecord
  belongs_to :news_source
  belongs_to :news_section

  enum :translation_status, {
    pending: "pending",
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
end
