require "test_helper"

class News::Translation::HtmlBodyRendererTest < ActiveSupport::TestCase
  test "unwraps formatting tags around block elements before translating" do
    renderer = News::Translation::HtmlBodyRenderer.new(
      source_html: "<strong><p>Source heading</p></strong><p>Source paragraph</p>"
    )

    html = renderer.call("Translated heading\n\nTranslated paragraph")

    refute_includes html, "<strong><p>"
    assert_includes html, "<p>Translated heading</p>"
    assert_includes html, "<p>Translated paragraph</p>"
  end

  test "keeps the translation sequence when the source body contains h1" do
    renderer = News::Translation::HtmlBodyRenderer.new(
      source_html: "<h1>Source title</h1><p>Source paragraph</p>"
    )

    html = renderer.call("Translated title\n\nTranslated paragraph")

    assert_includes html, "<h1>Translated title</h1>"
    assert_includes html, "<p>Translated paragraph</p>"
    refute_includes html, "Source title"
    refute_includes html, "Source paragraph"
  end
end
