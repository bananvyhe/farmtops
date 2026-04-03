require "test_helper"

class NewsIdentifyGameJobTest < ActiveSupport::TestCase
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

    @article = @section.news_articles.create!(
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
      source_title: "Article 1",
      source_preview_text: "Preview 1",
      source_body_text: "Body 1",
      translation_status: :translated,
      translation_target_locale: "ru",
      translation_source_locale: "en"
    )

    NewsArticleGame.create!(
      news_article: @article,
      request_id: "request-1",
      identified_game_name: "Example Game",
      slug: "example-game",
      confidence: 1.0,
      model: "fake",
      raw_response: {}
    )
  end

  test "releases the lock instead of jumping to a game from another crawl run" do
    other_run = @section.news_crawl_runs.create!(
      news_source: @section.news_source,
      status: :succeeded,
      started_at: 2.hours.ago,
      finished_at: 90.minutes.ago
    )

    @section.news_articles.create!(
      news_source: @section.news_source,
      news_section: @section,
      news_crawl_run: other_run,
      source_article_id: "article-old",
      canonical_url: "https://example.com/news/old",
      title: "Old Article",
      preview_text: "Old Preview",
      body_text: "Old Body",
      body_html: "<p>Old Body</p>",
      fetched_at: Time.current,
      content_hash: "hash-old",
      raw_payload: {},
      source_title: "Old Article",
      source_preview_text: "Old Preview",
      source_body_text: "Old Body",
      translation_status: :translated,
      translation_target_locale: "ru",
      translation_source_locale: "en"
    )

    lock_manager = FakeLockManager.new

    with_stubbed_constant(News::GameIdentification::LockManager, :new, -> { lock_manager }) do
      with_stubbed_constant(NewsIdentifyGameJob, :perform_async, ->(*_) { flunk("should not enqueue another article") }) do
        NewsIdentifyGameJob.new.perform(@article.id, "lock-token", @crawl_run.id)
      end
    end

    assert lock_manager.released
  end

  test "enqueues a watchdog after game identification" do
    lock_manager = FakeLockManager.new
    watchdog = nil

    with_stubbed_constant(News::GameIdentification::LockManager, :new, -> { lock_manager }) do
      with_stubbed_constant(News::ArticleGameIdentifier, :new, ->(article:) do
        Object.new.tap do |service|
          service.define_singleton_method(:call) do |request_id:|
            NewsArticleGame.create!(
              news_article: article,
              request_id: request_id,
              identified_game_name: "Example Game",
              slug: "example-game",
              confidence: 1.0,
              model: "fake",
              raw_response: {}
            )
          end
        end
      end) do
        with_stubbed_constant(NewsIdentifyPendingGamesJob, :perform_in, ->(delay, crawl_run_id = nil) {
          watchdog = [delay, crawl_run_id]
          "jid-1"
        }) do
          NewsIdentifyGameJob.new.perform(@article.id, "lock-token", @crawl_run.id)
        end
      end
    end

    assert_equal [1.minute, nil], watchdog
    assert lock_manager.released
  end

  test "recovery is triggered when the crawl run is drained" do
    lock_manager = FakeLockManager.new
    recovery = Object.new
    recovery_called = false
    recovery.define_singleton_method(:call) do |*args|
      assert_empty args
      recovery_called = true
      { cleared_lock: true, enqueued: true }
    end

    with_stubbed_constant(News::GameIdentification::LockManager, :new, -> { lock_manager }) do
      with_stubbed_constant(News::GameIdentification::Recovery, :new, -> { recovery }) do
        NewsIdentifyGameJob.new.perform(@article.id, "lock-token", @crawl_run.id)
      end
    end

    assert recovery_called
    assert lock_manager.released
  end
end
