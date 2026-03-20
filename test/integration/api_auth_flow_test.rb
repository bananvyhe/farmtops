require "test_helper"

class ApiAuthFlowTest < ActionDispatch::IntegrationTest
  test "registers a user and returns authenticated session payload" do
    post "/api/registration",
      params: {
        email: "newuser@example.com",
        password: "Password123!",
        password_confirmation: "Password123!"
      }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :created
    assert_equal(true, json_response["authenticated"])
    assert_equal("newuser@example.com", json_response.dig("user", "email"))

    get "/api/session"
    assert_response :success
    assert_equal(true, json_response["authenticated"])
  end

  test "logs in existing user" do
    user = User.create!(
      email: "session@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: :user,
      active: true
    )

    post "/api/session",
      params: { email: user.email, password: "Password123!" }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :success
    assert_equal(user.email, json_response.dig("user", "email"))
    assert_not_nil(json_response["csrf_token"])
  end
end
