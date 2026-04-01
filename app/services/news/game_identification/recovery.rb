require Rails.root.join("app/services/news/game_identification/lock_manager")

module News
  module GameIdentification
    class Recovery
      def initialize(lock_manager: LockManager.new, logger: Rails.logger)
        @lock_manager = lock_manager
        @logger = logger
      end

      def call(crawl_run_id = nil)
        cleared_lock = clear_stale_lock
        crawl_run_id ||= pending_game_crawl_run_id
        ready = crawl_run_id.present? && translation_pipeline_idle_for?(crawl_run_id)
        enqueued = enqueue_game_identification_job(crawl_run_id) if ready

        logger.info(
          "[News::GameIdentification::Recovery] cleared_lock=#{cleared_lock} crawl_run_id=#{crawl_run_id.inspect} ready=#{ready} enqueued=#{enqueued}"
        )

        {
          cleared_lock: cleared_lock,
          ready: ready,
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

      def pending_game_crawl_run_id
        NewsArticle.pending_game_identification
          .where.not(news_crawl_run_id: nil)
          .order(news_crawl_run_id: :desc, translated_at: :desc, id: :desc)
          .pluck(:news_crawl_run_id)
          .uniq
          .find { |run_id| translation_pipeline_idle_for?(run_id) }
      end

      def translation_pipeline_idle_for?(crawl_run_id)
        NewsArticle.pending_translation_for_crawl_run(crawl_run_id).blank? &&
          NewsArticle.translating_for_crawl_run(crawl_run_id).blank?
      end

      def enqueue_game_identification_job(crawl_run_id)
        NewsIdentifyPendingGamesJob.perform_async(crawl_run_id)
        true
      rescue StandardError => e
        logger.warn("[News::GameIdentification::Recovery] failed to enqueue game identification job: #{e.class} #{e.message}")
        false
      end
    end
  end
end
