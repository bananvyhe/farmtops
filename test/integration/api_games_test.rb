require "test_helper"

class ApiGamesTest < ActionDispatch::IntegrationTest
  setup do
    host! "farmspot.test"

    Game.create!(name: "Elden Ring", slug: "elden-ring")
    Game.create!(name: "Another Game", slug: "another-game")
    Game.create!(name: "Path of Exile", slug: "path-of-exile")
  end

  test "searches games by prefix and returns selected ids first" do
    selected = Game.find_by!(slug: "path-of-exile")

    get "/api/games/search", params: { q: "el", ids: selected.id }

    assert_response :success
    names = json_response["games"].map { |game| game["name"] }
    assert_equal "Path of Exile", names.first
    assert_includes names, "Elden Ring"
    refute_includes names, "Another Game"
  end

  test "authenticated user can unfollow a game and leave its shared shard" do
    game = Game.create!(name: "Unfollow Game", slug: "unfollow-game")
    user = User.create!(email: "unfollow-game@example.com", password: "Password123!", password_confirmation: "Password123!", role: :client, active: true)
    csrf = login_as(user)
    NewsGameBookmark.create!(game: game, user: user, bookmarked_at: Time.current)
    shard = Shard.create!(game: game, user: user, name: "Unfollow Game", world_seed: "seed-unfollow", status: :draft)
    Shards::LayerAllocator.new(shard:, user:).call

    delete "/api/games/#{game.id}/follow", headers: { "X-CSRF-Token" => csrf }

    assert_response :success
    assert_equal false, json_response.dig("game", "bookmarked")
    assert_not NewsGameBookmark.exists?(game_id: game.id, user_id: user.id)
    assert_not ShardLayerMembership.exists?(shard_id: shard.id, user_id: user.id)
  end
end
