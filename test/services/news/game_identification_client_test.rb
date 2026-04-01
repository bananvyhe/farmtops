require "test_helper"
require "net/http"

class News::GameIdentificationClientTest < ActiveSupport::TestCase
  def with_redefined_constant(klass, method_name, implementation)
    original = klass.method(method_name)
    klass.define_singleton_method(method_name, &implementation)
    yield
  ensure
    klass.define_singleton_method(method_name) do |*args, **kwargs, &block|
      original.call(*args, **kwargs, &block)
    end
  end

  test "client sends article id body text and task to the identifier" do
    captured_payload = nil
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.define_singleton_method(:body) do
      JSON.generate(
        request_id: "req-1",
        article_id: 987,
        status: "ok",
        identified_game_name: "Elden Ring",
        confidence: 1.0,
        model: "model-path",
        external_game_id: nil,
        slug: "elden-ring",
        error: nil
      )
    end

    fake_http = Object.new
    fake_http.define_singleton_method(:request) do |request|
      captured_payload = JSON.parse(request.body)
      assert_equal "secret", request["X-Game-Id-Token"]
      assert_equal "secret", request["X-Translation-Token"]
      assert_equal "Bearer secret", request["Authorization"]
      response
    end

    client = News::GameIdentification::Client.new(
      base_url: "http://identifier.example",
      token: "secret",
      open_timeout: 1,
      read_timeout: 1
    )

    with_redefined_constant(Net::HTTP, :start, ->(*_, &block) { block.call(fake_http) }) do
      client.identify_game(
        request_id: "req-1",
        article_id: 987,
        body_text: "The article discusses Elden Ring.",
        task: "Identify the game mentioned in the article body and return only the English title or unknown."
      )
    end

    assert_equal 987, captured_payload["article_id"]
    assert_equal "req-1", captured_payload["request_id"]
    assert_includes captured_payload["body_text"], "Elden Ring"
    assert_match "Identify the game", captured_payload["task"]
  end

  test "client accepts unknown responses" do
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.define_singleton_method(:body) do
      JSON.generate(
        request_id: "req-2",
        article_id: 11,
        status: "ok",
        identified_game_name: "unknown",
        confidence: 0.0,
        model: "model-path",
        external_game_id: nil,
        slug: nil,
        error: nil
      )
    end

    fake_http = Object.new
    fake_http.define_singleton_method(:request) { |_request| response }

    client = News::GameIdentification::Client.new(
      base_url: "http://identifier.example",
      token: "secret",
      open_timeout: 1,
      read_timeout: 1
    )

    result = nil
    with_redefined_constant(Net::HTTP, :start, ->(*_, &block) { block.call(fake_http) }) do
      result = client.identify_game(
        request_id: "req-2",
        article_id: 11,
        body_text: "No clear game mention."
      )
    end

    assert_equal "unknown", result.identified_game_name
    assert_equal 0.0, result.confidence
  end
end
