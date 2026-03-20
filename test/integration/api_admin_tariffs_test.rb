require "test_helper"

class ApiAdminTariffsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(
      email: "admin-tariff@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: :admin,
      active: true
    )
    @tariff = Tariff.create!(
      name: "Delete me",
      monthly_price_cents: 30000,
      billing_period_days: 30,
      active: true
    )
    @user = User.create!(
      email: "client-with-tariff@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: :client,
      active: true,
      tariff: @tariff
    )
  end

  test "admin can delete tariff and user loses reference" do
    csrf = login_as(@admin)

    delete "/api/admin/tariffs/#{@tariff.id}",
      headers: {
        "CONTENT_TYPE" => "application/json",
        "X-CSRF-Token" => csrf
      }

    assert_response :no_content
    assert_nil(@user.reload.tariff_id)
    assert_not(Tariff.exists?(@tariff.id))
  end
end
