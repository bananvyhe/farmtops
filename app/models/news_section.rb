class NewsSection < ApplicationRecord
  belongs_to :news_source

  has_many :news_articles, dependent: :destroy
  has_many :news_crawl_runs, dependent: :destroy

  validates :name, presence: true
  validates :url, presence: true

  before_validation :normalize_url

  scope :active, -> { where(active: true).order(:name) }

  private

  def normalize_url
    self.url = url.to_s.strip
  end
end
