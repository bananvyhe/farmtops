require "uri"

class NewsSource < ApplicationRecord
  BLOCKED_SOURCE_HOSTS = %w[theblock.co].freeze
  BLOCKED_SOURCE_BASE_URL_PATTERNS = BLOCKED_SOURCE_HOSTS.flat_map do |host|
    [
      "http://#{host}%",
      "https://#{host}%",
      "http://www.#{host}%",
      "https://www.#{host}%",
      "http://stage.#{host}%",
      "https://stage.#{host}%"
    ]
  end.freeze

  has_many :news_sections, dependent: :destroy
  has_many :news_articles, dependent: :destroy
  has_many :news_crawl_runs, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :base_url, presence: true
  validates :crawl_delay_min_seconds, numericality: { greater_than_or_equal_to: 0 }
  validates :crawl_delay_max_seconds, numericality: { greater_than_or_equal_to: 0 }

  before_validation :normalize_base_url
  before_validation :normalize_delay_bounds

  scope :active, -> { where(active: true).order(:name) }
  scope :crawlable, -> do
    where(active: true).where(
      BLOCKED_SOURCE_BASE_URL_PATTERNS.map { "base_url NOT LIKE ?" }.join(" AND "),
      *BLOCKED_SOURCE_BASE_URL_PATTERNS
    )
  end

  def delay_range
    min = [crawl_delay_min_seconds.to_f, 0.0].max
    max = [crawl_delay_max_seconds.to_f, min].max
    min..max
  end

  def crawlable?
    active? && !blocked_source?
  end

  def blocked_source?
    host = URI.parse(base_url.to_s).host.to_s.sub(/\Awww\./, "")
    BLOCKED_SOURCE_HOSTS.include?(host)
  rescue URI::InvalidURIError, URI::Error
    false
  end

  private

  def normalize_base_url
    self.base_url = base_url.to_s.strip
  end

  def normalize_delay_bounds
    self.crawl_delay_min_seconds = crawl_delay_min_seconds.to_i
    self.crawl_delay_max_seconds = [crawl_delay_max_seconds.to_i, crawl_delay_min_seconds.to_i].max
  end
end
