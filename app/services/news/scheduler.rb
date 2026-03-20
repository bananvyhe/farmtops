module News
  class Scheduler
    DEFAULT_INTERVAL_HOURS = 4

    def self.interval_hours
      value = ENV.fetch("NEWS_CRAWL_INTERVAL_HOURS", DEFAULT_INTERVAL_HOURS.to_s).to_i
      value = DEFAULT_INTERVAL_HOURS if value <= 0
      value
    end

    def self.cron_expression
      "0 */#{interval_hours} * * *"
    end
  end
end
