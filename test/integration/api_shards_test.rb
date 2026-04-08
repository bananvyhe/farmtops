require "test_helper"

class ApiShardsTest < ActionDispatch::IntegrationTest
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

    post "/api/registration",
      params: {
        email: "shard-world@example.com",
        password: "Password123!",
        password_confirmation: "Password123!"
      }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :created
    csrf_token = json_response["csrf_token"]

    post "/api/games/#{game.id}/shard", headers: { "X-CSRF-Token" => csrf_token }

    assert_response :created
    assert_equal game.id, json_response.dig("shard", "game_id")
    assert_equal 1, json_response.dig("layers", 0, "occupancy")
    assert_equal 1, json_response.dig("world", "players").size

    shard_id = json_response.dig("shard", "id")
    get "/api/shards/#{shard_id}/world"

    assert_response :success
    assert_equal shard_id, json_response.dig("shard", "id")
    assert_equal 1, json_response.dig("layers", 0, "occupancy")
    assert_equal 1, json_response.dig("world", "progress", "occupancy")
  end
end
