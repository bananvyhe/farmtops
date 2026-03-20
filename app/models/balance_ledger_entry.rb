class BalanceLedgerEntry < ApplicationRecord
  belongs_to :user
  belongs_to :payment_transaction, optional: true

  enum :kind, {
    deposit: 0,
    hourly_charge: 1,
    import_adjustment: 2,
    manual_adjustment: 3
  }

  validates :amount_cents, presence: true
  validates :balance_after_cents, presence: true
end
