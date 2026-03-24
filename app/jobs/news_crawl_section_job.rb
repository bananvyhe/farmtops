class NewsCrawlSectionJob
  include Sidekiq::Job

  ARTICLES_PER_SECTION = 7

  def perform(news_section_id)
    section = NewsSection.find_by(id: news_section_id)
    return unless section&.active? && section.news_source.active?

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
      max_articles: ARTICLES_PER_SECTION,
      translator: news_translator
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
  rescue StandardError => e
    run&.update!(
      status: :failed,
      finished_at: Time.current,
      crawl_errors: Array(run&.crawl_errors) + [{ message: e.message, class: e.class.name }]
    )
    raise
  end

  private

  def news_translator
    News::Translation::Client.new
  end
end
