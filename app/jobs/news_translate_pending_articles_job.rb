class NewsTranslatePendingArticlesJob
  include Sidekiq::Job

  def perform(crawl_run_id = nil)
    token = lock_manager.acquire
    return unless token

    article = next_pending_article(crawl_run_id)
    if article.blank?
      lock_manager.release(token)
      return
    end

    NewsTranslateArticleJob.perform_async(article.id, token, crawl_run_id)
  rescue StandardError => e
    lock_manager.release(token) if token.present?
    raise e
  end

  private

  def next_pending_article(crawl_run_id = nil)
    scope = if crawl_run_id.present?
      NewsArticle.pending_translation_for_crawl_run(crawl_run_id)
    else
      latest_crawl_run_id = NewsArticle.latest_pending_translation_crawl_run_id
      return nil if latest_crawl_run_id.blank?

      NewsArticle.pending_translation_for_crawl_run(latest_crawl_run_id)
    end

    scope.order(:created_at, :id).first
  end

  def lock_manager
    @lock_manager ||= News::Translation::LockManager.new
  end
end
