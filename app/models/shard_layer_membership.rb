class ShardLayerMembership < ApplicationRecord
  belongs_to :shard
  belongs_to :shard_layer
  belongs_to :user

  validates :joined_at, presence: true
  validates :last_seen_at, presence: true
  validates :user_id, uniqueness: { scope: :shard_id }
end
