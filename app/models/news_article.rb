require "nokogiri"

class NewsArticle < ApplicationRecord
  belongs_to :news_source
  belongs_to :news_section
  belongs_to :news_crawl_run, optional: true
  has_one :news_article_game, dependent: :destroy
  has_many :news_article_tags, dependent: :destroy
  has_many :news_tags, through: :news_article_tags

  TAG_SELECTORS = %w[
    a[rel='tag']
    .tags a
    .tag-links a
    .entry-tags a
    .post-tags a
    .td-post-category a
    .cat-links a
    .entry-categories a
    meta[property='article:tag']
    meta[property='article:section']
  ].freeze

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

  scope :recent, -> { order(Arel.sql("COALESCE(news_articles.published_at, news_articles.fetched_at, news_articles.created_at) DESC"), id: :desc) }
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
    pending_translation.where.not(news_crawl_run_id: nil)
      .order(Arel.sql("news_articles.news_crawl_run_id DESC"), Arel.sql("news_articles.created_at DESC"), id: :desc)
      .pick(:news_crawl_run_id)
  end

  def replace_news_tags!(tag_names)
    normalized = Array(tag_names).map { |value| value.to_s.strip }.reject(&:blank?).uniq
    tags = normalized.map do |name|
      slug = NewsTag.normalize_slug(name)
      next if slug.blank?

      NewsTag.find_or_create_by!(slug:) do |tag|
        tag.name = name
      end
    end.compact

    self.news_tags = tags
  end

  def self.extract_tag_names_from_html(html)
    fragment = Nokogiri::HTML.fragment(html.to_s)
    names = fragment.css(TAG_SELECTORS.join(", ")).filter_map do |node|
      value = if node.name == "meta"
        node["content"]
      else
        node.text
      end

      value.to_s.strip.presence
    end

    names.map { |name| name.gsub(/\s+/, " ").strip }.reject(&:blank?).uniq
  end

  def self.extract_tag_names_from_payload(article)
    payload = article.raw_payload.to_h
    candidates = []
    candidates.concat(Array(payload["tags"]))
    candidates.concat(Array(payload["tag_names"]))
    candidates.concat(Array(payload["categories"]))
    candidates.concat(extract_tag_names_from_html(article.body_html))
    candidates.map { |value| value.to_s.strip }.reject(&:blank?).uniq
  end
end
