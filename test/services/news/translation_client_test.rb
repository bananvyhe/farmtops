require "test_helper"

class News::TranslationClientTest < ActiveSupport::TestCase
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
end
