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
end
