class NewsArticleTag < ApplicationRecord
  belongs_to :news_article
  belongs_to :news_tag

  validates :news_article_id, uniqueness: { scope: :news_tag_id }
end
