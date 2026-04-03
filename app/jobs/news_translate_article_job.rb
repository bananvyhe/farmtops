require "securerandom"

class NewsTranslateArticleJob
  include Sidekiq::Job

  def perform(article_id, lock_token, crawl_run_id = nil)
    begin
      article = NewsArticle.find_by(id: article_id)
      crawl_run_id ||= article&.news_crawl_run_id
      return advance_chain(lock_token, next_pending_article_id(crawl_run_id), crawl_run_id) if article.blank?

      next_article_id = nil
      should_advance = false
      request_id = nil
      article.with_lock do
        if article.translated?
          should_advance = true
        elsif !lock_held_by_chain?(lock_token)
          should_advance = false
        else
          request_id = SecureRandom.uuid
          article.update!(
            translation_status: :translating,
            translation_started_at: Time.current,
            translation_error: nil,
            translation_request_id: request_id,
            translation_attempts: article.translation_attempts.to_i + 1
          )
          should_advance = true
        end
      end

      if should_advance && request_id.present? && article.translating?
        News::ArticleTranslator.new(article: article).call(request_id: request_id)
        enqueue_translation_watchdog
        next_article_id = next_pending_article_id(crawl_run_id)
      end
      next_article_id ||= next_pending_article_id(crawl_run_id) if should_advance
      advance_chain(lock_token, next_article_id, crawl_run_id) if should_advance
    rescue StandardError => e
      Rails.logger.warn("[NewsTranslateArticleJob] failed for #{article_id}: #{e.class} #{e.message}")
      raise
    ensure
      lock_manager.refresh(lock_token) if lock_held_by_chain?(lock_token)
    end
  end

  private

  def advance_chain(lock_token, next_article_id = nil, crawl_run_id = nil)
    return unless lock_held_by_chain?(lock_token)

    if next_article_id.present?
      NewsTranslateArticleJob.perform_async(next_article_id, lock_token, crawl_run_id)
    else
      lock_manager.release(lock_token)
      begin
        News::GameIdentification::Recovery.new.call
      rescue StandardError => e
        Rails.logger.warn("[NewsTranslateArticleJob] failed to enqueue game identification recovery: #{e.class} #{e.message}")
      end
    end
  end

  def enqueue_translation_watchdog
    NewsTranslatePendingArticlesJob.perform_in(1.minute)
  rescue StandardError => e
    Rails.logger.warn("[NewsTranslateArticleJob] failed to enqueue translation watchdog: #{e.class} #{e.message}")
  end

  def next_pending_article_id(crawl_run_id = nil)
    scope = if crawl_run_id.present?
      NewsArticle.pending_translation_for_crawl_run(crawl_run_id)
    else
      latest_crawl_run_id = NewsArticle.latest_pending_translation_crawl_run_id
      return nil if latest_crawl_run_id.blank?

      NewsArticle.pending_translation_for_crawl_run(latest_crawl_run_id)
    end

    scope.order(:created_at, :id).pick(:id)
  end

  def lock_held_by_chain?(lock_token)
    lock_manager.current_token == lock_token
  end

  def lock_manager
    @lock_manager ||= News::Translation::LockManager.new
  end
end
