class User < ApplicationRecord
  has_secure_password

  belongs_to :tariff, optional: true
  has_many :payment_transactions, dependent: :destroy
  has_many :balance_ledger_entries, dependent: :destroy

  enum :role, { admin: 0, user: 1, client: 2 }, default: :client

  normalizes :email, with: ->(value) { value.to_s.strip.downcase }

  validates :email, presence: true, uniqueness: true
  validates :hourly_rate_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :balance_cents, numericality: true

  scope :billable, -> { where(active: true).where("COALESCE(hourly_rate_cents, 0) > 0 OR tariff_id IS NOT NULL") }

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
end
