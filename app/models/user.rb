class User < ApplicationRecord
  has_secure_password

  PRIME_SLOTS_RANGE = 0...168

  belongs_to :tariff, optional: true
  has_many :payment_transactions, dependent: :destroy
  has_many :balance_ledger_entries, dependent: :destroy
  has_many :news_game_bookmarks, dependent: :destroy

  enum :role, { admin: 0, user: 1, client: 2 }, default: :client

  normalizes :email, with: ->(value) { value.to_s.strip.downcase }

  validates :email, presence: true, uniqueness: true
  validates :hourly_rate_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :balance_cents, numericality: true
  validate :prime_time_zone_must_be_valid
  validate :prime_slots_utc_must_be_valid

  scope :billable, -> { where(active: true).where("COALESCE(hourly_rate_cents, 0) > 0 OR tariff_id IS NOT NULL") }
  scope :with_prime_overlap, ->(slots) { where("prime_slots_utc && ARRAY[?]::integer[]", Array(slots).map(&:to_i).uniq) }

  before_validation :normalize_prime_schedule!

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

  def prime_slots_utc=(value)
    super(normalized_prime_slots(value))
  end

  def prime_slot_overlap(other_user)
    prime_slots_utc & Array(other_user&.prime_slots_utc)
  end

  private

  def normalize_prime_schedule!
    self.prime_time_zone = prime_time_zone.to_s.presence || "UTC"
    self.prime_slots_utc = normalized_prime_slots(prime_slots_utc)
  end

  def normalized_prime_slots(value)
    Array(value).map(&:to_i).select { |slot| PRIME_SLOTS_RANGE.cover?(slot) }.uniq.sort
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
