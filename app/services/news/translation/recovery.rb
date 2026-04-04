require Rails.root.join("app/services/news/translation/lock_manager")

module News
  module Translation
    class Recovery
      DEFAULT_FAILURE_WINDOW = 24.hours
      DEFAULT_TRANSLATING_WINDOW = 1.hour

      def initialize(lock_manager: LockManager.new, logger: Rails.logger,
        failure_window: DEFAULT_FAILURE_WINDOW,
        translating_window: DEFAULT_TRANSLATING_WINDOW)
        @lock_manager = lock_manager
        @logger = logger
        @failure_window = failure_window
        @translating_window = translating_window
      end

      def call(crawl_run_id = nil)
        cleared_lock = clear_stale_lock
        reset_count = reset_stalled_articles
        crawl_run_id ||= pending_translation_crawl_run_id
        enqueued = enqueue_translation_job(crawl_run_id) if crawl_run_id.present? && pending_articles_exist_for?(crawl_run_id)

        logger.info(
          "[News::Translation::Recovery] cleared_lock=#{cleared_lock} crawl_run_id=#{crawl_run_id.inspect} reset_recent_failed=#{reset_count} enqueued=#{enqueued}"
        )

        {
          cleared_lock: cleared_lock,
          crawl_run_id: crawl_run_id,
          reset_recent_failed: reset_count,
          enqueued: enqueued
        }
      end

      private

      attr_reader :lock_manager, :logger, :failure_window, :translating_window

      def clear_stale_lock
        lock_manager.clear
      rescue StandardError => e
        logger.warn("[News::Translation::Recovery] failed to clear lock: #{e.class} #{e.message}")
        false
      end

      def reset_stalled_articles
        failed_ids = recent_failed_article_ids + transient_failed_article_ids
        failed_count = reset_articles_by_id(failed_ids)

        translating_count = NewsArticle.translating.where("translation_started_at < ?", translating_window.ago).update_all(
          translation_status: "pending",
          translation_error: nil,
          translation_completed_at: nil,
          translated_at: nil,
          translation_model: nil,
          translation_started_at: nil,
          translation_request_id: nil
        )

        failed_count + translating_count
      end

      def pending_translation_crawl_run_id
        NewsArticle.pending_translation
          .where.not(news_crawl_run_id: nil)
          .order(news_crawl_run_id: :desc, created_at: :desc, id: :desc)
          .pick(:news_crawl_run_id)
      end

      def recent_failed_article_ids
        NewsArticle.failed.where(created_at: failure_window.ago..).pluck(:id)
      end

      def transient_failed_article_ids
        NewsArticle.failed
          .where("translation_error ILIKE ?", "%Translator unavailable%")
          .pluck(:id)
      end

      def reset_articles_by_id(article_ids)
        ids = Array(article_ids).map(&:to_i).reject(&:zero?).uniq
        return 0 if ids.blank?

        NewsArticle.where(id: ids).update_all(
          translation_status: "pending",
          translation_error: nil,
          translation_completed_at: nil,
          translated_at: nil,
          translation_model: nil,
          translation_started_at: nil,
          translation_request_id: nil
        )
      end

      def pending_articles_exist_for?(crawl_run_id)
        NewsArticle.pending_translation_for_crawl_run(crawl_run_id).exists?
      end

      def enqueue_translation_job(crawl_run_id)
        NewsTranslatePendingArticlesJob.perform_async(crawl_run_id)
        true
      rescue StandardError => e
        logger.warn("[News::Translation::Recovery] failed to enqueue translation job: #{e.class} #{e.message}")
        false
      end
    end
  end
end
