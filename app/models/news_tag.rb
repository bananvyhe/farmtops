class NewsTag < ApplicationRecord
  has_many :news_article_tags, dependent: :destroy
  has_many :news_articles, through: :news_article_tags

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  before_validation :normalize_slug

  def self.normalize_slug(value)
    value.to_s.parameterize
  end

  private

  def normalize_slug
    self.slug = self.class.normalize_slug(slug.presence || name)
  end
end
