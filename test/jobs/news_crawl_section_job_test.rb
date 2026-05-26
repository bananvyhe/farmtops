require "test_helper"

class NewsCrawlSectionJobTest < ActiveSupport::TestCase
  class FakeThrottle
    attr_reader :blocked_calls

    def initialize
      @blocked_calls = []
    end

    def blocked?(source)
      @blocked_calls << source.id
      false
    end
  end

  class FakeLockManager
    attr_reader :acquired_sources, :released_sources

    def initialize(acquire: true)
      @acquire = acquire
      @acquired_sources = []
      @released_sources = []
    end

    def acquire(source)
      @acquired_sources << source.id
      @acquire ? "lock-token" : nil
    end

    def release(source, token)
      @released_sources << [source.id, token]
      true
    end
  end

  test "uses one article per section when NEWS_CRAWL_ARTICLES_PER_SECTION is set" do
    previous_limit = ENV["NEWS_CRAWL_ARTICLES_PER_SECTION"]
    ENV["NEWS_CRAWL_ARTICLES_PER_SECTION"] = "1"

    begin
      assert_equal 1, NewsCrawlSectionJob.new.send(:articles_per_section)
      assert_equal 1, NewsCrawlSectionJob.new.send(:pages_per_section)
    ensure
      ENV["NEWS_CRAWL_ARTICLES_PER_SECTION"] = previous_limit
    end
  end

  test "builds the polite sleeper from the source delay range" do
    source = NewsSource.create!(
      name: "Example",
      base_url: "https://example.com",
      active: true,
      crawl_delay_min_seconds: 1,
      crawl_delay_max_seconds: 3
    )

    sleeper = NewsCrawlSectionJob.new.send(:crawl_sleeper, source)
    assert_instance_of News::PoliteSleeper, sleeper
  end

  test "acquires and releases a source lock while crawling a section" do
    source = NewsSource.create!(
      name: "Locked",
      base_url: "https://locked.example.com",
      active: true,
      crawl_delay_min_seconds: 0,
      crawl_delay_max_seconds: 0
    )
    section = source.news_sections.create!(
      name: "Main",
      url: "https://locked.example.com/news",
      active: true
    )

    throttle = FakeThrottle.new
    lock_manager = FakeLockManager.new
    crawler = Class.new do
      Result = Struct.new(:pages_visited, :articles_found, :articles_saved, :articles_skipped, :errors, keyword_init: true)

      def call
        Result.new(pages_visited: 1, articles_found: 0, articles_saved: 0, articles_skipped: 0, errors: [])
      end
    end.new

    News::CrawlThrottle.stub(:new, -> { throttle }) do
      News::SourceCrawlLockManager.stub(:new, -> { lock_manager }) do
        News::SectionCrawler.stub(:new, ->(**_) { crawler }) do
          NewsTranslatePendingArticlesJob.stub(:perform_async, ->(*) { "jid-1" }) do
            NewsCrawlSectionJob.new.perform(section.id)
          end
        end
      end
    end

    assert_equal [source.id], lock_manager.acquired_sources
    assert_equal [[source.id, "lock-token"]], lock_manager.released_sources
    assert_equal [source.id], throttle.blocked_calls
  end
end
