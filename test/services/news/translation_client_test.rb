require "test_helper"

class News::TranslationClientTest < ActiveSupport::TestCase
  def with_credentials(credentials)
    Rails.application.singleton_class.define_method(:credentials) { credentials }
    yield
  ensure
    Rails.application.singleton_class.send(:remove_method, :credentials)
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
end
