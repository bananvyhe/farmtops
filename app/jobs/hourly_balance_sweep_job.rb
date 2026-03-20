class HourlyBalanceSweepJob
  include Sidekiq::Job

  def perform
    billing_period_start = current_billing_period_start

    User.billable.find_each do |user|
      debit_user!(user, billing_period_start)
    end
  end

  private

  def debit_user!(user, billing_period_start)
    user.with_lock do
      return if user.last_hourly_charge_at.present? && user.last_hourly_charge_at >= billing_period_start
      return if user.effective_hourly_rate_cents <= 0

      Users::BalanceManager.apply_delta!(
        user:,
        amount_cents: -user.effective_hourly_rate_cents,
        kind: :hourly_charge,
        metadata: { billed_hour: billing_period_start.iso8601 },
        lock: false
      )
      user.update!(last_hourly_charge_at: billing_period_start)
    end
  end

  def current_billing_period_start
    interval_minutes =
      ENV.fetch("BILLING_INTERVAL_MINUTES", Rails.env.development? ? "20" : "60").to_i
    interval_minutes = 60 if interval_minutes <= 0

    now = Time.current
    interval_seconds = interval_minutes * 60
    Time.at((now.to_i / interval_seconds) * interval_seconds).in_time_zone
  end
end
