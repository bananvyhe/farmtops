module Users
  class BalanceManager
    class << self
      def apply_delta!(user:, amount_cents:, kind:, payment_transaction: nil, metadata: {}, lock: true)
        executor = lambda do
          new_balance = user.balance_cents + amount_cents

          user.update!(balance_cents: new_balance)
          user.balance_ledger_entries.create!(
            payment_transaction:,
            kind:,
            amount_cents:,
            balance_after_cents: new_balance,
            metadata:
          )
          user.reload
        end

        lock ? user.with_lock(&executor) : executor.call
      end
    end
  end
end
