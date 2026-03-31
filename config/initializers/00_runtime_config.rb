require "cgi"

module RuntimeConfig
  module_function

  def env_or_credential(env_key, *credential_path, default: nil)
    ENV[env_key].presence || credential_value(env_key, *credential_path) || default
  end

  def redis_url
    env_or_credential("REDIS_URL", :redis, :url, default: default_redis_url)
  end

  def default_redis_url
    host = env_or_credential("REDIS_HOST", :redis, :host, default: "127.0.0.1")
    port = env_or_credential("REDIS_PORT", :redis, :port, default: 6379)
    db = env_or_credential("REDIS_DB", :redis, :db, default: 0)
    password = redis_password
    auth = password.present? ? ":#{CGI.escape(password)}@" : ""

    "redis://#{auth}#{host}:#{port}/#{db}"
  end

  def redis_password
    env_or_credential("REDIS_PASSWORD", :redis, :password)
  end

  def credential_value(env_key, *credential_path)
    credentials = Rails.application.credentials

    if credential_path.any?
      nested_value = credentials.dig(*credential_path)
      return nested_value if nested_value.present?
    end

    top_level_key = env_key.to_sym
    alias_keys = [
      top_level_key,
      env_key,
      env_key.gsub(/\ANEWS_TRANSLATOR_TOKEN\z/, "X_Translation_Token")
    ].uniq

    alias_keys.each do |key|
      value = credentials[key]
      return value if value.present?
    end

    nil
  end
end
