class Game < ApplicationRecord
  has_many :news_article_games, dependent: :nullify
  has_many :news_game_bookmarks, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
end
