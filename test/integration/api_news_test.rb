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
    assert_equal "Hello", json_response["articles"].first["title"]
    assert_equal "Example", json_response["sources"].first["name"]
    assert_equal "Main", json_response["sections"].first["name"]
    assert_equal "Example", json_response["sections"].first["source_name"]
  end

  test "returns a single article payload" do
    get "/api/news/#{@article.id}"

    assert_response :success
    assert_equal "Body", json_response.dig("article", "body_text")
    assert_equal "news-1", json_response.dig("article", "source_article_id")
  end
end
