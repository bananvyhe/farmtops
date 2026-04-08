class Shard < ApplicationRecord
  belongs_to :user
  belongs_to :game

  enum :status, { draft: 0, active: 1, archived: 2 }, default: :draft

  validates :name, presence: true
  validates :world_seed, presence: true
  validates :game_id, uniqueness: { scope: :user_id }

  def self.build_name(game, user)
    "#{game.name} · #{user.nickname}"
  end

  def self.build_seed
    SecureRandom.alphanumeric(16).downcase
  end
end
