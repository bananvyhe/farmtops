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
end
