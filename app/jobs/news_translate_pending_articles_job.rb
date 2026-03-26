require "securerandom"

class NewsTranslatePendingArticlesJob
  include Sidekiq::Job

  LOCK_KEY = "news:translation:pending_articles_lock"
  LOCK_TTL_SECONDS = 12.hours.to_i

  def perform
    with_lock do
      loop do
        article = next_pending_article
        break if article.blank?

        News::ArticleTranslator.new(article: article).call
        redis.expire(LOCK_KEY, LOCK_TTL_SECONDS)
      end
    end
  end

  private

  def next_pending_article
    NewsArticle.pending_translation.order(:created_at, :id).first
  end

  def with_lock
    token = SecureRandom.uuid
    acquired = redis.set(LOCK_KEY, token, nx: true, ex: LOCK_TTL_SECONDS)
    return unless acquired

    yield
  ensure
    release_lock(token) if acquired
  end

  def release_lock(token)
    current_token = redis.get(LOCK_KEY)
    return unless current_token == token

    redis.del(LOCK_KEY)
  end

  def redis
    @redis ||= Redis.new(url: RuntimeConfig.redis_url)
  end
end
