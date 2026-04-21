require "test_helper"

class ApiShardsTest < ActionDispatch::IntegrationTest
  def register_user!(session, email)
    session.post "/api/registration",
      params: {
        email: email,
        password: "Password123!",
        password_confirmation: "Password123!"
      }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }

    assert_equal 201, session.response.status
    session.response.parsed_body["csrf_token"]
  end

  test "creates a shard world with a default layer and active membership" do
    source = NewsSource.create!(
      name: "Example",
      base_url: "https://example.com",
      active: true,
      config: {}
    )
    section = source.news_sections.create!(
      name: "Main",
      url: "https://example.com/news",
      active: true,
      config: {}
    )
    article = section.news_articles.create!(
      news_source: source,
      news_section: section,
      source_article_id: "news-10",
      canonical_url: "https://example.com/news/10",
      title: "Shard world",
      preview_text: "Preview",
      body_text: "Body",
      image_url: "https://example.com/image10.jpg",
      published_at: Time.zone.parse("2026-03-21 10:00:00"),
      fetched_at: Time.zone.now,
      content_hash: "hash-10",
      raw_payload: {}
    )
    game = Game.create!(name: "Albion Online", slug: "albion-online")
    article.create_news_article_game!(
      game: game,
      request_id: "req-10",
      identified_game_name: "Albion Online",
      slug: "albion-online",
      confidence: 1.0,
      model: "test-model",
      raw_response: {}
    )

    post "/api/news/#{article.id}/bookmark_game"

    csrf_token = register_user!(self, "shard-world@example.com")

    post "/api/games/#{game.id}/shard", headers: { "X-CSRF-Token" => csrf_token }

    assert_response :created
    assert_equal game.id, json_response.dig("shard", "game_id")
    assert_equal 1, json_response.dig("layers", 0, "occupancy")

    shard_id = json_response.dig("shard", "id")
    get "/api/shards/#{shard_id}/world"

    assert_response :success
    assert_equal shard_id, json_response.dig("shard", "id")
    assert_equal 1, json_response.dig("layers", 0, "occupancy")
    assert_equal 1, json_response.dig("world", "progress", "members_count")
  end

  test "second user joins existing shared shard for the game" do
    game = Game.create!(name: "Lineage", slug: "lineage")

    first = open_session
    first_csrf_token = register_user!(first, "shared-world-first@example.com")
    first_user = User.find_by!(email: "shared-world-first@example.com")
    NewsGameBookmark.create!(game: game, user: first_user, bookmarked_at: Time.current)
    first.post "/api/games/#{game.id}/shard", headers: { "X-CSRF-Token" => first_csrf_token }
    assert_equal 201, first.response.status
    shard_id = first.response.parsed_body.dig("shard", "id")

    second = open_session
    second_csrf_token = register_user!(second, "shared-world-second@example.com")
    second_user = User.find_by!(email: "shared-world-second@example.com")
    NewsGameBookmark.create!(game: game, user: second_user, bookmarked_at: Time.current)
    second.post "/api/games/#{game.id}/shard", headers: { "X-CSRF-Token" => second_csrf_token }
    assert_equal 201, second.response.status
    assert_equal shard_id, second.response.parsed_body.dig("shard", "id")
    assert_equal 2, second.response.parsed_body.dig("layers", 0, "occupancy")

    second.get "/api/shards"
    assert_equal 200, second.response.status
    assert_equal [shard_id], second.response.parsed_body.fetch("shards").map { |shard| shard["id"] }
  end

  test "creates and reads shard chat messages" do
    game = Game.create!(name: "Aion", slug: "aion")
    csrf_token = register_user!(self, "chat-shard-user@example.com")
    user = User.find_by!(email: "chat-shard-user@example.com")
    NewsGameBookmark.create!(game: game, user: user, bookmarked_at: Time.current)

    post "/api/games/#{game.id}/shard", headers: { "X-CSRF-Token" => csrf_token }
    assert_response :created
    shard_id = json_response.dig("shard", "id")

    post "/api/shards/#{shard_id}/chat_messages",
      params: { content: "hello shard" }.to_json,
      headers: { "CONTENT_TYPE" => "application/json", "X-CSRF-Token" => csrf_token }

    assert_response :created
    assert_equal "hello shard", json_response.dig("message", "content")

    get "/api/shards/#{shard_id}/chat_messages"
    assert_response :success
    assert_equal 1, json_response.fetch("messages").size
    assert_equal "hello shard", json_response.dig("messages", 0, "content")
  end
end
