class NewsIdentifyPendingGamesJob
  include Sidekiq::Job

  def perform(crawl_run_id = nil)
    token = lock_manager.acquire
    return unless token

    article = next_pending_article(crawl_run_id)
    if article.blank?
      lock_manager.release(token)
      return
    end

    NewsIdentifyGameJob.perform_async(article.id, token, crawl_run_id)
  rescue StandardError => e
    lock_manager.release(token) if token.present?
    raise e
  end

  private

  def next_pending_article(crawl_run_id = nil)
    scope = if crawl_run_id.present?
      NewsArticle.pending_game_identification_for_crawl_run(crawl_run_id)
    else
      NewsArticle.pending_game_identification
    end

    scope.order(:translated_at, :id).first
  end

  def lock_manager
    @lock_manager ||= News::GameIdentification::LockManager.new
  end
end
