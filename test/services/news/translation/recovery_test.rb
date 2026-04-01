require "test_helper"

class News::Translation::RecoveryTest < ActiveSupport::TestCase
  class FakeLockManager
    attr_reader :cleared

    def initialize
      @cleared = false
    end

    def clear
      @cleared = true
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
    @crawl_run = @section.news_crawl_runs.create!(
      news_source: source,
      status: :succeeded,
      started_at: 4.hours.ago,
      finished_at: 3.hours.ago
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
    @stalled_translating = build_article(
      source:,
      source_article_id: "article-stalled",
      canonical_url: "https://example.com/news/stalled",
      content_hash: "hash-stalled",
      created_at: 3.days.ago,
      translation_status: :translating,
      translation_started_at: 2.days.ago,
      translation_error: "still working"
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

  test "clears the lock and requeues fresh failed and stalled translating articles" do
    lock_manager = FakeLockManager.new
    enqueued = []

    NewsTranslatePendingArticlesJob.stub(:perform_async, ->(crawl_run_id = nil) { enqueued << crawl_run_id; "jid-1" }) do
      result = News::Translation::Recovery.new(lock_manager:, failure_window: 24.hours).call(@crawl_run.id)

      assert_equal true, result[:cleared_lock]
      assert_equal 2, result[:reset_recent_failed]
      assert_equal [@crawl_run.id], enqueued
    end

    assert lock_manager.cleared
    assert_equal "pending", @recent_failed.reload.translation_status
    assert_nil @recent_failed.reload.translation_error
    assert_equal "failed", @old_failed.reload.translation_status
    assert_equal "pending", @stalled_translating.reload.translation_status
    assert_nil @stalled_translating.reload.translation_started_at
    assert_equal "pending", @pending.reload.translation_status
  end

  private

  def build_article(source:, source_article_id: "article-1", canonical_url: "https://example.com/news/1",
    content_hash: "hash-1", created_at: Time.current, translation_status:, translation_error: nil,
    translation_started_at: nil)
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
      news_crawl_run: @crawl_run,
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
      translation_started_at: translation_started_at,
      translation_target_locale: "ru",
      translation_source_locale: "en"
    )
  end
end
