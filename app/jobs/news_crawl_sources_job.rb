class NewsCrawlSourcesJob
  include Sidekiq::Job

  def perform
    NewsSource.active.find_each do |source|
      next if source.blocked_source?
      next if crawl_throttle.blocked?(source)

      source.news_sections.active.find_each do |section|
        NewsCrawlSectionJob.perform_async(section.id)
      end
    end
  end

  private

  def crawl_throttle
    @crawl_throttle ||= News::CrawlThrottle.new
  end
end
