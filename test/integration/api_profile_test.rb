require "test_helper"

class ApiProfileTest < ActionDispatch::IntegrationTest
  test "returns the authenticated user profile with prime schedule fields" do
    user = User.create!(
      email: "profile@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: :client,
      active: true,
      prime_time_zone: "Asia/Yekaterinburg",
      prime_slots_utc: [0, 1, 25]
    )

    login_as(user)

    get "/api/profile"

    assert_response :success
    assert_equal "profile@example.com", json_response.dig("user", "email")
    assert_match(/\Au_[a-z0-9]{8}\z/, json_response.dig("user", "nickname"))
    assert_equal "Asia/Yekaterinburg", json_response.dig("user", "prime_time_zone")
    assert_equal 7, json_response.dig("user", "prime_cycle_days")
    assert_equal Date.new(2026, 1, 5).iso8601, json_response.dig("user", "prime_cycle_anchor_on")
    assert_equal [5, 6, 30], json_response.dig("user", "prime_cycle_slots_local")
    assert_equal 3, json_response.dig("user", "prime_slots_count")
  end

  test "checks nickname availability" do
    taken = User.create!(
      email: "taken@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: :client,
      active: true
    )
    login_as(taken)

    get "/api/profile/nickname_check", params: { nickname: taken.nickname }

    assert_response :success
    assert_equal taken.nickname, json_response["normalized"]
    assert_equal true, json_response["available"]

    other = User.create!(
      email: "other@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: :client,
      active: true
    )

    get "/api/profile/nickname_check", params: { nickname: other.nickname }

    assert_response :success
    assert_equal false, json_response["available"]
  end

  test "allows nickname change only once" do
    user = User.create!(
      email: "nickname-once@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: :client,
      active: true
    )
    csrf_token = login_as(user)

    patch "/api/profile",
      params: { nickname: "alpha_bot" }.to_json,
      headers: { "CONTENT_TYPE" => "application/json", "X-CSRF-Token" => csrf_token }

    assert_response :success
    assert_equal "alpha_bot", json_response.dig("user", "nickname")
    assert_equal true, json_response.dig("user", "nickname_change_used")

    patch "/api/profile",
      params: { nickname: "beta_bot" }.to_json,
      headers: { "CONTENT_TYPE" => "application/json", "X-CSRF-Token" => csrf_token }

    assert_response :unprocessable_entity
    assert_includes json_response["errors"], "Nickname can be changed only once"
  end

  test "updates the authenticated user prime cycle schedule" do
    user = User.create!(
      email: "profile-update@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: :client,
      active: true
    )
    csrf_token = login_as(user)

    patch "/api/profile",
      params: {
        prime_time_zone: "Asia/Yekaterinburg",
        prime_cycle_days: 3,
        prime_cycle_anchor_on: "2026-04-24",
        prime_cycle_slots_local: [0, 1, 24, 25, 48, 50, 72]
      }.to_json,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "X-CSRF-Token" => csrf_token
      }

    assert_response :success
    assert_equal "Asia/Yekaterinburg", json_response.dig("user", "prime_time_zone")
    assert_equal 3, json_response.dig("user", "prime_cycle_days")
    assert_equal "2026-04-24", json_response.dig("user", "prime_cycle_anchor_on")
    assert_equal [0, 1, 24, 25, 48, 50], json_response.dig("user", "prime_cycle_slots_local")

    user.reload
    assert_equal "Asia/Yekaterinburg", user.prime_time_zone
    assert_equal 3, user.prime_cycle_days
    assert_equal Date.new(2026, 4, 24), user.prime_cycle_anchor_on
    assert_equal [0, 1, 24, 25, 48, 50], user.prime_cycle_slots_local
  end

  test "rejects invalid timezone values" do
    user = User.create!(
      email: "profile-invalid@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: :client,
      active: true
    )
    csrf_token = login_as(user)

    patch "/api/profile",
      params: {
        prime_time_zone: "Mars/Phobos",
        prime_slots_utc: [12]
      }.to_json,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "X-CSRF-Token" => csrf_token
      }

    assert_response :unprocessable_entity
    assert_includes json_response["errors"], "Prime time zone is invalid"
  end
end
