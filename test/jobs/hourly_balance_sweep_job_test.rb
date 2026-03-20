require "test_helper"

class HourlyBalanceSweepJobTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email: "client-billing@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: :client,
      balance_cents: 50,
      hourly_rate_cents: 100,
      active: true
    )
  end

  test "deducts full hourly rate and allows negative balance" do
    travel_to Time.zone.parse("2026-03-08 10:15:00") do
      HourlyBalanceSweepJob.new.perform
    end

    assert_equal(-50, @user.reload.balance_cents)
    assert_equal("hourly_charge", @user.balance_ledger_entries.order(:created_at).last.kind)
  end

  test "does not double charge within the same hour" do
    travel_to Time.zone.parse("2026-03-08 10:15:00") do
      job = HourlyBalanceSweepJob.new
      job.perform
      job.perform
    end

    assert_equal(-50, @user.reload.balance_cents)
    assert_equal(1, @user.balance_ledger_entries.hourly_charge.count)
  end
end
