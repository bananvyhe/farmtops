require "test_helper"

class News::Translation::RecoveryTest < ActiveSupport::TestCase
  class FakeRedis
    def initialize
      @store = {}
    end

    def set(key, value, nx: false, ex: nil)
      return false if nx && @store.key?(key)

      @store[key] = value
      true
    end

    def get(key)
      @store[key]
    end

    def del(key)
      @store.delete(key).present? ? 1 : 0
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

    @recent_failed = build_article(
      source:,
      created_at: 2.hours.ago,
      translation_status: :failed,
      translation_error: "offline"
    )
    @old_failed = build_article(
      source:,
      source_article_id: "article-old",
      canonical_url: "https://example.com/news/old",
      content_hash: "hash-old",
      created_at: 3.days.ago,
      translation_status: :failed,
      translation_error: "offline"
    )
    @pending = build_article(
      source:,
      source_article_id: "article-pending",
      canonical_url: "https://example.com/news/pending",
      content_hash: "hash-pending",
      created_at: 1.hour.ago,
      translation_status: :pending,
      translation_error: nil
    )
  end

  test "clears the lock and requeues fresh failed articles" do
    redis = FakeRedis.new
    redis.set(
      NewsTranslatePendingArticlesJob::LOCK_KEY,
      "stale-token",
      nx: true,
      ex: NewsTranslatePendingArticlesJob::LOCK_TTL_SECONDS
    )

    enqueued = []
    result = nil

    NewsTranslatePendingArticlesJob.stub(:perform_async, -> { enqueued << true; "jid-1" }) do
      result = News::Translation::Recovery.new(redis:, failure_window: 24.hours).call
    end

    assert_equal true, result[:cleared_lock]
    assert_equal 1, result[:reset_recent_failed]
    assert_equal 1, enqueued.size
    assert_equal "pending", @recent_failed.reload.translation_status
    assert_nil @recent_failed.reload.translation_error
    assert_equal "failed", @old_failed.reload.translation_status
    assert_equal "pending", @pending.reload.translation_status
  end

  private

  def build_article(source:, source_article_id: "article-1", canonical_url: "https://example.com/news/1",
    content_hash: "hash-1", created_at: Time.current, translation_status:, translation_error:)
    @section.news_articles.create!(
      news_source: source,
      news_section: @section,
      source_article_id: source_article_id,
      canonical_url: canonical_url,
      title: "Hello",
      preview_text: "Preview",
      preview_html: "<p>Preview</p>",
      body_text: "Body one\n\nBody two",
      body_html: "<p>Body one</p><p>Body two</p>",
      image_url: "https://example.com/image.jpg",
      fetched_at: created_at,
      created_at: created_at,
      updated_at: created_at,
      content_hash: content_hash,
      raw_payload: {},
      source_title: "Hello",
      source_preview_text: "Preview",
      source_body_text: "Body one\n\nBody two",
      translation_status: translation_status,
      translation_error: translation_error,
      translation_target_locale: "ru",
      translation_source_locale: "en"
    )
  end
end
