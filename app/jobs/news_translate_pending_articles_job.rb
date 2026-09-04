class NewsTranslatePendingArticlesJob
  include Sidekiq::Job

  def perform(crawl_run_id = nil)
    token = lock_manager.acquire
    unless token
      # A crawl can enqueue its translation job while another source is being
      # translated. Do not lose that job: retry after the current chain has
      # had time to release the global lock.
      self.class.perform_in(30.seconds, crawl_run_id)
      return
    end

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
