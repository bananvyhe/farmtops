require "cgi"

module RuntimeConfig
  module_function

  def env_or_credential(env_key, *credential_path, default: nil)
    ENV[env_key].presence || Rails.application.credentials.dig(*credential_path) || default
  end

  def redis_url
    env_or_credential("REDIS_URL", :redis, :url, default: default_redis_url)
  end

  def default_redis_url
    host = env_or_credential("REDIS_HOST", :redis, :host, default: "127.0.0.1")
    port = env_or_credential("REDIS_PORT", :redis, :port, default: 6379)
    db = env_or_credential("REDIS_DB", :redis, :db, default: 0)
    password = env_or_credential("REDIS_PASSWORD", :redis, :password)
    auth = password.present? ? ":#{CGI.escape(password)}@" : ""

    "redis://#{auth}#{host}:#{port}/#{db}"
  end
end
