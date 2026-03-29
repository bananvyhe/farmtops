require "test_helper"

class NewsCrawlSourcesJobTest < ActiveSupport::TestCase
  test "skips blocked sources when enqueueing section crawls" do
    allowed_source = NewsSource.create!(
      name: "Reuters",
      base_url: "https://www.reuters.com",
      active: true,
      crawl_delay_min_seconds: 0,
      crawl_delay_max_seconds: 0
    )
    allowed_section = allowed_source.news_sections.create!(
      name: "World",
      url: "https://www.reuters.com/world/",
      active: true
    )

    blocked_source = NewsSource.create!(
      name: "The Block",
      base_url: "https://stage.theblock.co",
      active: true,
      crawl_delay_min_seconds: 0,
      crawl_delay_max_seconds: 0
    )
    blocked_source.news_sections.create!(
      name: "Latest",
      url: "https://stage.theblock.co/latest-crypto-news",
      active: true
    )

    queued = []

    NewsCrawlSectionJob.stub(:perform_async, ->(section_id) { queued << section_id; "jid-1" }) do
      NewsCrawlSourcesJob.new.perform
    end

    assert_equal [allowed_section.id], queued
  end
end
