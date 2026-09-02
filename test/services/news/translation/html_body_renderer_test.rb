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
end
