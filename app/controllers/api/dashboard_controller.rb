module Api
  class DashboardController < BaseController
    before_action :ensure_authenticated!

    def show
      render json: {
        user: user_payload(current_user),
        recent_payments: current_user.payment_transactions.order(created_at: :desc).limit(10).map { |payment| payment_payload(payment) },
        recent_entries: current_user.balance_ledger_entries.order(created_at: :desc).limit(10).map { |entry| ledger_payload(entry) }
      }
    end
  end
end
