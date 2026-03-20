require "test_helper"

module Imports
  class FarmspotUsersImporterTest < ActiveSupport::TestCase
    test "imports bcrypt password digest, roles and negative balances" do
      digest = BCrypt::Password.create("Secret123!")
      rows = [
        {
          "id" => "77",
          "email" => "legacy@example.com",
          "encrypted_password" => digest.to_s,
          "username" => "legacy_user",
          "created_at" => "2024-01-01 10:00:00",
          "updated_at" => "2024-01-02 10:00:00",
          "client_balance" => "-12.34",
          "client_incoming" => "99.0",
          "client_spent" => "111.34",
          "role_names" => "client,applicant"
        }
      ]

      result = Imports::FarmspotUsersImporter.new(rows:).call
      user = User.find_by!(email: "legacy@example.com")

      assert_equal(1, result.imported)
      assert_equal("client", user.role)
      assert_equal(-1234, user.balance_cents)
      assert(user.authenticate("Secret123!"))
      assert_equal("farmspot:77", user.external_id)
    end
  end
end
