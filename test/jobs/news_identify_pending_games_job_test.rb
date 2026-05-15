require "test_helper"

class NewsIdentifyPendingGamesJobTest < ActiveSupport::TestCase
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

    @crawl_run = @section.news_crawl_runs.create!(
      news_source: source,
      status: :succeeded,
      started_at: 1.hour.ago,
      finished_at: 30.minutes.ago
    )

    @first_article = @section.news_articles.create!(
      news_source: source,
      news_section: @section,
      news_crawl_run: @crawl_run,
      source_article_id: "article-1",
      canonical_url: "https://example.com/news/1",
      title: "Article 1",
      preview_text: "Preview 1",
      body_text: "Body 1",
      body_html: "<p>Body 1</p>",
      fetched_at: Time.current,
      content_hash: "hash-1",
      raw_payload: {},
      full_article_available: true,
      source_title: "Article 1",
      source_preview_text: "Preview 1",
      source_body_text: "Body 1",
      translation_status: :translated,
      translation_target_locale: "ru",
      translation_source_locale: "en"
    )
  end

  test "enqueues the first translated article missing a game and keeps the chain lock" do
    lock_manager = FakeLockManager.new
    captured = nil

    with_stubbed_constant(News::GameIdentification::LockManager, :new, -> { lock_manager }) do
      with_stubbed_constant(NewsIdentifyGameJob, :perform_async, ->(article_id, token, crawl_run_id = nil) {
        captured = [article_id, token, crawl_run_id]
        "jid-1"
      }) do
        NewsIdentifyPendingGamesJob.new.perform
      end
    end

    assert_equal [@first_article.id, "lock-token", nil], captured
    refute lock_manager.released
  end

  test "scopes to the requested crawl run and ignores older pending games" do
    old_run = @section.news_crawl_runs.create!(
      news_source: @section.news_source,
      status: :succeeded,
      started_at: 2.hours.ago,
      finished_at: 90.minutes.ago
    )

    old_article = @section.news_articles.create!(
      news_source: @section.news_source,
      news_section: @section,
      news_crawl_run: old_run,
      source_article_id: "article-old",
      canonical_url: "https://example.com/news/old",
      title: "Old Article",
      preview_text: "Old Preview",
      body_text: "Old Body",
      body_html: "<p>Old Body</p>",
      fetched_at: Time.current,
      content_hash: "hash-old",
      raw_payload: {},
      full_article_available: true,
      source_title: "Old Article",
      source_preview_text: "Old Preview",
      source_body_text: "Old Body",
      translation_status: :translated,
      translation_target_locale: "ru",
      translation_source_locale: "en"
    )

    lock_manager = FakeLockManager.new
    captured = nil

    with_stubbed_constant(News::GameIdentification::LockManager, :new, -> { lock_manager }) do
      with_stubbed_constant(NewsIdentifyGameJob, :perform_async, ->(article_id, token, crawl_run_id) {
        captured = [article_id, token, crawl_run_id]
        "jid-1"
      }) do
        NewsIdentifyPendingGamesJob.new.perform(@crawl_run.id)
      end
    end

    assert_equal [@first_article.id, "lock-token", @crawl_run.id], captured
    refute_equal old_article.id, captured.first
    refute lock_manager.released
  end

  test "releases the lock when there is nothing to process" do
    @section.news_articles.delete_all
    lock_manager = FakeLockManager.new

    with_stubbed_constant(News::GameIdentification::LockManager, :new, -> { lock_manager }) do
      with_stubbed_constant(NewsIdentifyGameJob, :perform_async, ->(*_) { flunk("should not enqueue") }) do
        NewsIdentifyPendingGamesJob.new.perform
      end
    end

    assert lock_manager.released
  end

  test "ignores articles without a full article" do
    @section.news_articles.delete_all
    feed_only_article = @section.news_articles.create!(
      news_source: @section.news_source,
      news_section: @section,
      news_crawl_run: @crawl_run,
      source_article_id: "article-feed-only",
      canonical_url: "https://example.com/news/feed-only",
      title: "Feed-only Article",
      preview_text: "Preview only",
      body_text: "Preview only",
      body_html: "<p>Preview only</p>",
      fetched_at: Time.current,
      content_hash: "hash-feed-only",
      raw_payload: {},
      full_article_available: false,
      source_title: "Feed-only Article",
      source_preview_text: "Preview only",
      source_body_text: nil,
      translation_status: :translated,
      translation_target_locale: "ru",
      translation_source_locale: "en"
    )

    lock_manager = FakeLockManager.new

    with_stubbed_constant(News::GameIdentification::LockManager, :new, -> { lock_manager }) do
      with_stubbed_constant(NewsIdentifyGameJob, :perform_async, ->(*_) { flunk("should not enqueue") }) do
        NewsIdentifyPendingGamesJob.new.perform
      end
    end

    assert lock_manager.released
    assert_not NewsArticle.pending_game_identification.exists?
  end
end
