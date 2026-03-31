class NewsIdentifyPendingGamesJob
  include Sidekiq::Job

  def perform
    token = lock_manager.acquire
    return unless token

    article = next_pending_article
    if article.blank?
      lock_manager.release(token)
      return
    end

    NewsIdentifyGameJob.perform_async(article.id, token)
  rescue StandardError => e
    lock_manager.release(token) if token.present?
    raise e
  end

  private

  def next_pending_article
    NewsArticle.pending_game_identification.order(:translated_at, :id).first
  end

  def lock_manager
    @lock_manager ||= News::GameIdentification::LockManager.new
  end
end
