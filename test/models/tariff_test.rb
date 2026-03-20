require "test_helper"

class TariffTest < ActiveSupport::TestCase
  test "calculates hourly rate from monthly price in rubles" do
    tariff = Tariff.create!(
      name: "Standard",
      monthly_price_cents: 72000,
      billing_period_days: 30,
      active: true
    )

    assert_equal(100, tariff.hourly_rate_cents)
  end
end
