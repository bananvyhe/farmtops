require "net/http"
require "uri"

module News
  class HttpClient
    Error = Class.new(StandardError)

    def initialize(open_timeout: ENV.fetch("NEWS_HTTP_OPEN_TIMEOUT_SECONDS", "10").to_i,
      read_timeout: ENV.fetch("NEWS_HTTP_READ_TIMEOUT_SECONDS", "20").to_i,
      user_agent: ENV.fetch("NEWS_USER_AGENT", "FarmspotNewsCrawler/1.0"))
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @user_agent = user_agent
    end

    def fetch(url)
      uri = URI.parse(url)
      redirects = 0

      loop do
        response = perform_request(uri)

        case response
        when Net::HTTPSuccess
          return response.body.to_s
        when Net::HTTPRedirection
          redirects += 1
          raise Error, "Too many redirects for #{url}" if redirects > 5

          location = response["location"]
          raise Error, "Redirect without location for #{url}" if location.blank?

          uri = URI.parse(location)
          uri = URI.join(url, location) if uri.relative?
        else
          raise Error, "HTTP #{response.code} for #{url}"
        end
      end
    end

    private

    attr_reader :open_timeout, :read_timeout, :user_agent

    def perform_request(uri)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout:, read_timeout:) do |http|
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = user_agent
        request["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        request["Accept-Language"] = "en-US,en;q=0.9"
        request["Cache-Control"] = "no-cache"
        request["Pragma"] = "no-cache"
        request["Upgrade-Insecure-Requests"] = "1"
        request["Sec-Fetch-Dest"] = "document"
        request["Sec-Fetch-Mode"] = "navigate"
        request["Sec-Fetch-Site"] = "none"
        http.request(request)
      end
    end
  end
end
