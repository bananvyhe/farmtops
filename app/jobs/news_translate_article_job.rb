require "securerandom"

class NewsTranslateArticleJob
  include Sidekiq::Job

  def perform(article_id, lock_token)
    begin
      article = NewsArticle.find_by(id: article_id)
      return advance_chain(lock_token, next_pending_article_id) if article.blank?

      next_article_id = nil
      should_advance = false
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

          News::ArticleTranslator.new(article: article).call(request_id: request_id)
          next_article_id = next_pending_article_id
          should_advance = true
        end
      end
      next_article_id ||= next_pending_article_id if should_advance
      advance_chain(lock_token, next_article_id) if should_advance
    rescue StandardError => e
      Rails.logger.warn("[NewsTranslateArticleJob] failed for #{article_id}: #{e.class} #{e.message}")
      raise
    ensure
      lock_manager.refresh(lock_token) if lock_held_by_chain?(lock_token)
    end
  end

  private

  def advance_chain(lock_token, next_article_id = nil)
    return unless lock_held_by_chain?(lock_token)

    if next_article_id.present?
      NewsTranslateArticleJob.perform_async(next_article_id, lock_token)
    else
      lock_manager.release(lock_token)
    end
  end

  def next_pending_article_id
    NewsArticle.pending_translation.order(:created_at, :id).pick(:id)
  end

  def lock_held_by_chain?(lock_token)
    lock_manager.current_token == lock_token
  end

  def lock_manager
    @lock_manager ||= News::Translation::LockManager.new
  end
end
