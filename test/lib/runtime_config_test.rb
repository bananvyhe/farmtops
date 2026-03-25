require "test_helper"

class RuntimeConfigTest < ActiveSupport::TestCase
  def with_credentials(credentials)
    Rails.application.singleton_class.define_method(:credentials) { credentials }
    yield
  ensure
    Rails.application.singleton_class.send(:remove_method, :credentials)
  end

  test "env_or_credential falls back to top level credentials key" do
    credentials = Class.new do
      def initialize(values)
        @values = values
      end

      def dig(*path)
        @values.dig(*path)
      end

      def [](key)
        @values[key]
      end
    end.new(
      {
        NEWS_TRANSLATOR_TOKEN: "top-level-token"
      }
    )

    with_credentials(credentials) do
      assert_equal "top-level-token", RuntimeConfig.env_or_credential("NEWS_TRANSLATOR_TOKEN", :translation, :token)
    end
  end

  test "env_or_credential still prefers nested credentials when present" do
    credentials = Class.new do
      def initialize(values)
        @values = values
      end

      def dig(*path)
        @values.dig(*path)
      end

      def [](key)
        @values[key]
      end
    end.new(
      {
        NEWS_TRANSLATOR_TOKEN: "top-level-token",
        translation: { token: "nested-token" }
      }
    )

    with_credentials(credentials) do
      assert_equal "nested-token", RuntimeConfig.env_or_credential("NEWS_TRANSLATOR_TOKEN", :translation, :token)
    end
  end

  test "env_or_credential accepts top level X_Translation_Token key" do
    credentials = Class.new do
      def initialize(values)
        @values = values
      end

      def dig(*path)
        @values.dig(*path)
      end

      def [](key)
        @values[key]
      end
    end.new(
      {
        "X_Translation_Token" => "header-style-token"
      }
    )

    with_credentials(credentials) do
      assert_equal "header-style-token", RuntimeConfig.env_or_credential("NEWS_TRANSLATOR_TOKEN", :translation, :token)
    end
  end
end
