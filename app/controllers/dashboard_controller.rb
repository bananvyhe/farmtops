class DashboardController < ApplicationController
  before_action :require_authentication

  def show
    @user = current_user
    @payment_transaction = current_user.payment_transactions.build
    @recent_payments = current_user.payment_transactions.order(created_at: :desc).limit(10)
    @recent_entries = current_user.balance_ledger_entries.order(created_at: :desc).limit(10)
  end
end
