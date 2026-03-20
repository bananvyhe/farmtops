require "test_helper"

module Users
  class BalanceManagerTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(
        email: "balance@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        role: :client,
        balance_cents: 0,
        active: true
      )
    end

    test "allows negative balance values" do
      Users::BalanceManager.apply_delta!(
        user: @user,
        amount_cents: -250,
        kind: :manual_adjustment,
        metadata: { reason: "test" }
      )

      assert_equal(-250, @user.reload.balance_cents)
      assert_equal(-250, @user.balance_ledger_entries.last.balance_after_cents)
    end
  end
end
