class NewsCrawlSectionJob
  include Sidekiq::Job

  ARTICLES_PER_SECTION = 7

  def perform(news_section_id)
    section = NewsSection.find_by(id: news_section_id)
    return unless section&.active? && section.news_source.active? && !section.news_source.blocked_source?

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
end
