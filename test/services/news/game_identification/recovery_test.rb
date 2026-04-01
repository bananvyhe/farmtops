require "test_helper"

class News::GameIdentification::RecoveryTest < ActiveSupport::TestCase
  class FakeLockManager
    attr_reader :cleared

    def clear
      @cleared = true
      true
    end
  end

  def with_stubbed_constant(object, method_name, implementation)
    original = object.method(method_name)
    object.define_singleton_method(method_name, &implementation)
    yield
  ensure
    object.define_singleton_method(method_name) do |*args, **kwargs, &block|
      original.call(*args, **kwargs, &block)
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

    @older_run = @section.news_crawl_runs.create!(
      news_source: source,
      status: :succeeded,
      started_at: 2.hours.ago,
      finished_at: 90.minutes.ago
    )

    @newer_run = @section.news_crawl_runs.create!(
      news_source: source,
      status: :succeeded,
      started_at: 1.hour.ago,
      finished_at: 30.minutes.ago
    )

    @section.news_articles.create!(
      news_source: source,
      news_section: @section,
      news_crawl_run: @older_run,
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
      translation_status: :translated,
      translation_target_locale: "ru",
      translation_source_locale: "en"
    )

    @section.news_articles.create!(
      news_source: source,
      news_section: @section,
      news_crawl_run: @newer_run,
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
      translation_status: :translated,
      translation_target_locale: "ru",
      translation_source_locale: "en"
    )
  end

  test "enqueues only the newest crawl run with pending games" do
    lock_manager = FakeLockManager.new
    captured = nil

    with_stubbed_constant(News::GameIdentification::LockManager, :new, -> { lock_manager }) do
      with_stubbed_constant(NewsIdentifyPendingGamesJob, :perform_async, ->(crawl_run_id) {
        captured = crawl_run_id
        "jid-1"
      }) do
        result = described_class.new(lock_manager: lock_manager).call

        assert_equal @newer_run.id, captured
        assert_equal({ cleared_lock: true, ready: true, enqueued: true }, result)
      end
    end

    assert lock_manager.cleared
  end

  test "does not enqueue when translations are still pending" do
    @section.news_articles.create!(
      news_source: @section.news_source,
      news_section: @section,
      news_crawl_run: @newer_run,
      source_article_id: "article-3",
      canonical_url: "https://example.com/news/3",
      title: "Article 3",
      preview_text: "Preview 3",
      body_text: "Body 3",
      body_html: "<p>Body 3</p>",
      fetched_at: Time.current,
      content_hash: "hash-3",
      raw_payload: {},
      source_title: "Article 3",
      source_preview_text: "Preview 3",
      source_body_text: "Body 3",
      translation_status: :pending,
      translation_target_locale: "ru",
      translation_source_locale: "en"
    )

    lock_manager = FakeLockManager.new

    with_stubbed_constant(NewsIdentifyPendingGamesJob, :perform_async, ->(*_) { flunk("should not enqueue") }) do
      result = described_class.new(lock_manager: lock_manager).call

      assert_equal({ cleared_lock: true, ready: false, enqueued: nil }, result)
    end
  end

  test "does not enqueue for a crawl run that still has translating articles" do
    @section.news_articles.create!(
      news_source: @section.news_source,
      news_section: @section,
      news_crawl_run: @newer_run,
      source_article_id: "article-3",
      canonical_url: "https://example.com/news/3",
      title: "Article 3",
      preview_text: "Preview 3",
      body_text: "Body 3",
      body_html: "<p>Body 3</p>",
      fetched_at: Time.current,
      content_hash: "hash-3",
      raw_payload: {},
      source_title: "Article 3",
      source_preview_text: "Preview 3",
      source_body_text: "Body 3",
      translation_status: :translating,
      translation_started_at: 30.seconds.ago,
      translation_target_locale: "ru",
      translation_source_locale: "en"
    )

    lock_manager = FakeLockManager.new
    captured = nil

    with_stubbed_constant(NewsIdentifyPendingGamesJob, :perform_async, ->(crawl_run_id) {
      captured = crawl_run_id
      "jid-1"
    }) do
      result = described_class.new(lock_manager: lock_manager).call(@newer_run.id)

      assert_nil captured
      assert_equal({ cleared_lock: true, ready: false, enqueued: nil }, result)
    end
  end

  test "still enqueues for the requested crawl run even if another crawl run is translating" do
    other_run = @section.news_crawl_runs.create!(
      news_source: @section.news_source,
      status: :running,
      started_at: 10.minutes.ago
    )

    @section.news_articles.create!(
      news_source: @section.news_source,
      news_section: @section,
      news_crawl_run: other_run,
      source_article_id: "article-4",
      canonical_url: "https://example.com/news/4",
      title: "Article 4",
      preview_text: "Preview 4",
      body_text: "Body 4",
      body_html: "<p>Body 4</p>",
      fetched_at: Time.current,
      content_hash: "hash-4",
      raw_payload: {},
      source_title: "Article 4",
      source_preview_text: "Preview 4",
      source_body_text: "Body 4",
      translation_status: :translating,
      translation_started_at: 10.seconds.ago,
      translation_target_locale: "ru",
      translation_source_locale: "en"
    )

    lock_manager = FakeLockManager.new
    captured = nil

    with_stubbed_constant(NewsIdentifyPendingGamesJob, :perform_async, ->(crawl_run_id) {
      captured = crawl_run_id
      "jid-1"
    }) do
      result = described_class.new(lock_manager: lock_manager).call(@newer_run.id)

      assert_equal @newer_run.id, captured
      assert_equal({ cleared_lock: true, ready: true, enqueued: true }, result)
    end
  end
end
