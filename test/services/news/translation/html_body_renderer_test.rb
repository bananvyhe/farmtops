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

  test "unwraps formatting tags when a nested wrapper contains block elements" do
    renderer = News::Translation::HtmlBodyRenderer.new(
      source_html: "<strong><span><p>Source heading</p><p>Source paragraph</p></span></strong>"
    )

    html = renderer.call("Translated heading\n\nTranslated paragraph")

    refute_match(/<strong[^>]*>.*<p>/m, html)
    assert_includes html, "<p>Translated heading</p>"
    assert_includes html, "<p>Translated paragraph</p>"
  end

  test "removes a body h1 without consuming the first translated paragraph" do
    renderer = News::Translation::HtmlBodyRenderer.new(
      source_html: "<h1>Source title</h1><p>Source paragraph</p>"
    )

    html = renderer.call("Translated paragraph")

    assert_includes html, "<p>Translated paragraph</p>"
    refute_includes html, "Source title"
    refute_includes html, "Source paragraph"
  end

  test "keeps an inline-only div heading as one translated block" do
    renderer = News::Translation::HtmlBodyRenderer.new(
      source_html: '<div><strong>Source heading</strong></div><p>Source paragraph</p>'
    )

    html = renderer.call("Translated heading\n\nTranslated paragraph")

    assert_includes html, "<div><strong>Translated heading</strong></div>"
    assert_includes html, "<p>Translated paragraph</p>"
    refute_includes html, "Source heading"
  end

  test "keeps inline formatting inside a regular heading block" do
    renderer = News::Translation::HtmlBodyRenderer.new(
      source_html: "<p><strong>Source heading</strong></p><p>Source paragraph</p>"
    )

    html = renderer.call("Translated heading\n\nTranslated paragraph")

    assert_includes html, "<p><strong>Translated heading</strong></p>"
    assert_includes html, "<p>Translated paragraph</p>"
  end
end
