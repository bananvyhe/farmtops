require "test_helper"

class News::TranslationClientTest < ActiveSupport::TestCase
  def with_credentials(credentials)
    Rails.application.singleton_class.define_method(:credentials) { credentials }
    yield
  ensure
    Rails.application.singleton_class.send(:remove_method, :credentials)
  end

  def with_stubbed_constant(object, method_name, implementation)
    original = object.method(method_name)
    object.define_singleton_method(method_name, &implementation)
    yield
  ensure
    object.define_singleton_method(method_name) do |*args, **kwargs, &block|
      original.call(*args, **kwargs, &block)
    end
  end

  test "null client passes through the input" do
    result = News::Translation::NullClient.new.translate_article(
      source_lang: "en",
      target_lang: "ru",
      title: "Hello",
      preview_text: "Preview",
      body_text: "Body"
    )

    assert_equal "Hello", result.translated_title
    assert_equal "Preview", result.translated_preview_text
    assert_equal "Body", result.translated_body_text
    assert_equal "noop", result.model
    assert_equal "ok", result.status
  end

  test "client sends title preview and body aliases to the translator" do
    captured_payload = nil
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.define_singleton_method(:body) do
      JSON.generate(
        request_id: "req-1",
        translated_title: "Привет",
        translated_preview_text: "Превью",
        translated_body_text: "Тело",
        model: "test-translator",
        status: "ok"
      )
    end

    fake_http = Object.new
    fake_http.define_singleton_method(:request) do |request|
      captured_payload = JSON.parse(request.body)
      response
    end

    client = News::Translation::Client.new(
      base_url: "http://translator.example",
      token: "secret",
      open_timeout: 1,
      read_timeout: 1
    )

    Net::HTTP.stub(:start, lambda { |*_, &block| block.call(fake_http) }) do
      client.translate_article(
        source_lang: "en",
        target_lang: "ru",
        title: "Hello",
        preview_text: "Preview",
        body_text: "Body"
      )
    end

    assert_equal "Hello", captured_payload["title"]
    assert_equal "Preview", captured_payload["preview_text"]
    assert_equal "Body", captured_payload["body_text"]
  end

  test "client raises a clear error when production token is missing" do
    credentials = Class.new do
      def dig(*_path)
        nil
      end

      def [](key)
        nil
      end
    end.new

    rails_env = ActiveSupport::StringInquirer.new("production")

    with_credentials(credentials) do
      Rails.stub(:env, rails_env) do
        error = assert_raises(News::Translation::Error) { News::Translation::Client.new }
        assert_match "Translation token is not configured", error.message
      end
    end
  end

  test "client falls back to the first healthy translator when base url is not configured" do
    rails_env = ActiveSupport::StringInquirer.new("production")
    events = []
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.define_singleton_method(:body) do
      JSON.generate(
        request_id: "req-1",
        translated_title: "Привет",
        translated_preview_text: "Превью",
        translated_body_text: "Тело",
        model: "test-translator",
        status: "ok"
      )
    end

    fake_http = Object.new
    fake_http.define_singleton_method(:get) do |path|
      events << [:health, path]
      Net::HTTPOK.new("1.1", "200", "OK")
    end
    fake_http.define_singleton_method(:request) do |request|
      events << [:translate, request.uri.host, request.uri.port]
      response
    end

    with_credentials(Class.new do
      def dig(*path)
        return "secret" if path == [:translation, :token]

        nil
      end

      def [](key)
        key == :translation ? { token: "secret" } : nil
      end
    end.new) do
      Rails.stub(:env, rails_env) do
        with_stubbed_constant(Net::HTTP, :start, ->(host, port, **kwargs, &block) {
          block.call(fake_http)
        }) do
          client = News::Translation::Client.new
          result = client.translate_article(
            source_lang: "en",
            target_lang: "ru",
            title: "Hello",
            preview_text: "Preview",
            body_text: "Body"
          )

          assert_equal "Привет", result.translated_title
        end
      end
    end

    assert_includes events, [:health, "/health"]
    assert_includes events, [:translate, "host.docker.internal", 19191]
  end

  test "client ignores an unreachable configured translator url and falls back" do
    rails_env = ActiveSupport::StringInquirer.new("production")
    events = []
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.define_singleton_method(:body) do
      JSON.generate(
        request_id: "req-2",
        translated_title: "Привет",
        translated_preview_text: "Превью",
        translated_body_text: "Тело",
        model: "test-translator",
        status: "ok"
      )
    end

    fake_http = Object.new
    fake_http.define_singleton_method(:get) do |path|
      events << [:health, path]
      Net::HTTPOK.new("1.1", "200", "OK")
    end
    fake_http.define_singleton_method(:request) do |request|
      events << [:translate, request.uri.host, request.uri.port]
      response
    end

    credentials = Class.new do
      def dig(*path)
        return "http://127.0.0.1:19191" if path == [:translation, :base_url]
        return "secret" if path == [:translation, :token]

        nil
      end

      def [](key)
        return { base_url: "http://127.0.0.1:19191", token: "secret" } if key == :translation

        nil
      end
    end.new

    with_credentials(credentials) do
      Rails.stub(:env, rails_env) do
        with_stubbed_constant(Net::HTTP, :start, ->(_host, _port, **_kwargs, &block) {
          block.call(fake_http)
        }) do
          client = News::Translation::Client.new
          result = client.translate_article(
            source_lang: "en",
            target_lang: "ru",
            title: "Hello",
            preview_text: "Preview",
            body_text: "Body"
          )

          assert_equal "Привет", result.translated_title
        end
      end
    end

    assert_includes events, [:translate, "host.docker.internal", 19191]
    refute_includes events, [:translate, "127.0.0.1", 19191]
  end
end
