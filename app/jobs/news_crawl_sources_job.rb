class NewsCrawlSourcesJob
  include Sidekiq::Job

  def perform
    NewsSource.active.find_each do |source|
      next if source.blocked_source?

      source.news_sections.active.find_each do |section|
        NewsCrawlSectionJob.perform_async(section.id)
      end
    end
  end
end
