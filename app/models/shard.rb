class Shard < ApplicationRecord
  belongs_to :user
  belongs_to :game
  has_many :layers, class_name: "ShardLayer", dependent: :destroy
  has_many :layer_memberships, class_name: "ShardLayerMembership", dependent: :destroy
  has_many :chat_messages, class_name: "ShardChatMessage", dependent: :destroy

  enum :status, { draft: 0, active: 1, archived: 2 }, default: :draft

  validates :name, presence: true
  validates :world_seed, presence: true
  validates :game_id, uniqueness: true

  scope :visible_to_user, lambda { |user|
    left_outer_joins(:layer_memberships)
      .where("shards.user_id = :user_id OR shard_layer_memberships.user_id = :user_id", user_id: user.id)
      .distinct
  }

  def self.build_name(game, user = nil)
    return "#{game.name} · #{user.nickname}" if user.present?

    "#{game.name} · shared"
  end

  def self.build_seed
    SecureRandom.alphanumeric(16).downcase
  end

  def default_layer
    layers.order(:layer_index).first_or_create!(layer_index: 1)
  end
end
