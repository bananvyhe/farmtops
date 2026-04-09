require "nokogiri"
require "test_helper"

class PublicAssetsTest < ActionDispatch::IntegrationTest
  setup do
    host! "farmspot.test"

    @source = NewsSource.create!(
      name: "Example",
      base_url: "https://example.com",
      active: true,
      config: {}
    )
    @section = @source.news_sections.create!(
      name: "Main",
      url: "https://example.com/news",
      active: true,
      config: {}
    )
    @article = @section.news_articles.create!(
      news_source: @source,
      news_section: @section,
      source_article_id: "news-1",
      canonical_url: "https://example.com/news/1",
      title: "Hello",
      preview_text: "Preview",
      body_text: "Body",
      image_url: "https://example.com/image.jpg",
      published_at: Time.zone.parse("2026-03-20 10:00:00"),
      translated_at: Time.zone.parse("2026-03-20 11:00:00"),
      fetched_at: Time.zone.now,
      translation_status: "translated",
      content_hash: "hash-1",
      raw_payload: {}
    )
    blocked_source = NewsSource.create!(
      name: "The Block",
      base_url: "https://stage.theblock.co",
      active: true,
      config: {}
    )
    blocked_section = blocked_source.news_sections.create!(
      name: "Latest",
      url: "https://stage.theblock.co/latest-crypto-news",
      active: true,
      config: {}
    )
    blocked_section.news_articles.create!(
      news_source: blocked_source,
      news_section: blocked_section,
      source_article_id: "blocked-1",
      canonical_url: "https://stage.theblock.co/post/1",
      title: "Blocked story",
      preview_text: "Blocked preview",
      body_text: "Blocked body",
      image_url: "https://stage.theblock.co/image.jpg",
      published_at: Time.zone.parse("2026-03-20 11:00:00"),
      translated_at: Time.zone.parse("2026-03-20 12:00:00"),
      fetched_at: Time.zone.now,
      translation_status: "translated",
      content_hash: "blocked-hash",
      raw_payload: {}
    )
  end

  test "returns a robots file that points to the sitemap" do
    get "/robots.txt"

    assert_response :success
    assert_equal "text/plain; charset=utf-8", response.content_type
    assert_includes response.body, "Disallow: /admin"
    assert_includes response.body, "Sitemap:"
    assert_includes response.body, "farmspot.test/sitemap.xml"
  end

  test "returns a sitemap with public news article urls only" do
    get "/sitemap.xml"

    assert_response :success
    assert_includes response.media_type, "xml"

    doc = Nokogiri::XML(response.body)
    locs = doc.xpath("//xmlns:loc", "xmlns" => "http://www.sitemaps.org/schemas/sitemap/0.9").map(&:text)
    blocked_article = NewsArticle.find_by!(title: "Blocked story")

    assert_includes locs, "http://farmspot.test/"
    assert_includes locs, "http://farmspot.test/news"
    assert_includes locs, "http://farmspot.test/news/#{@article.id}"
    refute_includes locs, "http://farmspot.test/news/#{blocked_article.id}"

    lastmod = doc.at_xpath("//xmlns:url[xmlns:loc='http://farmspot.test/news/#{@article.id}']/xmlns:lastmod", "xmlns" => "http://www.sitemaps.org/schemas/sitemap/0.9")
    assert lastmod.present?
  end
end
