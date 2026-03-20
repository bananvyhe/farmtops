module News
  class PoliteSleeper
    def initialize(min_seconds: ENV.fetch("NEWS_CRAWL_MIN_DELAY_SECONDS", "0.8").to_f,
      max_seconds: ENV.fetch("NEWS_CRAWL_MAX_DELAY_SECONDS", "2.2").to_f,
      sleeper: Kernel)
      @min_seconds = [min_seconds.to_f, 0.0].max
      @max_seconds = [max_seconds.to_f, @min_seconds].max
      @sleeper = sleeper
    end

    def pause!
      delay = @min_seconds
      if @max_seconds > @min_seconds
        delay = rand(@min_seconds..@max_seconds)
      end
      @sleeper.sleep(delay) if delay.positive?
    end
  end
end
