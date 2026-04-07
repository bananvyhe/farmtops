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
    assert_equal "Asia/Yekaterinburg", json_response.dig("user", "prime_time_zone")
    assert_equal [0, 1, 25], json_response.dig("user", "prime_slots_utc")
    assert_equal 3, json_response.dig("user", "prime_slots_count")
  end

  test "updates the authenticated user prime schedule in utc" do
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
        prime_slots_utc: [49, 50, 49, 170]
      }.to_json,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "X-CSRF-Token" => csrf_token
      }

    assert_response :success
    assert_equal "Asia/Yekaterinburg", json_response.dig("user", "prime_time_zone")
    assert_equal [49, 50], json_response.dig("user", "prime_slots_utc")

    user.reload
    assert_equal "Asia/Yekaterinburg", user.prime_time_zone
    assert_equal [49, 50], user.prime_slots_utc
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
