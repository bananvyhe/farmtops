require "test_helper"

class ApiAuthFlowTest < ActionDispatch::IntegrationTest
  test "registers a user and returns authenticated session payload" do
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
      source_article_id: "news-1",
      canonical_url: "https://example.com/news/1",
      title: "Hello",
      preview_text: "Preview",
      body_text: "Body",
      image_url: "https://example.com/image.jpg",
      published_at: Time.zone.parse("2026-03-20 10:00:00"),
      fetched_at: Time.zone.now,
      content_hash: "hash-1",
      raw_payload: {}
    )
    game = Game.create!(
      name: "Elden Ring",
      slug: "elden-ring"
    )
    article.create_news_article_game!(
      game: game,
      request_id: "req-1",
      identified_game_name: "Elden Ring",
      slug: "elden-ring",
      confidence: 1.0,
      model: "test-model",
      raw_response: {}
    )

    get "/api/news"
    post "/api/news/reads",
      params: { article_ids: [article.id] }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }
    post "/api/news/#{article.id}/bookmark_game"

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

    get "/api/news"
    assert_response :success
    assert_equal(true, json_response.dig("articles", 0, "read"))
    assert_equal(true, json_response.dig("articles", 0, "game", "bookmarked"))
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
