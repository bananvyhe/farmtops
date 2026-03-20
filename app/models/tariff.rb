class Tariff < ApplicationRecord
  has_many :users, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :monthly_price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :hourly_rate_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :billing_period_days, numericality: { greater_than: 0 }

  before_validation :set_hourly_rate_from_monthly_price

  scope :active, -> { where(active: true).order(:monthly_price_cents, :name) }

  def monthly_price_rubles
    monthly_price_cents / 100.0
  end

  private

  def set_hourly_rate_from_monthly_price
    return if monthly_price_cents.blank? || billing_period_days.blank?

    self.hourly_rate_cents = (monthly_price_cents.to_d / (billing_period_days * 24)).round
  end
end
