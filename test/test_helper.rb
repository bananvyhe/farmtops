ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

class ActiveSupport::TestCase
  parallelize(workers: 1)
end

module JsonResponseHelper
  def json_response
    JSON.parse(response.body)
  end
end

class ActionDispatch::IntegrationTest
  include JsonResponseHelper

  def login_as(user, password: "Password123!")
    post "/api/session", params: { email: user.email, password: }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :success
    json_response["csrf_token"]
  end
end
