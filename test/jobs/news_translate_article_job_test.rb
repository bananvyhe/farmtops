require "test_helper"

class NewsTranslateArticleJobTest < ActiveSupport::TestCase
  class FakeLockManager
    attr_reader :released

    def initialize(token: "lock-token")
      @token = token
      @released = false
    end

    def current_token
      @token
    end

    def refresh(_token)
      true
    end

    def release(_token)
      @released = true
      true
    end
  end

  class FakeTranslator
    def initialize(article)
      @article = article
    end

    def call(request_id:)
      @article.update!(
        title: "Translated #{@article.title}",
        preview_text: "Translated #{@article.preview_text}",
        body_text: "Translated #{@article.body_text}",
        body_html: "<p>Translated #{@article.body_text}</p>",
        translated_at: Time.current,
        translation_completed_at: Time.current,
        translation_model: "fake-translator",
        translation_status: :translated,
        translation_request_id: request_id
      )
      @article
    end
  end

  setup do
    source = NewsSource.create!(
      name: "Example",
      base_url: "https://example.com",
      active: true,
      crawl_delay_min_seconds: 0,
      crawl_delay_max_seconds: 0
    )
    @section = source.news_sections.create!(
      name: "Main",
      url: "https://example.com/news",
      active: true
    )

    @first_article = @section.news_articles.create!(
      news_source: source,
      news_section: @section,
      source_article_id: "article-1",
      canonical_url: "https://example.com/news/1",
      title: "Article 1",
      preview_text: "Preview 1",
      body_text: "Body 1",
      body_html: "<p>Body 1</p>",
      fetched_at: Time.current,
      content_hash: "hash-1",
      raw_payload: {},
      source_title: "Article 1",
      source_preview_text: "Preview 1",
      source_body_text: "Body 1",
      translation_status: :pending,
      translation_target_locale: "ru",
      translation_source_locale: "en"
    )

    @second_article = @section.news_articles.create!(
      news_source: source,
      news_section: @section,
      source_article_id: "article-2",
      canonical_url: "https://example.com/news/2",
      title: "Article 2",
      preview_text: "Preview 2",
      body_text: "Body 2",
      body_html: "<p>Body 2</p>",
      fetched_at: Time.current,
      content_hash: "hash-2",
      raw_payload: {},
      source_title: "Article 2",
      source_preview_text: "Preview 2",
      source_body_text: "Body 2",
      translation_status: :pending,
      translation_target_locale: "ru",
      translation_source_locale: "en"
    )
  end

  test "translates a single article and enqueues the next one" do
    lock_manager = FakeLockManager.new
    captured = nil

    News::Translation::LockManager.stub(:new, lock_manager) do
      News::ArticleTranslator.stub(:new, ->(article:) { FakeTranslator.new(article) }) do
        NewsTranslateArticleJob.stub(:perform_async, ->(article_id, token) { captured = [article_id, token]; "jid-1" }) do
          NewsTranslateArticleJob.new.perform(@first_article.id, "lock-token")
        end
      end
    end

    assert_equal [@second_article.id, "lock-token"], captured
    assert_equal "translated", @first_article.reload.translation_status
    assert_equal "fake-translator", @first_article.reload.translation_model
    assert_predicate @first_article.reload.translation_request_id, :present?
    refute lock_manager.released
  end
end
