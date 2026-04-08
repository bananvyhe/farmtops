class PaymentTransaction < ApplicationRecord
  belongs_to :user
  has_many :balance_ledger_entries, dependent: :destroy

  enum :status, { pending: 0, paid: 1, failed: 2, canceled: 3 }, default: :pending

  validates :label, presence: true, uniqueness: true
  validates :requested_amount_cents, numericality: { greater_than: 0 }
  validates :credited_amount_cents, :provider_net_amount_cents, numericality: { greater_than_or_equal_to: 0 }

  def requested_amount_rubles
    requested_amount_cents / 100.0
  end
end
