require "redis"

module News
  module Translation
    class Recovery
      DEFAULT_FAILURE_WINDOW = 24.hours

      def initialize(redis: Redis.new(url: RuntimeConfig.redis_url), logger: Rails.logger,
        failure_window: DEFAULT_FAILURE_WINDOW)
        @redis = redis
        @logger = logger
        @failure_window = failure_window
      end

      def call
        cleared_lock = clear_stale_lock
        reset_count = reset_recent_failed_articles
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

      attr_reader :redis, :logger, :failure_window

      def clear_stale_lock
        redis.del(NewsTranslatePendingArticlesJob::LOCK_KEY).positive?
      rescue StandardError => e
        logger.warn("[News::Translation::Recovery] failed to clear lock: #{e.class} #{e.message}")
        false
      end

      def reset_recent_failed_articles
        scope = NewsArticle.failed.where(created_at: failure_window.ago..)
        scope.update_all(
          translation_status: "pending",
          translation_error: nil,
          translation_completed_at: nil,
          translated_at: nil,
          translation_model: nil
        )
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
