module Payments
  class YooMoneyForm
    ENDPOINT = "https://yoomoney.ru/quickpay/confirm".freeze

    def initialize(payment_transaction)
      @payment_transaction = payment_transaction
    end

    def configured?
      receiver.present?
    end

    def endpoint
      ENDPOINT
    end

    def wallet_fields
      base_fields.merge(paymentType: "PC")
    end

    def card_fields
      base_fields.merge(paymentType: "AC")
    end

    private

    attr_reader :payment_transaction

    def base_fields
      fields = {
        "receiver" => receiver,
        "quickpay-form" => "shop",
        "targets" => "Пополнение баланса #{payment_transaction.user.email}",
        "sum" => payment_transaction.requested_amount_rubles,
        "label" => payment_transaction.label
      }
      fields["successURL"] = success_url if success_url.present?
      fields
    end

    def receiver
      Rails.application.credentials.dig(:yoomoney, :receiver) || ENV["YOOMONEY_RECEIVER"]
    end

    def success_url
      base = Rails.application.credentials.dig(:app, :base_url) || ENV["APP_BASE_URL"]
      return if base.blank?

      "#{base.delete_suffix("/")}/payments/#{payment_transaction.id}"
    end
  end
end
