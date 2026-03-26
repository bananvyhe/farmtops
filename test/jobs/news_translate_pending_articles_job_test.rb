require "test_helper"

class NewsTranslatePendingArticlesJobTest < ActiveSupport::TestCase
  class FakeLockManager
    attr_reader :released

    def initialize(token: "lock-token", acquired: true)
      @token = token
      @acquired = acquired
      @released = false
    end

    def acquire
      @acquired ? @token : nil
    end

    def release(_token)
      @released = true
      true
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
  end

  test "enqueues the first pending article and keeps the chain lock" do
    lock_manager = FakeLockManager.new
    captured = nil

    News::Translation::LockManager.stub(:new, lock_manager) do
      NewsTranslateArticleJob.stub(:perform_async, ->(article_id, token) { captured = [article_id, token]; "jid-1" }) do
        NewsTranslatePendingArticlesJob.new.perform
      end
    end

    assert_equal [@first_article.id, "lock-token"], captured
    refute lock_manager.released
  end

  test "releases the lock when there is nothing to process" do
    @section.news_articles.delete_all
    lock_manager = FakeLockManager.new

    News::Translation::LockManager.stub(:new, lock_manager) do
      NewsTranslateArticleJob.stub(:perform_async, ->(*_) { flunk("should not enqueue") }) do
        NewsTranslatePendingArticlesJob.new.perform
      end
    end

    assert lock_manager.released
  end
end
