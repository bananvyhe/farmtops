require "test_helper"

class NewsCrawlSectionJobTest < ActiveSupport::TestCase
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
end
