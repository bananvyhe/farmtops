class ShardLayer < ApplicationRecord
  SHARED_LAYER_CAPACITY = 200

  belongs_to :shard
  has_many :memberships, class_name: "ShardLayerMembership", dependent: :destroy
  has_many :users, through: :memberships

  enum :status, { active: 0, paused: 1, closed: 2 }, default: :active

  validates :layer_index, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :layer_index, uniqueness: { scope: :shard_id }
  validates :campaign_target_players, numericality: { greater_than_or_equal_to: 2 }

  def world_state
    self[:world_state] || {}
  end

  def world_state=(value)
    super(value.presence || {})
  end

  def world_state_simulated_at
    self[:world_state_simulated_at]
  end

  def occupancy
    memberships.count
  end

  def capacity
    SHARED_LAYER_CAPACITY
  end

  def full?
    occupancy >= capacity
  end

  def available_capacity
    [capacity - occupancy, 0].max
  end

  def campaign_started?
    campaign_started_at.present?
  end
end
