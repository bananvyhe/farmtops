require "redis"

module News
  class CrawlThrottle
    DEFAULT_BLOCK_TTL_SECONDS = ENV.fetch("NEWS_CRAWL_BLOCK_TTL_SECONDS", 12.hours.to_i.to_s).to_i
    DEFAULT_FULL_ARTICLE_DISABLED_TTL_SECONDS = ENV.fetch("NEWS_FULL_ARTICLE_DISABLED_TTL_SECONDS", 7.days.to_i.to_s).to_i
    KEY_PREFIX = "news:crawl:blocked_source"
    FULL_ARTICLE_PREFIX = "news:crawl:full_article_disabled"

    def initialize(redis: Redis.new(url: RuntimeConfig.redis_url), ttl: DEFAULT_BLOCK_TTL_SECONDS)
      @redis = redis
      @ttl = ttl
    end

    def block!(source, ttl: @ttl)
      redis.set(block_key(source), Time.current.to_i.to_s, ex: [ttl.to_i, 1].max)
    end

    def blocked?(source)
      redis.exists?(block_key(source))
    end

    def clear!(source)
      redis.del(block_key(source)).positive?
    end

    def disable_full_article_fetch!(source, ttl: DEFAULT_FULL_ARTICLE_DISABLED_TTL_SECONDS)
      redis.set(full_article_key(source), Time.current.to_i.to_s, ex: [ttl.to_i, 1].max)
    end

    def full_article_fetch_disabled?(source)
      redis.exists?(full_article_key(source))
    end

    def clear_full_article_fetch!(source)
      redis.del(full_article_key(source)).positive?
    end

    private

    attr_reader :redis, :ttl

    def block_key(source)
      "#{KEY_PREFIX}:#{source.id}"
    end

    def full_article_key(source)
      "#{FULL_ARTICLE_PREFIX}:#{source.id}"
    end
  end
end
