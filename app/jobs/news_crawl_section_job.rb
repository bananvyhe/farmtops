class NewsCrawlSectionJob
  include Sidekiq::Job

  ARTICLES_PER_SECTION = 7

  def perform(news_section_id)
    section = NewsSection.find_by(id: news_section_id)
    return unless section&.active? && section.news_source.active? && !section.news_source.blocked_source?
    return if crawl_throttle.blocked?(section.news_source)

    lock_token = source_lock_manager.acquire(section.news_source)
    unless lock_token
      self.class.perform_in(rand(180..420), news_section_id)
      return
    end

    run = section.news_crawl_runs.create!(
      news_source: section.news_source,
      status: :running,
      started_at: Time.current,
      metadata: {
        section_name: section.name,
        section_url: section.url
      }
    )

    result = News::SectionCrawler.new(
      section:,
      sleeper: crawl_sleeper(section.news_source),
      crawl_run: run,
      max_articles: articles_per_section,
      max_pages: pages_per_section
    ).call
    run.update!(
      status: :succeeded,
      finished_at: Time.current,
      pages_visited: result.pages_visited,
      articles_found: result.articles_found,
      articles_saved: result.articles_saved,
      articles_skipped: result.articles_skipped,
      crawl_errors: result.errors
    )
    begin
      NewsTranslatePendingArticlesJob.perform_async(run.id)
    rescue StandardError => enqueue_error
      Rails.logger.warn("[NewsCrawlSectionJob] failed to enqueue translation queue: #{enqueue_error.class} #{enqueue_error.message}")
    end
  rescue StandardError => e
    run&.update!(
      status: :failed,
      finished_at: Time.current,
      crawl_errors: Array(run&.crawl_errors) + [{ message: e.message, class: e.class.name }]
    )
    raise
  ensure
    source_lock_manager.release(section.news_source, lock_token) if section&.news_source.present? && lock_token.present?
  end

  private

  def articles_per_section
    override = ENV["NEWS_CRAWL_ARTICLES_PER_SECTION"].to_s.strip
    return override.to_i if override.present? && override.to_i > 0

    Rails.env.development? ? 1 : ARTICLES_PER_SECTION
  end

  def pages_per_section
    override = ENV["NEWS_CRAWL_PAGES_PER_SECTION"].to_s.strip
    return override.to_i if override.present? && override.to_i > 0

    1
  end

  def crawl_sleeper(source)
    News::PoliteSleeper.new(
      min_seconds: source.crawl_delay_min_seconds,
      max_seconds: source.crawl_delay_max_seconds
    )
  end

  def source_lock_manager
    @source_lock_manager ||= News::SourceCrawlLockManager.new
  end

  def crawl_throttle
    @crawl_throttle ||= News::CrawlThrottle.new
  end
end
