require "test_helper"

class ApiAdminUsersTest < ActionDispatch::IntegrationTest
  test "admin users index includes shard subscriptions" do
    admin = User.create!(
      email: "admin-users@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: :admin,
      active: true,
      nickname: "admin_users"
    )
    csrf_token = login_as(admin)

    game = Game.create!(name: "Throne and Liberty", slug: "throne-liberty")
    user = User.create!(
      email: "member-users@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: :user,
      active: true,
      nickname: "member_users"
    )
    shard = Shard.create!(
      user: admin,
      game: game,
      name: "Shared TL",
      world_seed: "sharedseed123456",
      status: :active
    )
    layer = shard.default_layer
    ShardLayerMembership.create!(
      shard: shard,
      shard_layer: layer,
      user: user,
      joined_at: Time.current,
      last_seen_at: Time.current
    )

    get "/api/admin/users", headers: { "X-CSRF-Token" => csrf_token }

    assert_response :success
    payload = json_response.fetch("users").find { |item| item["id"] == user.id }
    assert_not_nil payload
    assert_equal 1, payload.fetch("shard_subscriptions").size
    assert_equal shard.id, payload.dig("shard_subscriptions", 0, "shard_id")
    assert_equal game.name, payload.dig("shard_subscriptions", 0, "game_name")
    assert_equal layer.layer_index, payload.dig("shard_subscriptions", 0, "layer_index")
  end
end
