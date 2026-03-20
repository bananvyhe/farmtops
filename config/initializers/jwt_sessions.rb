redis_url = RuntimeConfig.redis_url

JWTSessions.algorithm = "HS256"
JWTSessions.signing_key =
  Rails.application.credentials.dig(:jwt, :signing_key) ||
  ENV["JWT_SIGNING_KEY"] ||
  (Rails.env.production? ? raise("JWT signing key is not configured") : "change-me-in-production")

JWTSessions.access_cookie = "farmspot_access"
JWTSessions.refresh_cookie = "farmspot_refresh"
JWTSessions.csrf_header = "X-CSRF-Token"
JWTSessions.access_exp_time = 30.minutes.to_i
JWTSessions.refresh_exp_time = 30.days.to_i
JWTSessions.token_store =
  if Rails.env.production? || ENV["REDIS_URL"].present?
    [:redis, { redis_url: redis_url }]
  else
    :memory
  end
