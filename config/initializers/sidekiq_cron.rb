if defined?(Sidekiq) && Sidekiq.server?
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
    "news_crawl_sources" => {
      "class" => "NewsCrawlSourcesJob",
      "cron" => News::Scheduler.cron_expression
    }
  )
end
