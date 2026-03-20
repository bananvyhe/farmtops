module Api
  class PaymentTransactionsController < BaseController
    before_action :ensure_authenticated!
    before_action :set_payment_transaction, only: :show

    def create
      amount_cents = (BigDecimal(params[:amount_rubles].to_s) * 100).to_i
      return render_error("Amount must be greater than zero", status: :unprocessable_entity) if amount_cents <= 0

      payment = current_user.payment_transactions.create!(
        label: "farmspot-#{SecureRandom.uuid}",
        requested_amount_cents: amount_cents,
        provider: "yoomoney",
        payment_method: params[:payment_method].presence || "bank_card"
      )

      form = Payments::YooMoneyForm.new(payment)
      render json: {
        payment: payment_payload(payment),
        form: {
          configured: form.configured?,
          endpoint: form.endpoint,
          card_fields: form.card_fields,
          wallet_fields: form.wallet_fields
        }
      }, status: :created
    rescue ArgumentError
      render_error("Invalid amount", status: :unprocessable_entity)
    end

    def show
      form = Payments::YooMoneyForm.new(@payment_transaction)
      render json: {
        payment: payment_payload(@payment_transaction),
        form: {
          configured: form.configured?,
          endpoint: form.endpoint,
          card_fields: form.card_fields,
          wallet_fields: form.wallet_fields
        }
      }
    end

    private

    def set_payment_transaction
      @payment_transaction = current_user.payment_transactions.find(params[:id])
    end
  end
end
