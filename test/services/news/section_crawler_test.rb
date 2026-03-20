require "test_helper"

class News::SectionCrawlerTest < ActiveSupport::TestCase
  class FakeClient
    def initialize(pages)
      @pages = pages
    end

    def fetch(url)
      @pages.fetch(url)
    end
  end

  class NullSleeper
    def pause!
    end
  end

  setup do
    @source = NewsSource.create!(
      name: "Example",
      base_url: "https://example.com",
      active: true,
      crawl_delay_min_seconds: 0,
      crawl_delay_max_seconds: 0,
      config: {
        "list_item_selector" => "article",
        "listing_url_selector" => "a[href]",
        "listing_title_selector" => "h2",
        "listing_preview_selector" => ".preview",
        "article_title_selector" => "h1",
        "article_body_selector" => ".story-body",
        "next_page_selector" => "a[rel='next']",
        "article_image_selector" => "meta[property='og:image']"
      }
    )
    @section = @source.news_sections.create!(
      name: "Main",
      url: "https://example.com/news",
      active: true,
      config: {
        "list_item_selector" => "article",
        "listing_url_selector" => "a[href]",
        "listing_title_selector" => "h2",
        "listing_preview_selector" => ".preview",
        "article_title_selector" => "h1",
        "article_body_selector" => ".story-body",
        "next_page_selector" => "a[rel='next']",
        "article_image_selector" => "meta[property='og:image']"
      }
    )
  end

  test "crawls listing pages, fetches full articles and skips duplicate content hashes" do
    pages = {
      "https://example.com/news" => listing_page(
        [
          { title: "First", href: "/news/first-a", preview: "Preview first" },
          { title: "Second", href: "/news/second", preview: "Preview second" }
        ],
        next_page: "/news/page-2"
      ),
      "https://example.com/news/page-2" => listing_page(
        [
          { title: "First duplicate", href: "/archive/first-b", preview: "Preview first duplicate" }
        ]
      ),
      "https://example.com/news/first-a" => article_page(
        title: "First",
        body: "Body one",
        image_url: "https://cdn.example.com/first.jpg",
        canonical_url: "https://example.com/news/first-a"
      ),
      "https://example.com/news/second" => article_page(
        title: "Second",
        body: "Body two",
        image_url: "https://cdn.example.com/second.jpg",
        canonical_url: "https://example.com/news/second"
      ),
      "https://example.com/archive/first-b" => article_page(
        title: "First",
        body: "Body one",
        image_url: "https://cdn.example.com/first.jpg",
        canonical_url: "https://example.com/archive/first-b"
      )
    }

    result = News::SectionCrawler.new(
      section: @section,
      client: FakeClient.new(pages),
      sleeper: NullSleeper.new,
      max_articles: 12,
      max_pages: 5,
      max_retries: 1
    ).call

    assert_equal 2, result.articles_saved
    assert_equal 1, result.articles_skipped
    assert_equal 2, result.pages_visited
    assert_equal 2, @section.news_articles.count
    assert_equal "First", @section.news_articles.find_by!(canonical_url: "https://example.com/news/first-a").title
    assert_equal "Body one", @section.news_articles.find_by!(canonical_url: "https://example.com/news/first-a").body_text
    assert_equal "https://cdn.example.com/first.jpg", @section.news_articles.find_by!(canonical_url: "https://example.com/news/first-a").image_url
  end

  test "stops after twelve saved articles" do
    items = 13.times.map do |index|
      {
        title: "Article #{index + 1}",
        href: "/news/article-#{index + 1}",
        preview: "Preview #{index + 1}"
      }
    end

    pages = {
      "https://example.com/news" => listing_page(items.first(8), next_page: "/news/page-2"),
      "https://example.com/news/page-2" => listing_page(items.last(5))
    }

    items.each do |item|
      pages["https://example.com#{item[:href]}"] = article_page(
        title: item[:title],
        body: "Body for #{item[:title]}",
        image_url: "https://cdn.example.com/#{item[:href].split("/").last}.jpg",
        canonical_url: "https://example.com#{item[:href]}"
      )
    end

    result = News::SectionCrawler.new(
      section: @section,
      client: FakeClient.new(pages),
      sleeper: NullSleeper.new,
      max_articles: 12,
      max_pages: 5,
      max_retries: 1
    ).call

    assert_equal 12, result.articles_saved
    assert_equal 12, @section.news_articles.count
  end

  test "crawls rss feeds when configured for feed pagination" do
    source = NewsSource.create!(
      name: "Feed Example",
      base_url: "https://feed.example.com",
      active: true,
      crawl_delay_min_seconds: 0,
      crawl_delay_max_seconds: 0,
      config: {
        "pagination_mode" => "feed"
      }
    )
    section = source.news_sections.create!(
      name: "Feed",
      url: "https://feed.example.com/category/news/",
      active: true,
      config: {
        "pagination_mode" => "feed"
      }
    )

    pages = {
      "https://feed.example.com/category/news/feed/" => feed_page(
        [
          {
            title: "Feed One",
            link: "https://feed.example.com/posts/one",
            description: "Feed preview one",
            guid: "one"
          },
          {
            title: "Feed Two",
            link: "https://feed.example.com/posts/two",
            description: "Feed preview two",
            guid: "two"
          }
        ]
      ),
      "https://feed.example.com/posts/one" => article_page(
        title: "Feed One",
        body: "Feed body one",
        image_url: "https://cdn.example.com/feed-one.jpg",
        canonical_url: "https://feed.example.com/posts/one"
      ),
      "https://feed.example.com/posts/two" => article_page(
        title: "Feed Two",
        body: "Feed body two",
        image_url: "https://cdn.example.com/feed-two.jpg",
        canonical_url: "https://feed.example.com/posts/two"
      )
    }

    result = News::SectionCrawler.new(
      section:,
      client: FakeClient.new(pages),
      sleeper: NullSleeper.new,
      max_articles: 12,
      max_pages: 5,
      max_retries: 1
    ).call

    assert_equal 2, result.articles_saved
    assert_equal 1, result.pages_visited
    assert_equal 2, section.news_articles.count
    assert_equal "Feed One", section.news_articles.find_by!(canonical_url: "https://feed.example.com/posts/one").title
  end

  test "prefers json ld article body html when present" do
    pages = {
      "https://example.com/news/json-ld" => article_page(
        title: "Json LD",
        body: "Fallback body",
        image_url: "https://cdn.example.com/json-ld.jpg",
        canonical_url: "https://example.com/news/json-ld",
        article_body_html: <<~HTML
          <p>First paragraph</p>
          <p>Second paragraph with <a href="/relative">link</a></p>
          <div class="video">
            <iframe src="/embed/video"></iframe>
          </div>
        HTML
      )
    }

    listing = listing_page(
      [
        { title: "Json LD", href: "/news/json-ld", preview: "Preview json ld" }
      ]
    )
    pages["https://example.com/news"] = listing

    result = News::SectionCrawler.new(
      section: @section,
      client: FakeClient.new(pages),
      sleeper: NullSleeper.new,
      max_articles: 12,
      max_pages: 2,
      max_retries: 1
    ).call

    assert_equal 1, result.articles_saved
    article = @section.news_articles.find_by!(canonical_url: "https://example.com/news/json-ld")
    assert_includes article.body_html, "First paragraph"
    assert_includes article.body_html, "https://example.com/embed/video"
    assert_includes article.body_text, "Second paragraph"
  end

  test "refreshes existing article when the new body html is richer" do
    NewsArticle.create!(
      news_source: @source,
      news_section: @section,
      source_article_id: "https://example.com/news/rich",
      canonical_url: "https://example.com/news/rich",
      title: "Rich article",
      preview_text: "Old preview",
      body_text: "Old text",
      body_html: "<p>Old text</p>",
      image_url: "https://cdn.example.com/old.jpg",
      published_at: Time.zone.now,
      fetched_at: Time.zone.now,
      content_hash: Digest::SHA256.hexdigest([@source.id, "Rich article", "Old text", "https://cdn.example.com/old.jpg"].join("|")),
      raw_payload: {}
    )

    pages = {
      "https://example.com/news" => listing_page(
        [
          { title: "Rich article", href: "/news/rich", preview: "New preview" }
        ]
      ),
      "https://example.com/news/rich" => article_page(
        title: "Rich article",
        body: "New body fallback",
        image_url: "https://cdn.example.com/new.jpg",
        canonical_url: "https://example.com/news/rich",
        article_body_html: <<~HTML
          <p>Updated paragraph one</p>
          <p>Updated paragraph two</p>
        HTML
      )
    }

    result = News::SectionCrawler.new(
      section: @section,
      client: FakeClient.new(pages),
      sleeper: NullSleeper.new,
      max_articles: 12,
      max_pages: 2,
      max_retries: 1
    ).call

    assert_equal 1, result.articles_saved
    article = @section.news_articles.find_by!(source_article_id: "https://example.com/news/rich")
    assert_includes article.body_html, "Updated paragraph one"
    assert_includes article.body_html, "Updated paragraph two"
    assert_includes article.body_text, "Updated paragraph one"
    assert_equal "https://cdn.example.com/new.jpg", article.image_url
  end

  test "increments start pagination offsets" do
    source = NewsSource.create!(
      name: "Offset Example",
      base_url: "https://offset.example.com",
      active: true,
      crawl_delay_min_seconds: 0,
      crawl_delay_max_seconds: 0,
      config: {
        "pagination_mode" => "start",
        "pagination_step" => 50
      }
    )
    section = source.news_sections.create!(
      name: "Latest",
      url: "https://offset.example.com/latest",
      active: true,
      config: {
        "pagination_mode" => "start",
        "pagination_step" => 50
      }
    )

    pages = {
      "https://offset.example.com/latest" => listing_page(
        [
          { title: "Offset One", href: "/posts/one", preview: "Preview one" }
        ],
        next_page: "https://offset.example.com/latest?start=50"
      ),
      "https://offset.example.com/latest?start=50" => listing_page(
        [
          { title: "Offset Two", href: "/posts/two", preview: "Preview two" }
        ],
        next_page: "https://offset.example.com/latest?start=100"
      ),
      "https://offset.example.com/latest?start=100" => listing_page(
        []
      ),
      "https://offset.example.com/posts/one" => article_page(
        title: "Offset One",
        body: "Body one",
        image_url: "https://cdn.example.com/one.jpg",
        canonical_url: "https://offset.example.com/posts/one"
      ),
      "https://offset.example.com/posts/two" => article_page(
        title: "Offset Two",
        body: "Body two",
        image_url: "https://cdn.example.com/two.jpg",
        canonical_url: "https://offset.example.com/posts/two"
      )
    }

    result = News::SectionCrawler.new(
      section:,
      client: FakeClient.new(pages),
      sleeper: NullSleeper.new,
      max_articles: 12,
      max_pages: 5,
      max_retries: 1
    ).call

    assert_equal 2, result.articles_saved
    assert_equal 3, result.pages_visited
    assert_equal 2, section.news_articles.count
  end

  private

  def listing_page(items, next_page: nil)
    article_markup = items.map do |item|
      <<~HTML
        <article>
          <h2><a href="#{item[:href]}">#{item[:title]}</a></h2>
          <p class="preview">#{item[:preview]}</p>
        </article>
      HTML
    end.join

    next_markup = next_page ? %(<a rel="next" href="#{next_page}">Next</a>) : ""

    <<~HTML
      <html>
        <body>
          #{article_markup}
          #{next_markup}
        </body>
      </html>
    HTML
  end

  def article_page(title:, body:, image_url:, canonical_url:, article_body_html: nil)
    content_html = article_body_html.presence || "<p>#{body}</p>"
    content_html = "<div class=\"story-body\">#{content_html}</div>" if article_body_html.blank?

    json_ld = {
      "@context" => "https://schema.org",
      "@type" => "NewsArticle",
      "headline" => title,
      "articleBody" => article_body_html.presence || body,
      "image" => image_url,
      "mainEntityOfPage" => canonical_url
    }.to_json

    <<~HTML
      <html>
        <head>
          <meta property="og:image" content="#{image_url}">
          <link rel="canonical" href="#{canonical_url}">
          <script type="application/ld+json">#{json_ld}</script>
        </head>
        <body>
          <h1>#{title}</h1>
          <time datetime="2026-03-20T09:00:00+05:00"></time>
          #{content_html}
        </body>
      </html>
    HTML
  end

  def feed_page(items)
    entries = items.map do |item|
      <<~XML
        <item>
          <title>#{item[:title]}</title>
          <link>#{item[:link]}</link>
          <guid>#{item[:guid]}</guid>
          <description>#{item[:description]}</description>
        </item>
      XML
    end.join

    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Feed Example</title>
          #{entries}
        </channel>
      </rss>
    XML
  end
end
