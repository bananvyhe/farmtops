require "test_helper"

class News::ArticleGameIdentifierTest < ActiveSupport::TestCase
  class FakeClient
    def initialize(result)
      @result = result
    end

    def identify_game(**)
      @result
    end
  end

  setup do
    @source = NewsSource.create!(
      name: "Example",
      base_url: "https://example.com",
      active: true,
      crawl_delay_min_seconds: 0,
      crawl_delay_max_seconds: 0
    )
    @section = @source.news_sections.create!(
      name: "Main",
      url: "https://example.com/news",
      active: true
    )
  end

  def build_article(body_text = "The article discusses Elden Ring.")
    @section.news_articles.create!(
      news_source: @source,
      news_section: @section,
      source_article_id: "article-1",
      canonical_url: "https://example.com/news/1",
      title: "Hello",
      preview_text: "Preview",
      body_text: body_text,
      body_html: "<p>Body</p>",
      fetched_at: Time.current,
      content_hash: "hash-1",
      raw_payload: {},
      source_title: "Hello",
      source_preview_text: "Preview",
      source_body_text: body_text,
      translation_status: :translated,
      translation_target_locale: "ru",
      translation_source_locale: "en"
    )
  end

  test "persists a detected game and links it to the article" do
    article = build_article
    result = News::GameIdentification::Result.new(
      request_id: "req-1",
      article_id: article.id,
      status: "ok",
      identified_game_name: "Elden Ring",
      confidence: 1.0,
      model: "model-path",
      external_game_id: "game-1",
      slug: "elden-ring",
      error: nil
    )

    News::ArticleGameIdentifier.new(article: article, client: FakeClient.new(result)).call(request_id: "req-1")

    article_game = article.reload.news_article_game
    assert_equal "Elden Ring", article_game.identified_game_name
    assert_equal "req-1", article_game.request_id
    assert_equal "elden-ring", article_game.slug
    assert_equal 1.0, article_game.confidence.to_f
    assert_equal "model-path", article_game.model
    assert_equal "game-1", article_game.external_game_id
    assert_equal "Elden Ring", article_game.game.name
    assert_equal "elden-ring", article_game.game.slug
  end

  test "stores unknown results without creating a game relation" do
    article = build_article("No game mentioned here.")
    result = News::GameIdentification::Result.new(
      request_id: "req-2",
      article_id: article.id,
      status: "ok",
      identified_game_name: "unknown",
      confidence: 0.0,
      model: "model-path",
      external_game_id: nil,
      slug: nil,
      error: nil
    )

    News::ArticleGameIdentifier.new(article: article, client: FakeClient.new(result)).call(request_id: "req-2")

    article_game = article.reload.news_article_game
    assert_equal "unknown", article_game.identified_game_name
    assert_nil article_game.game
  end
end
