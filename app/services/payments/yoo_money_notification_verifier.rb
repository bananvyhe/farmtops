require "digest/sha1"

module Payments
  class YooMoneyNotificationVerifier
    def initialize(params)
      @params = params
    end

    def valid?
      return true if notification_secret.blank?
      return false if params["sha1_hash"].blank?

      ActiveSupport::SecurityUtils.secure_compare(params["sha1_hash"], expected_hash)
    end

    private

    attr_reader :params

    def expected_hash
      Digest::SHA1.hexdigest(
        [
          params["notification_type"],
          params["operation_id"],
          params["amount"],
          params["currency"],
          params["datetime"],
          params["sender"],
          params["codepro"],
          notification_secret,
          params["label"]
        ].join("&")
      )
    end

    def notification_secret
      Rails.application.credentials.dig(:yoomoney, :notification_secret) || ENV["YOOMONEY_NOTIFICATION_SECRET"]
    end
  end
end
