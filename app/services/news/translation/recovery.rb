require Rails.root.join("app/services/news/translation/lock_manager")

module News
  module Translation
    class Recovery
      DEFAULT_FAILURE_WINDOW = 24.hours

      def initialize(lock_manager: LockManager.new, logger: Rails.logger,
        failure_window: DEFAULT_FAILURE_WINDOW)
        @lock_manager = lock_manager
        @logger = logger
        @failure_window = failure_window
      end

      def call
        cleared_lock = clear_stale_lock
        reset_count = reset_stalled_articles
        enqueued = enqueue_translation_job if pending_articles_exist?

        logger.info(
          "[News::Translation::Recovery] cleared_lock=#{cleared_lock} reset_recent_failed=#{reset_count} enqueued=#{enqueued}"
        )

        {
          cleared_lock: cleared_lock,
          reset_recent_failed: reset_count,
          enqueued: enqueued
        }
      end

      private

      attr_reader :lock_manager, :logger, :failure_window

      def clear_stale_lock
        lock_manager.clear
      rescue StandardError => e
        logger.warn("[News::Translation::Recovery] failed to clear lock: #{e.class} #{e.message}")
        false
      end

      def reset_stalled_articles
        failed_count = NewsArticle.failed.where(created_at: failure_window.ago..).update_all(
          translation_status: "pending",
          translation_error: nil,
          translation_completed_at: nil,
          translated_at: nil,
          translation_model: nil,
          translation_started_at: nil,
          translation_request_id: nil
        )

        translating_count = NewsArticle.translating.where("translation_started_at < ?", failure_window.ago).update_all(
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

      def pending_articles_exist?
        NewsArticle.pending_translation.exists?
      end

      def enqueue_translation_job
        NewsTranslatePendingArticlesJob.perform_async
        true
      rescue StandardError => e
        logger.warn("[News::Translation::Recovery] failed to enqueue translation job: #{e.class} #{e.message}")
        false
      end
    end
  end
end
