require "redis"
require "securerandom"

module News
  module Translation
    class LockManager
      LOCK_KEY = "news:translation:pending_articles_lock"
      LOCK_TTL_SECONDS = 12.hours.to_i

      def initialize(redis: Redis.new(url: RuntimeConfig.redis_url), key: LOCK_KEY, ttl: LOCK_TTL_SECONDS)
        @redis = redis
        @key = key
        @ttl = ttl
      end

      def acquire
        token = SecureRandom.uuid
        return unless redis.set(key, token, nx: true, ex: ttl)

        token
      end

      def refresh(token)
        return false unless current_token == token

        redis.expire(key, ttl)
      end

      def release(token)
        return false unless current_token == token

        redis.del(key).positive?
      end

      def clear
        redis.del(key).positive?
      end

      def current_token
        redis.get(key)
      end

      private

      attr_reader :redis, :key, :ttl
    end
  end
end
