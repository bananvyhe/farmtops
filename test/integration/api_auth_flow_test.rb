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
    assert_match(/\Au_[a-z0-9]{8}\z/, json_response.dig("user", "nickname"))
    assert_empty cookies[:farmspot_visitor_id].to_s

    get "/api/news"
    assert_response :success
    assert_equal(true, json_response.dig("articles", 0, "read"))
    assert_equal(true, json_response.dig("articles", 0, "game", "bookmarked"))
  end

  test "logs in existing user" do
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
      source_article_id: "news-3",
      canonical_url: "https://example.com/news/3",
      title: "Hello 3",
      preview_text: "Preview 3",
      body_text: "Body 3",
      image_url: "https://example.com/image3.jpg",
      published_at: Time.zone.parse("2026-03-20 13:00:00"),
      fetched_at: Time.zone.now,
      content_hash: "hash-3",
      raw_payload: {}
    )
    game = Game.create!(name: "Hollow Knight", slug: "hollow-knight")
    article.create_news_article_game!(
      game: game,
      request_id: "req-3",
      identified_game_name: "Hollow Knight",
      slug: "hollow-knight",
      confidence: 1.0,
      model: "test-model",
      raw_response: {}
    )

    get "/api/news"
    post "/api/news/reads", params: { article_ids: [article.id] }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    post "/api/news/#{article.id}/bookmark_game"

    get "/api/news/#{article.id}"
    assert_response :success
    assert_equal true, json_response.dig("article", "read")
    assert_equal true, json_response.dig("article", "game", "bookmarked")

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
    assert_empty cookies[:farmspot_visitor_id].to_s

    get "/api/news"
    assert_response :success
    assert_equal false, json_response.dig("articles", 0, "read")
    assert_equal false, json_response.dig("articles", 0, "game", "bookmarked")
  end

  test "logout clears visitor identity and guest state" do
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
      source_article_id: "news-2",
      canonical_url: "https://example.com/news/2",
      title: "Hello 2",
      preview_text: "Preview 2",
      body_text: "Body 2",
      image_url: "https://example.com/image2.jpg",
      published_at: Time.zone.parse("2026-03-20 12:00:00"),
      fetched_at: Time.zone.now,
      content_hash: "hash-2",
      raw_payload: {}
    )
    game = Game.create!(name: "Hades", slug: "hades")
    article.create_news_article_game!(
      game: game,
      request_id: "req-2",
      identified_game_name: "Hades",
      slug: "hades",
      confidence: 1.0,
      model: "test-model",
      raw_response: {}
    )

    get "/api/news"
    post "/api/news/reads", params: { article_ids: [article.id] }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    post "/api/news/#{article.id}/bookmark_game"

    user = User.create!(
      email: "logout-check@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: :user,
      active: true
    )

    post "/api/session",
      params: { email: user.email, password: "Password123!" }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :success
    csrf_token = json_response["csrf_token"]

    delete "/api/session", headers: { "X-CSRF-Token" => csrf_token }

    assert_response :success
    assert_empty cookies[:farmspot_visitor_id].to_s

    get "/api/news"

    assert_response :success
    assert_equal false, json_response.dig("articles", 0, "read")
    assert_equal false, json_response.dig("articles", 0, "game", "bookmarked")
  end
end
