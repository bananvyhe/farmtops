require "test_helper"

class ApiNewsTest < ActionDispatch::IntegrationTest
  setup do
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

  test "returns a single article payload" do
    get "/api/news/#{@article.id}"

    assert_response :success
    assert_equal "Body", json_response.dig("article", "body_text")
    assert_equal "news-1", json_response.dig("article", "source_article_id")
    assert_equal "/api/news/#{@article.id}/image", json_response.dig("article", "image_url")
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
