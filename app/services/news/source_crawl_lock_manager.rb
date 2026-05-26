require "redis"
require "securerandom"

module News
  class SourceCrawlLockManager
    LOCK_TTL_SECONDS = 30.minutes.to_i
    KEY_PREFIX = "news:crawl:source_lock"

    def initialize(redis: Redis.new(url: RuntimeConfig.redis_url), ttl: LOCK_TTL_SECONDS)
      @redis = redis
      @ttl = ttl
    end

    def acquire(source)
      token = SecureRandom.uuid
      return unless redis.set(lock_key(source), token, nx: true, ex: ttl)

      token
    end

    def release(source, token)
      return false unless current_token(source) == token

      redis.del(lock_key(source)).positive?
    end

    def current_token(source)
      redis.get(lock_key(source))
    end

    private

    attr_reader :redis, :ttl

    def lock_key(source)
      "#{KEY_PREFIX}:#{source.id}"
    end
  end
end
