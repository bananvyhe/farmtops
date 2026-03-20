class PaymentTransactionsController < ApplicationController
  before_action :require_authentication
  before_action :set_payment_transaction, only: :show

  def create
    amount_cents = (BigDecimal(params[:payment_transaction][:amount_rubles].to_s) * 100).to_i

    if amount_cents <= 0
      redirect_to dashboard_path, alert: "Укажите сумму пополнения больше нуля."
      return
    end

    @payment_transaction = current_user.payment_transactions.create!(
      label: "farmspot-#{SecureRandom.uuid}",
      requested_amount_cents: amount_cents,
      provider: "yoomoney",
      payment_method: "bank_card"
    )

    redirect_to payment_transaction_path(@payment_transaction), success: "Платёж создан. Перейдите к оплате."
  rescue ArgumentError
    redirect_to dashboard_path, alert: "Некорректная сумма."
  end

  def show
    @payment_form = Payments::YooMoneyForm.new(@payment_transaction)
  end

  private

  def set_payment_transaction
    @payment_transaction = current_user.payment_transactions.find(params[:id])
  end
end
