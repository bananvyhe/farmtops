class ShardLayer < ApplicationRecord
  belongs_to :shard
  has_many :memberships, class_name: "ShardLayerMembership", dependent: :destroy
  has_many :users, through: :memberships

  enum :status, { active: 0, paused: 1, closed: 2 }, default: :active

  validates :layer_index, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :layer_index, uniqueness: { scope: :shard_id }

  def occupancy
    memberships.count
  end

  def capacity
    10
  end

  def full?
    occupancy >= capacity
  end

  def available_capacity
    [capacity - occupancy, 0].max
  end
end
