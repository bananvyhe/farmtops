class Shard < ApplicationRecord
  belongs_to :user
  belongs_to :game
  has_many :layers, class_name: "ShardLayer", dependent: :destroy
  has_many :layer_memberships, class_name: "ShardLayerMembership", dependent: :destroy

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

  def default_layer
    layers.order(:layer_index).first_or_create!(layer_index: 1)
  end
end
