class ShardLayerMembership < ApplicationRecord
  PRESENCE_TTL = 15.seconds

  belongs_to :shard
  belongs_to :shard_layer
  belongs_to :user

  validates :joined_at, presence: true
  validates :last_seen_at, presence: true
  validates :user_id, uniqueness: { scope: :shard_id }

  scope :stale, ->(threshold = PRESENCE_TTL.ago) { where(last_seen_at: ...threshold) }
  scope :recent, ->(threshold = PRESENCE_TTL.ago) { where("last_seen_at >= ?", threshold) }

  def touch_presence!(timestamp = Time.current)
    update_columns(last_seen_at: timestamp)
  end

  def stale?(threshold = PRESENCE_TTL.ago)
    last_seen_at.blank? || last_seen_at < threshold
  end
end
