class NewsArticleGame < ApplicationRecord
  belongs_to :news_article
  belongs_to :game, optional: true

  validates :news_article_id, uniqueness: true
  validates :request_id, presence: true
  validates :identified_game_name, presence: true
end
