class User < ApplicationRecord
  has_secure_password

  PRIME_SLOTS_RANGE = 0...168
  NICKNAME_PATTERN = /\A[a-z][a-z0-9_-]{2,19}\z/

  belongs_to :tariff, optional: true
  has_many :payment_transactions, dependent: :destroy
  has_many :balance_ledger_entries, dependent: :destroy
  has_many :news_article_reads, dependent: :destroy
  has_many :news_game_bookmarks, dependent: :destroy
  has_many :shards, dependent: :destroy
  has_many :shard_layer_memberships, dependent: :destroy
  has_many :shard_chat_messages, dependent: :destroy

  enum :role, { admin: 0, user: 1, client: 2 }, default: :client

  normalizes :nickname, with: ->(value) { value.to_s.strip.downcase }
  normalizes :email, with: ->(value) { value.to_s.strip.downcase }

  validates :email, presence: true, uniqueness: true
  validates :nickname, presence: true, uniqueness: { case_sensitive: false }, format: { with: NICKNAME_PATTERN }
  validates :hourly_rate_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :balance_cents, numericality: true
  validates :world_level, numericality: { greater_than_or_equal_to: 1 }
  validates :world_xp_total, numericality: { greater_than_or_equal_to: 0 }
  validates :world_xp_bank, numericality: { greater_than_or_equal_to: 0 }
  validates :world_boss_kills, numericality: { greater_than_or_equal_to: 0 }
  validate :prime_time_zone_must_be_valid
  validate :prime_slots_utc_must_be_valid
  validate :nickname_change_allowed_only_once, if: :nickname_changed?

  scope :billable, -> { where(active: true).where("COALESCE(hourly_rate_cents, 0) > 0 OR tariff_id IS NOT NULL") }
  scope :with_prime_overlap, ->(slots) { where("prime_slots_utc && ARRAY[?]::integer[]", Array(slots).map(&:to_i).uniq) }

  before_validation :ensure_generated_nickname, on: :create
  before_validation :normalize_profile_fields!

  def balance_rubles
    balance_cents / 100.0
  end

  def requested_hourly_charge_rubles
    effective_hourly_rate_cents / 100.0
  end

  def remaining_days
    return nil if effective_hourly_rate_cents.zero?

    (balance_cents.to_f / effective_hourly_rate_cents / 24).round(2)
  end

  def jwt_namespace
    "user:#{id}"
  end

  def effective_hourly_rate_cents
    tariff&.hourly_rate_cents || hourly_rate_cents
  end

  def tariff_name
    tariff&.name || "Индивидуальный"
  end

  def can_change_nickname?
    !nickname_change_used?
  end

  def prime_slots_utc=(value)
    super(normalized_prime_slots(value))
  end

  def nickname=(value)
    super(normalized_nickname(value))
  end

  def prime_slot_overlap(other_user)
    prime_slots_utc & Array(other_user&.prime_slots_utc)
  end

  def world_level
    self[:world_level] || 1
  end

  def world_xp_total
    self[:world_xp_total] || 0
  end

  def world_xp_bank
    self[:world_xp_bank] || 0
  end

  def world_boss_kills
    self[:world_boss_kills] || 0
  end

  def world_xp_threshold_for(level)
    level = level.to_i
    return 0 if level <= 1

    ((level - 1)**2 * 1_000).to_i
  end

  def world_xp_to_next_level
    [world_xp_threshold_for(world_level.to_i + 1) - world_xp_total.to_i, 0].max
  end

  def apply_world_xp_bank!
    with_lock do
      banked_xp = world_xp_bank.to_i
      return 0 if banked_xp <= 0

      total_xp = world_xp_total.to_i + banked_xp
      level = world_level.to_i

      loop do
        threshold = world_xp_threshold_for(level + 1)
        break if threshold <= 0 || total_xp < threshold

        level += 1
      end

      update_columns(
        world_xp_total: total_xp,
        world_xp_bank: 0,
        world_level: level
      )
      banked_xp
    end
  end

  def self.generate_unique_nickname
    loop do
      candidate = "u_#{SecureRandom.alphanumeric(8).downcase}"
      return candidate unless exists?(nickname: candidate)
    end
  end

  private

  def normalize_profile_fields!
    self.nickname_change_used = true if persisted? && nickname_changed? && !nickname_change_used?
    self.prime_time_zone = prime_time_zone.to_s.presence || "UTC"
    self.prime_slots_utc = normalized_prime_slots(prime_slots_utc)
  end

  def ensure_generated_nickname
    self.nickname = self.class.generate_unique_nickname if nickname.blank?
  end

  def normalized_nickname(value)
    value.to_s.strip.downcase
  end

  def normalized_prime_slots(value)
    Array(value).map(&:to_i).select { |slot| PRIME_SLOTS_RANGE.cover?(slot) }.uniq.sort
  end

  def nickname_change_allowed_only_once
    return if new_record?
    return if nickname == nickname_was
    return unless nickname_change_used_was

    errors.add(:nickname, "can be changed only once")
  end

  def prime_slots_utc_must_be_valid
    return if Array(prime_slots_utc).all? { |slot| slot.is_a?(Integer) && PRIME_SLOTS_RANGE.cover?(slot) }

    errors.add(:prime_slots_utc, "must contain unique UTC weekly hour slots from 0 to 167")
  end

  def prime_time_zone_must_be_valid
    TZInfo::Timezone.get(prime_time_zone)
  rescue TZInfo::InvalidTimezoneIdentifier
    errors.add(:prime_time_zone, "is invalid")
  end
end
