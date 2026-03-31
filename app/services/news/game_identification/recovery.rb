require Rails.root.join("app/services/news/game_identification/lock_manager")

module News
  module GameIdentification
    class Recovery
      def initialize(lock_manager: LockManager.new, logger: Rails.logger)
        @lock_manager = lock_manager
        @logger = logger
      end

      def call
        cleared_lock = clear_stale_lock
        enqueued = enqueue_game_identification_job if ready_for_identification?

        logger.info(
          "[News::GameIdentification::Recovery] cleared_lock=#{cleared_lock} enqueued=#{enqueued}"
        )

        {
          cleared_lock: cleared_lock,
          enqueued: enqueued
        }
      end

      private

      attr_reader :lock_manager, :logger

      def clear_stale_lock
        lock_manager.clear
      rescue StandardError => e
        logger.warn("[News::GameIdentification::Recovery] failed to clear lock: #{e.class} #{e.message}")
        false
      end

      def ready_for_identification?
        !NewsArticle.pending_translation.exists? && pending_game_articles_exist?
      end

      def pending_game_articles_exist?
        NewsArticle.pending_game_identification.exists?
      end

      def enqueue_game_identification_job
        NewsIdentifyPendingGamesJob.perform_async
        true
      rescue StandardError => e
        logger.warn("[News::GameIdentification::Recovery] failed to enqueue game identification job: #{e.class} #{e.message}")
        false
      end
    end
  end
end
