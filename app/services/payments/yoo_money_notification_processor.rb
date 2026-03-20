module Payments
  class YooMoneyNotificationProcessor
    def initialize(params)
      @params = params
    end

    def call
      return false unless Payments::YooMoneyNotificationVerifier.new(params).valid?

      payment = PaymentTransaction.find_by(label: params["label"])
      return false if payment.blank?

      payment.with_lock do
        return true if payment.paid? && payment.provider_operation_id == params["operation_id"]

        payment.update!(
          status: :paid,
          paid_at: Time.current,
          provider_operation_id: params["operation_id"],
          credited_amount_cents: credited_amount_cents(payment),
          provider_net_amount_cents: net_amount_cents,
          provider_payload: params
        )

        Users::BalanceManager.apply_delta!(
          user: payment.user,
          amount_cents: payment.credited_amount_cents,
          kind: :deposit,
          payment_transaction: payment,
          metadata: {
            provider: payment.provider,
            operation_id: payment.provider_operation_id
          }
        )
      end

      true
    rescue ActiveRecord::ActiveRecordError, ArgumentError => error
      Rails.logger.error("YooMoney notification failed: #{error.class}: #{error.message}")
      false
    end

    private

    attr_reader :params

    def credited_amount_cents(payment)
      # Credit exactly what user requested, regardless of provider fees.
      payment.requested_amount_cents
    end

    def net_amount_cents
      amount_to_cents(params["amount"])
    end

    def amount_to_cents(value)
      (BigDecimal(value.to_s) * 100).to_i
    end
  end
end
