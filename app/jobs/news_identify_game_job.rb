require "securerandom"

class NewsIdentifyGameJob
  include Sidekiq::Job

  def perform(article_id, lock_token, crawl_run_id = nil)
    begin
      article = NewsArticle.find_by(id: article_id)
      return advance_chain(lock_token, next_pending_article_id(crawl_run_id), crawl_run_id) if article.blank?

      next_article_id = nil
      should_advance = false
      article.with_lock do
        if article.news_article_game.present?
          should_advance = true
        elsif !lock_held_by_chain?(lock_token)
          should_advance = false
        else
          request_id = SecureRandom.uuid
          News::ArticleGameIdentifier.new(article: article).call(request_id: request_id)
          next_article_id = next_pending_article_id(crawl_run_id)
          should_advance = true
        end
      end
      next_article_id ||= next_pending_article_id(crawl_run_id) if should_advance
      advance_chain(lock_token, next_article_id, crawl_run_id) if should_advance
    rescue StandardError => e
      Rails.logger.warn("[NewsIdentifyGameJob] failed for #{article_id}: #{e.class} #{e.message}")
      raise
    ensure
      lock_manager.refresh(lock_token) if lock_held_by_chain?(lock_token)
    end
  end

  private

  def advance_chain(lock_token, next_article_id = nil, crawl_run_id = nil)
    return unless lock_held_by_chain?(lock_token)

    if next_article_id.present?
      NewsIdentifyGameJob.perform_async(next_article_id, lock_token, crawl_run_id)
    else
      lock_manager.release(lock_token)
      begin
        News::GameIdentification::Recovery.new.call
      rescue StandardError => e
        Rails.logger.warn("[NewsIdentifyGameJob] failed to enqueue game identification recovery: #{e.class} #{e.message}")
      end
    end
  end

  def next_pending_article_id(crawl_run_id = nil)
    scope = if crawl_run_id.present?
      NewsArticle.pending_game_identification_for_crawl_run(crawl_run_id)
    else
      NewsArticle.pending_game_identification
    end

    scope.order(:translated_at, :id).pick(:id)
  end

  def lock_held_by_chain?(lock_token)
    lock_manager.current_token == lock_token
  end

  def lock_manager
    @lock_manager ||= News::GameIdentification::LockManager.new
  end
end
