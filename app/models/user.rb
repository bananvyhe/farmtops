class User < ApplicationRecord
  has_secure_password

  PRIME_SLOTS_RANGE = 0...168
  PRIME_CYCLE_DAYS_RANGE = 1..14
  PRIME_CYCLE_SLOTS_RANGE = 0...(14 * 24)
  NICKNAME_PATTERN = /\A[a-z][a-z0-9_-]{2,19}\z/
  REFERENCE_LOCAL_MONDAY = Date.new(2026, 1, 5)
  REFERENCE_UTC_MONDAY = Time.utc(2026, 1, 5, 0, 0, 0)

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
  validate :prime_cycle_days_must_be_valid
  validate :prime_cycle_slots_local_must_be_valid
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
    @prime_slots_legacy_assigned = true
    super(normalized_prime_slots(value))
  end

  def prime_cycle_days=(value)
    super(normalized_prime_cycle_days(value))
  end

  def prime_cycle_slots_local=(value)
    @prime_cycle_slots_local_assigned = true
    super(normalized_prime_cycle_slots(value, prime_cycle_days))
  end

  def nickname=(value)
    super(normalized_nickname(value))
  end

  def prime_cycle_days
    normalized_prime_cycle_days(self[:prime_cycle_days])
  end

  def prime_cycle_slots_local
    normalized_prime_cycle_slots(self[:prime_cycle_slots_local], prime_cycle_days)
  end

  def prime_cycle_anchor_on
    self[:prime_cycle_anchor_on] || REFERENCE_LOCAL_MONDAY
  end

  def prime_schedule_active?(time = Time.current)
    prime_cycle_slots_local.include?(current_prime_cycle_slot_local(time))
  end

  def prime_slots_utc_preview
    preview_weekly_slots_from_cycle
  end

  def prime_slot_overlap(other_user, from: Time.current, horizon_days: 14)
    return [] if other_user.blank?

    start_time = from.utc.beginning_of_hour
    Array.new(horizon_days * 24).filter_map do |offset|
      slot_time = start_time + offset.hours
      slot_time.iso8601 if prime_schedule_active?(slot_time) && other_user.prime_schedule_active?(slot_time)
    end
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
    self[:prime_cycle_days] = normalized_prime_cycle_days(prime_cycle_days)

    if @prime_slots_legacy_assigned && !@prime_cycle_slots_local_assigned
      self[:prime_cycle_days] = 7
      self[:prime_cycle_anchor_on] = REFERENCE_LOCAL_MONDAY
      self[:prime_cycle_slots_local] = normalized_prime_cycle_slots(
        convert_legacy_prime_slots_to_cycle_local(self[:prime_slots_utc], prime_time_zone),
        self[:prime_cycle_days]
      )
    else
      self[:prime_cycle_anchor_on] = normalized_prime_cycle_anchor_on(self[:prime_cycle_anchor_on], prime_time_zone)
      self[:prime_cycle_slots_local] = normalized_prime_cycle_slots(self[:prime_cycle_slots_local], self[:prime_cycle_days])
    end

    self[:prime_slots_utc] = preview_weekly_slots_from_cycle
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

  def normalized_prime_cycle_days(value)
    days = value.to_i
    return 7 if days <= 0

    [[days, PRIME_CYCLE_DAYS_RANGE.min].max, PRIME_CYCLE_DAYS_RANGE.max].min
  end

  def normalized_prime_cycle_slots(value, cycle_days)
    max_slot = normalized_prime_cycle_days(cycle_days) * 24
    Array(value).map(&:to_i).select { |slot| slot >= 0 && slot < max_slot && PRIME_CYCLE_SLOTS_RANGE.cover?(slot) }.uniq.sort
  end

  def normalized_prime_cycle_anchor_on(value, time_zone)
    return value if value.is_a?(Date)
    return Date.parse(value.to_s) if value.present?

    current_local_date_for(time_zone)
  rescue ArgumentError
    current_local_date_for(time_zone)
  end

  def current_local_date_for(time_zone)
    Time.find_zone!(time_zone).now.to_date
  end

  def current_prime_cycle_slot_local(time)
    local_time = time.in_time_zone(prime_time_zone)
    day_offset = (local_time.to_date - prime_cycle_anchor_on).to_i % prime_cycle_days
    (day_offset * 24) + local_time.hour
  end

  def convert_legacy_prime_slots_to_cycle_local(slots, time_zone)
    zone = Time.find_zone!(time_zone)

    normalized_prime_slots(slots).map do |slot|
      utc_time = REFERENCE_UTC_MONDAY + slot.hours
      local_time = utc_time.in_time_zone(zone)
      local_day_index = (local_time.wday + 6) % 7
      (local_day_index * 24) + local_time.hour
    end
  end

  def preview_weekly_slots_from_cycle
    zone = Time.find_zone!(prime_time_zone)

    prime_cycle_slots_local.filter_map do |slot|
      day_index = slot / 24
      next if day_index >= 7

      hour = slot % 24
      local_time = zone.local(
        REFERENCE_LOCAL_MONDAY.year,
        REFERENCE_LOCAL_MONDAY.month,
        REFERENCE_LOCAL_MONDAY.day + day_index,
        hour,
        0,
        0
      )
      utc_time = local_time.utc
      ((utc_time.wday + 6) % 7) * 24 + utc_time.hour
    end.uniq.sort
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

  def prime_cycle_days_must_be_valid
    return if PRIME_CYCLE_DAYS_RANGE.cover?(prime_cycle_days)

    errors.add(:prime_cycle_days, "must be between 1 and 14 days")
  end

  def prime_cycle_slots_local_must_be_valid
    max_slot = prime_cycle_days * 24
    return if prime_cycle_slots_local.all? { |slot| slot.is_a?(Integer) && slot >= 0 && slot < max_slot }

    errors.add(:prime_cycle_slots_local, "must contain unique local cycle hour slots within the selected cycle")
  end

  def prime_time_zone_must_be_valid
    TZInfo::Timezone.get(prime_time_zone)
  rescue TZInfo::InvalidTimezoneIdentifier
    errors.add(:prime_time_zone, "is invalid")
  end
end
