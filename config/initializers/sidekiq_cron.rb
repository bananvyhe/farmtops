require Rails.root.join("app/services/news/scheduler")
require Rails.root.join("app/services/news/translation/recovery")
require Rails.root.join("app/services/news/game_identification/recovery")

Rails.application.config.after_initialize do
  next unless defined?(Sidekiq) && Sidekiq.server?
  next if Rails.env.development? && ENV["ENABLE_SIDEKIQ_DEV_SCHEDULES"] != "1"

  News::Translation::Recovery.new.call
  News::GameIdentification::Recovery.new.call
  remove_cron_job("news_translate_pending_articles")
  remove_cron_job("news_identify_pending_games")

  interval_minutes =
    ENV.fetch("BILLING_INTERVAL_MINUTES", Rails.env.development? ? "20" : "60").to_i
  interval_minutes = 60 if interval_minutes <= 0

  cron_expression = "*/#{interval_minutes} * * * *"

  Sidekiq::Cron::Job.load_from_hash(
    "hourly_balance_sweep" => {
      "class" => "HourlyBalanceSweepJob",
      "cron" => cron_expression
    }
  )

  Sidekiq::Cron::Job.load_from_hash(
    "news_translation_recovery" => {
      "class" => "NewsTranslationRecoveryJob",
      "cron" => "*/15 * * * *"
    }
  )

  Sidekiq::Cron::Job.load_from_hash(
    "news_crawl_sources" => {
      "class" => "NewsCrawlSourcesJob",
      "cron" => News::Scheduler.cron_expression
    }
  )
end

def remove_cron_job(name)
  job = Sidekiq::Cron::Job.find(name)
  job&.destroy
end
