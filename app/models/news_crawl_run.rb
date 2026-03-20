class NewsCrawlRun < ApplicationRecord
  belongs_to :news_source
  belongs_to :news_section, optional: true

  enum :status, { running: 0, succeeded: 1, failed: 2, skipped: 3 }, default: :running

  validates :started_at, presence: true
  validates :pages_visited, :articles_found, :articles_saved, :articles_skipped, numericality: { greater_than_or_equal_to: 0 }
end
