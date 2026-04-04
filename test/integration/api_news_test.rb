require "securerandom"
require "test_helper"

class ApiNewsTest < ActionDispatch::IntegrationTest
  setup do
    host! "farmspot.test"

    @source = NewsSource.create!(
      name: "Example",
      base_url: "https://example.com",
      active: true,
      config: {}
    )
    @section = @source.news_sections.create!(
      name: "Main",
      url: "https://example.com/news",
      active: true,
      config: {}
    )
    @article = @section.news_articles.create!(
      news_source: @source,
      news_section: @section,
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
    @game = Game.create!(
      name: "Elden Ring",
      slug: "elden-ring"
    )
    @article.create_news_article_game!(
      game: @game,
      request_id: "req-1",
      identified_game_name: "Elden Ring",
      slug: "elden-ring",
      confidence: 1.0,
      model: "test-model",
      raw_response: {}
    )
  end

  test "returns the public news wall payload" do
    get "/api/news"

    assert_response :success
    assert_equal 1, json_response["articles"].size
    assert_nil json_response["next_cursor"]
    assert_equal false, json_response["has_more"]
    assert_equal "Hello", json_response["articles"].first["title"]
    assert_equal "/api/news/#{@article.id}/image", json_response["articles"].first["image_url"]
    assert_equal "Example", json_response["sources"].first["name"]
    assert_equal "Main", json_response["sections"].first["name"]
    assert_equal "Example", json_response["sections"].first["source_name"]
  end

  test "hides blocked sources and their articles" do
    blocked_source = NewsSource.create!(
      name: "The Block",
      base_url: "https://stage.theblock.co",
      active: true,
      config: {}
    )
    blocked_section = blocked_source.news_sections.create!(
      name: "Latest",
      url: "https://stage.theblock.co/latest-crypto-news",
      active: true,
      config: {}
    )
    blocked_section.news_articles.create!(
      news_source: blocked_source,
      news_section: blocked_section,
      source_article_id: "blocked-1",
      canonical_url: "https://stage.theblock.co/post/1",
      title: "Blocked story",
      preview_text: "Blocked preview",
      body_text: "Blocked body",
      image_url: "https://stage.theblock.co/image.jpg",
      published_at: Time.zone.parse("2026-03-20 11:00:00"),
      fetched_at: Time.zone.now,
      content_hash: "blocked-hash",
      raw_payload: {}
    )

    get "/api/news"

    assert_response :success
    assert_equal ["Example"], json_response["sources"].map { |source| source["name"] }
    assert_equal ["Main"], json_response["sections"].map { |section| section["name"] }
    refute_includes json_response["articles"].map { |article| article["title"] }, "Blocked story"

    get "/api/news/#{blocked_section.news_articles.first.id}"
    assert_response :not_found
  end

  test "returns a single article payload" do
    get "/api/news/#{@article.id}"

    assert_response :success
    assert_equal "Body", json_response.dig("article", "body_text")
    assert_equal "news-1", json_response.dig("article", "source_article_id")
    assert_equal "/api/news/#{@article.id}/image", json_response.dig("article", "image_url")
    assert_equal false, json_response.dig("article", "read")
    assert_equal "Elden Ring", json_response.dig("article", "game", "name")
    assert_equal false, json_response.dig("article", "game", "bookmarked")
    assert_equal 0, json_response.dig("article", "game", "bookmarks_count")
  end

  test "returns bookmark counts for games in the news payload" do
    NewsGameBookmark.create!(
      game: @game,
      visitor_uuid: SecureRandom.uuid,
      bookmarked_at: Time.current
    )

    get "/api/news"

    assert_response :success
    assert_equal 1, json_response.dig("articles", 0, "game", "bookmarks_count")
  end

  test "returns a separate preview image url when listing metadata is available" do
    @article.update!(
      raw_payload: {
        "source_listing_image_url" => "https://example.com/thumb.jpg"
      }
    )

    get "/api/news/#{@article.id}"

    assert_response :success
    assert_equal "/api/news/#{@article.id}/preview_image", json_response.dig("article", "preview_image_url")
    assert_equal "/api/news/#{@article.id}/image", json_response.dig("article", "image_url")
  end

  test "removes a duplicated leading featured image from the article body" do
    @article.update!(
      image_url: "https://example.com/images/hero.jpg",
      body_html: <<~HTML
        <div class="td-post-featured-image">
          <img src="https://example.com/images/hero.jpg" width="1200" height="675">
        </div>
        <p>Main body paragraph.</p>
      HTML
    )

    get "/api/news/#{@article.id}"

    assert_response :success
    body_html = json_response.dig("article", "body_html")
    assert_includes body_html, "Main body paragraph."
    refute_includes body_html, "td-post-featured-image"
    refute_includes body_html, "hero.jpg"
  end

  test "rewrites twitch embed parents to the current host" do
    @article.update!(
      body_html: <<~HTML
        <p>Intro</p>
        <iframe
          src="https://player.twitch.tv/?channel=massivelyoverpowered&parent=massivelyop.com"
          width="640"
          height="360"
          allowfullscreen="true"
        ></iframe>
      HTML
    )

    get "/api/news/#{@article.id}"

    assert_response :success
    body_html = json_response.dig("article", "body_html")
    assert_includes body_html, "player.twitch.tv"
    assert_includes body_html, "parent=farmspot.test"
    refute_includes body_html, "parent=massivelyop.com"
  end

  test "drops invalid twitch parent values and keeps only the request host" do
    @article.update!(
      body_html: <<~HTML
        <iframe
          src="https://player.twitch.tv/?channel=massivelyoverpowered&parent=https://massivelyop.com/news"
          width="640"
          height="360"
          allowfullscreen="true"
        ></iframe>
      HTML
    )

    get "/api/news/#{@article.id}"

    assert_response :success
    body_html = json_response.dig("article", "body_html")
    assert_includes body_html, "parent=farmspot.test"
    refute_includes body_html, "parent=https://massivelyop.com/news"
    refute_includes body_html, "parent=massivelyop.com"
  end

  test "marks reads for an anonymous visitor and exposes the read flag" do
    get "/api/news"

    assert_response :success
    assert_equal false, json_response.dig("articles", 0, "read")

    post "/api/news/reads",
      params: { article_ids: [@article.id] }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :success
    assert_equal [@article.id], json_response["read_article_ids"]

    get "/api/news"

    assert_response :success
    assert_equal true, json_response.dig("articles", 0, "read")
  end

  test "bookmarks a game for an anonymous visitor and merges it on login" do
    post "/api/news/#{@article.id}/bookmark_game"

    assert_response :success
    assert_equal true, json_response.dig("game", "bookmarked")
    assert_equal 1, json_response.dig("game", "bookmarks_count")

    get "/api/news/#{@article.id}"

    assert_response :success
    assert_equal true, json_response.dig("article", "game", "bookmarked")

    post "/api/registration",
      params: {
        email: "bookmark@example.com",
        password: "Password123!",
        password_confirmation: "Password123!"
      }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :created

    get "/api/news/#{@article.id}"

    assert_response :success
    assert_equal true, json_response.dig("article", "game", "bookmarked")
  end

  test "unbookmarks a game" do
    post "/api/news/#{@article.id}/bookmark_game"
    assert_response :success

    delete "/api/news/#{@article.id}/unbookmark_game"

    assert_response :success
    assert_equal false, json_response.dig("game", "bookmarked")

    get "/api/news/#{@article.id}"
    assert_response :success
    assert_equal false, json_response.dig("article", "game", "bookmarked")
  end

  test "paginates with cursor" do
    older = @section.news_articles.create!(
      news_source: @source,
      news_section: @section,
      source_article_id: "news-0",
      canonical_url: "https://example.com/news/0",
      title: "Older",
      preview_text: "Older preview",
      body_text: "Older body",
      image_url: "https://example.com/older.jpg",
      published_at: Time.zone.parse("2026-03-19 10:00:00"),
      fetched_at: Time.zone.now,
      content_hash: "hash-0",
      raw_payload: {},
      body_html: "<p>Older body</p>"
    )

    get "/api/news", params: { limit: 1 }

    assert_response :success
    assert_equal 1, json_response["articles"].size
    assert_equal "Hello", json_response["articles"].first["title"]
    assert_equal true, json_response["has_more"]
    cursor = json_response["next_cursor"]
    assert cursor.present?

    get "/api/news", params: { limit: 1, cursor: cursor }

    assert_response :success
    assert_equal 1, json_response["articles"].size
    assert_equal "Older", json_response["articles"].first["title"]
    assert_equal false, json_response["has_more"]
    assert_nil json_response["next_cursor"]
    assert_equal older.id, json_response["articles"].first["id"]
  end
end
