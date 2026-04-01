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
        crawl_run_id = ready_crawl_run_id(crawl_run_id)
        ready = crawl_run_id.present?
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

      def ready_crawl_run_id(crawl_run_id = nil)
        return nil unless translation_pipeline_idle_globally?

        if crawl_run_id.present? && NewsArticle.pending_game_identification_for_crawl_run(crawl_run_id).exists?
          return crawl_run_id
        end

        pending_game_crawl_run_id
      end

      def pending_game_crawl_run_id
        NewsArticle.pending_game_identification
          .where.not(news_crawl_run_id: nil)
          .order(news_crawl_run_id: :desc, translated_at: :desc, id: :desc)
          .pick(:news_crawl_run_id)
      end

      def translation_pipeline_idle_globally?
        NewsArticle.pending_translation.blank? && NewsArticle.translating.blank?
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
