module Api
  class BaseController < ApplicationController
    skip_forgery_protection
    before_action :verify_frontend_csrf!

    private

    def render_error(message, status:)
      render json: { error: message }, status:
    end

    def ensure_authenticated!
      return if user_signed_in?

      render_error("Authentication required", status: :unauthorized)
    end

    def ensure_admin!
      return if current_user&.admin?

      render_error("Admin access required", status: :forbidden)
    end

    def user_payload(user)
      {
        id: user.id,
        email: user.email,
        role: user.role,
        active: user.active,
        balance_cents: user.balance_cents,
        tariff_id: user.tariff_id,
        tariff_name: user.tariff_name,
        hourly_rate_cents: user.effective_hourly_rate_cents,
        manual_hourly_rate_cents: user.hourly_rate_cents,
        remaining_days: user.remaining_days,
        last_hourly_charge_at: user.last_hourly_charge_at
      }
    end

    def tariff_payload(tariff)
      {
        id: tariff.id,
        name: tariff.name,
        monthly_price_cents: tariff.monthly_price_cents,
        hourly_rate_cents: tariff.hourly_rate_cents,
        billing_period_days: tariff.billing_period_days,
        description: tariff.description,
        active: tariff.active
      }
    end

    def payment_payload(payment)
      {
        id: payment.id,
        label: payment.label,
        status: payment.status,
        requested_amount_cents: payment.requested_amount_cents,
        credited_amount_cents: payment.credited_amount_cents,
        provider_net_amount_cents: payment.provider_net_amount_cents,
        paid_at: payment.paid_at,
        created_at: payment.created_at
      }
    end

    def ledger_payload(entry)
      {
        id: entry.id,
        kind: entry.kind,
        amount_cents: entry.amount_cents,
        balance_after_cents: entry.balance_after_cents,
        metadata: entry.metadata,
        created_at: entry.created_at
      }
    end
  end
end
