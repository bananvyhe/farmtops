require "test_helper"
require_relative "../../../app/services/news/translation/client"

class News::ArticleTranslatorTest < ActiveSupport::TestCase
  class FakeTranslator
    def initialize(result: nil, error: nil)
      @result = result
      @error = error
    end

    def translate_article(**)
      raise @error if @error

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

  def build_article(body_html: "<p>Body one</p><p>Body two</p>")
    @section.news_articles.create!(
      news_source: @source,
      news_section: @section,
      source_article_id: "article-1",
      canonical_url: "https://example.com/news/1",
      title: "Hello",
      preview_text: "Preview",
      preview_html: "<p>Preview</p>",
      body_text: "Body one\n\nBody two",
      body_html: body_html,
      image_url: "https://example.com/image.jpg",
      fetched_at: Time.current,
      content_hash: "hash-1",
      raw_payload: {},
      source_title: "Hello",
      source_preview_text: "Preview",
      source_body_text: "Body one\n\nBody two",
      translation_status: :pending,
      translation_target_locale: "ru",
      translation_source_locale: "en"
    )
  end

  test "translates and updates the saved article" do
    article = build_article
    result = News::Translation::Result.new(
      request_id: "req-1",
      translated_title: "Привет",
      translated_preview_text: "Превью",
      translated_body_text: "Тело один\n\nТело два",
      model: "fake-translator",
      latency_ms: 10,
      status: "ok",
      error: nil
    )

    translated = News::ArticleTranslator.new(
      article:,
      translator: FakeTranslator.new(result:)
    ).call

    assert_equal article.id, translated.id
    assert_equal "Привет", translated.title
    assert_equal "Превью", translated.preview_text
    assert_equal "Тело один\n\nТело два", translated.body_text
    assert_equal "translated", translated.translation_status
    assert_equal "fake-translator", translated.translation_model
    assert_not_nil translated.translated_at
    assert_not_nil translated.translation_completed_at
    assert_equal "req-1", translated.translation_request_id
    assert_equal "Hello", translated.source_title
    assert_equal "Body one\n\nBody two", translated.source_body_text
  end

  test "preserves embedded media blocks in translated body html" do
    article = build_article(
      body_html: <<~HTML
        <p>Body one</p>
        <div class="video">
          <iframe src="https://example.com/embed/video" allowfullscreen></iframe>
        </div>
        <p>Body two</p>
      HTML
    )

    result = News::Translation::Result.new(
      request_id: "req-2",
      translated_title: "Привет",
      translated_preview_text: "Превью",
      translated_body_text: "Тело один\n\nТело два",
      model: "fake-translator",
      latency_ms: 10,
      status: "ok",
      error: nil
    )

    translated = News::ArticleTranslator.new(
      article:,
      translator: FakeTranslator.new(result:)
    ).call

    assert_includes translated.body_html, "<iframe src=\"https://example.com/embed/video\""
    assert_includes translated.body_html, "Тело один"
    assert_includes translated.body_html, "Тело два"
  end

  test "keeps translating text blocks inside a container that also holds an embed" do
    article = build_article(
      body_html: <<~HTML
        <div class="articleBody">
          <h2>Heading one</h2>
          <p>Body one</p>
          <figure class="media">
            <blockquote class="twitter-tweet">
              <a href="https://twitter.com/example/status/1"></a>
            </blockquote>
          </figure>
          <h2>Heading two</h2>
          <p>Body two</p>
        </div>
      HTML
    )

    result = News::Translation::Result.new(
      request_id: "req-embed-container",
      translated_title: "Привет",
      translated_preview_text: "Превью",
      translated_body_text: "Заголовок один\n\nТело один\n\nЗаголовок два\n\nТело два",
      model: "fake-translator",
      latency_ms: 10,
      status: "ok",
      error: nil
    )

    translated = News::ArticleTranslator.new(
      article:,
      translator: FakeTranslator.new(result:)
    ).call

    assert_includes translated.body_html, "Заголовок один"
    assert_includes translated.body_html, "Тело один"
    assert_includes translated.body_html, "Заголовок два"
    assert_includes translated.body_html, "Тело два"
    assert_includes translated.body_html, "twitter-tweet"
  end

  test "keeps a body h1 as-is so it does not consume the first translated paragraph" do
    article = build_article(
      body_html: <<~HTML
        <div class="articleBody">
          <h1>Body title</h1>
          <p>Body one</p>
          <p>Body two</p>
        </div>
      HTML
    )

    result = News::Translation::Result.new(
      request_id: "req-h1",
      translated_title: "Привет",
      translated_preview_text: "Превью",
      translated_body_text: "Тело один\n\nТело два",
      model: "fake-translator",
      latency_ms: 10,
      status: "ok",
      error: nil
    )

    translated = News::ArticleTranslator.new(
      article:,
      translator: FakeTranslator.new(result:)
    ).call

    assert_includes translated.body_html, "Body title"
    assert_includes translated.body_html, "Тело один"
    assert_includes translated.body_html, "Тело два"
    assert_operator translated.body_html.index("Body title"), :<, translated.body_html.index("Тело один")
  end

  test "preserves image-only blocks in translated body html" do
    article = build_article(
      body_html: <<~HTML
        <p>Body one</p>
        <p><img src="https://example.com/image.jpg" alt="Example image"></p>
        <p>Body two</p>
      HTML
    )

    result = News::Translation::Result.new(
      request_id: "req-3",
      translated_title: "Привет",
      translated_preview_text: "Превью",
      translated_body_text: "Тело один\n\nТело два",
      model: "fake-translator",
      latency_ms: 10,
      status: "ok",
      error: nil
    )

    translated = News::ArticleTranslator.new(
      article:,
      translator: FakeTranslator.new(result:)
    ).call

    assert_includes translated.body_html, "<img src=\"https://example.com/image.jpg\" alt=\"Example image\">"
    assert_includes translated.body_html, "Тело один"
    assert_includes translated.body_html, "Тело два"
  end

  test "marks the article as failed when translation errors" do
    article = build_article

    translated = News::ArticleTranslator.new(
      article:,
      translator: FakeTranslator.new(error: News::Translation::Error.new("offline"))
    ).call

    assert_equal article.id, translated.id
    assert_equal "Hello", translated.title
    assert_equal "failed", translated.translation_status
    assert_nil translated.translated_at
    assert_match "offline", translated.translation_error
    assert_equal "Hello", translated.source_title
    assert_equal "Body one\n\nBody two", translated.source_body_text
  end
end
