class ShardChatMessage < ApplicationRecord
  belongs_to :shard
  belongs_to :user

  validates :content, presence: true, length: { maximum: 500 }

  scope :recent_first, -> { order(created_at: :desc) }
  scope :chronological, -> { order(created_at: :asc) }
end
