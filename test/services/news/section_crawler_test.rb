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

  test "stops after the first listing item even when it already exists in the database" do
    @section.news_articles.create!(
      news_source: @source,
      canonical_url: "https://example.com/news/duplicate-a",
      source_article_id: "https://example.com/news/duplicate-a",
      fetched_at: Time.current,
      content_hash: "existing-hash",
      translation_status: :pending
    )

    pages = {
      "https://example.com/news" => listing_page(
        [
          { title: "Duplicate", href: "/news/duplicate-a", preview: "Preview duplicate" }
        ],
        next_page: "/news/page-2"
      ),
      "https://example.com/news/page-2" => listing_page(
        [
          { title: "Should not crawl", href: "/news/should-not-crawl", preview: "Preview should not crawl" }
        ]
      ),
      "https://example.com/news/should-not-crawl" => article_page(
        title: "Should not crawl",
        body: "Body should not be fetched",
        image_url: "https://cdn.example.com/should-not-crawl.jpg",
        canonical_url: "https://example.com/news/should-not-crawl"
      )
    }

    result = News::SectionCrawler.new(
      section: @section,
      client: FakeClient.new(pages),
      sleeper: NullSleeper.new,
      max_articles: 1,
      max_pages: 5,
      max_retries: 1
    ).call

    assert_equal 1, result.articles_found
    assert_equal 0, result.articles_saved
    assert_equal 1, result.pages_visited
    assert_nil @section.news_articles.find_by(canonical_url: "https://example.com/news/should-not-crawl")
  end

  test "saves original article content and marks translation as pending" do
    pages = {
      "https://example.com/news" => listing_page(
        [
          { title: "First", href: "/news/first-a", preview: "Preview first" }
        ]
      ),
      "https://example.com/news/first-a" => article_page(
        title: "First",
        body: "Body one\n\nSecond paragraph",
        image_url: "https://cdn.example.com/first.jpg",
        canonical_url: "https://example.com/news/first-a"
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

    assert_equal 1, result.articles_saved
    article = @section.news_articles.find_by!(canonical_url: "https://example.com/news/first-a")
    assert_equal "First", article.title
    assert_equal "Preview first", article.preview_text
    assert_equal "Body one\n\nSecond paragraph", article.body_text
    assert_includes article.body_text, "\n\n"
    assert_equal "First", article.source_title
    assert_equal "Preview first", article.source_preview_text
    assert_equal "Body one\n\nSecond paragraph", article.source_body_text
    assert_equal "pending", article.translation_status
    assert_nil article.translated_at
    assert_nil article.translation_model
    assert_equal "ru", article.translation_target_locale
    assert_equal "en", article.translation_source_locale
  end

  test "saves the original article when translation fails" do
    pages = {
      "https://example.com/news" => listing_page(
        [
          { title: "First", href: "/news/first-a", preview: "Preview first" }
        ]
      ),
      "https://example.com/news/first-a" => article_page(
        title: "First",
        body: "Body one",
        image_url: "https://cdn.example.com/first.jpg",
        canonical_url: "https://example.com/news/first-a"
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

    assert_equal 1, result.articles_saved
    assert_equal 0, result.articles_skipped

    article = @section.news_articles.find_by!(canonical_url: "https://example.com/news/first-a")
    assert_equal "First", article.title
    assert_equal "First", article.source_title
    assert_equal "Body one", article.body_text
    assert_equal "Body one", article.source_body_text
    assert_equal "pending", article.translation_status
    assert_nil article.translated_at
    assert_nil article.translation_model
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
        body: "Feed body one with significantly more context than the feed preview, including additional background and details for readers.",
        image_url: "https://cdn.example.com/feed-one.jpg",
        canonical_url: "https://feed.example.com/posts/one"
      ),
      "https://feed.example.com/posts/two" => article_page(
        title: "Feed Two",
        body: "Feed body two with significantly more context than the feed preview, including additional background and details for readers.",
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
    assert_includes section.news_articles.find_by!(canonical_url: "https://feed.example.com/posts/one").body_text, "significantly more context"
  end

  test "uses the full article page for feed sources when it is richer than the feed excerpt" do
    source = NewsSource.create!(
      name: "MassivelyOP",
      base_url: "https://massivelyop.com",
      active: true,
      crawl_delay_min_seconds: 0,
      crawl_delay_max_seconds: 0,
      config: {
        "pagination_mode" => "feed"
      }
    )
    section = source.news_sections.create!(
      name: "Patch",
      url: "https://massivelyop.com/category/patch/",
      active: true,
      config: {
        "pagination_mode" => "feed"
      }
    )

    pages = {
      "https://massivelyop.com/category/patch/feed/" => feed_page(
        [
          {
            title: "Patch Article",
            link: "https://massivelyop.com/2026/03/20/patch-article/",
            description: "Short feed preview",
            guid: "patch-article"
          }
        ]
      ),
      "https://massivelyop.com/2026/03/20/patch-article/" => article_page(
        title: "Patch Article",
        body: "This is the full article body with far more detail than the feed preview.",
        image_url: "https://massivelyop.com/wp-content/uploads/2026/03/patch.jpg",
        canonical_url: "https://massivelyop.com/2026/03/20/patch-article/",
        article_body_html: <<~HTML
          <div><img src="https://massivelyop.com/wp-content/uploads/2026/03/patch.jpg"></div>
          <p>This is the full article body with far more detail than the feed preview.</p>
          <p>Another paragraph that should not be lost.</p>
        HTML
      )
    }

    result = News::SectionCrawler.new(
      section:,
      client: FakeClient.new(pages),
      sleeper: NullSleeper.new,
      max_articles: 12,
      max_pages: 2,
      max_retries: 1
    ).call

    assert_equal 1, result.articles_saved
    article = section.news_articles.find_by!(canonical_url: "https://massivelyop.com/2026/03/20/patch-article/")
    assert_includes article.body_text, "far more detail"
    assert_includes article.body_html, "Another paragraph"
    refute_includes article.body_text, "Short feed preview"
  end

  test "captures listing preview html while deriving card preview text from the full article body" do
    pages = {
      "https://example.com/news" => <<~HTML,
        <html>
          <body>
            <article>
              <h2><a href="/news/rich-preview">Rich preview</a></h2>
              <div class="preview"><p>Listing <strong>preview</strong> with <em>markup</em>.</p></div>
            </article>
          </body>
        </html>
      HTML
      "https://example.com/news/rich-preview" => article_page(
        title: "Rich preview",
        body: "Full body first paragraph.\n\nFull body second paragraph with more details.",
        image_url: "https://cdn.example.com/rich-preview.jpg",
        canonical_url: "https://example.com/news/rich-preview",
        article_body_html: <<~HTML
          <article class="story-body">
            <p>Full body first paragraph.</p>
            <p>Full body second paragraph with more details.</p>
          </article>
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
    article = @section.news_articles.find_by!(canonical_url: "https://example.com/news/rich-preview")
    assert_includes article.preview_html, "<strong>preview</strong>"
    assert_includes article.preview_html, "<em>markup</em>"
    refute_includes article.preview_text, "Listing preview"
    assert_includes article.preview_text, "Full body first paragraph"
  end

  test "prefers lazy preview images from listing pages" do
    source = NewsSource.create!(
      name: "PlayToEarn",
      base_url: "https://playtoearn.com",
      active: true,
      crawl_delay_min_seconds: 0,
      crawl_delay_max_seconds: 0,
      config: {
        "list_item_selector" => "article",
        "listing_url_selector" => "a[href]",
        "listing_title_selector" => "h2 a",
        "listing_preview_selector" => "p",
        "listing_image_selector" => "img",
        "article_title_selector" => "h1",
        "article_body_selector" => "article",
        "article_image_selector" => "meta[property='og:image'], img"
      }
    )
    section = source.news_sections.create!(
      name: "News",
      url: "https://playtoearn.com/news/category/News",
      active: true,
      config: source.config
    )

    pages = {
      "https://playtoearn.com/news/category/News" => <<~HTML,
        <html>
          <body>
            <article>
              <h2><a href="/news/lazy-image">Lazy image</a></h2>
              <p class="preview">Preview text</p>
              <img src="https://assets.playtoearn.com/img/load.png" data-src="https://img.playtoearn.com/news/lazy-image.jpg">
            </article>
          </body>
        </html>
      HTML
      "https://playtoearn.com/news/lazy-image" => article_page(
        title: "Lazy image",
        body: "Body with lazy image",
        image_url: "https://img.playtoearn.com/news/lazy-image.jpg",
        canonical_url: "https://playtoearn.com/news/lazy-image"
      )
    }

    result = News::SectionCrawler.new(
      section:,
      client: FakeClient.new(pages),
      sleeper: NullSleeper.new,
      max_articles: 12,
      max_pages: 2,
      max_retries: 1
    ).call

    assert_equal 1, result.articles_saved
    article = section.news_articles.find_by!(canonical_url: "https://playtoearn.com/news/lazy-image")
    assert_equal "https://img.playtoearn.com/news/lazy-image.jpg", article.image_url
  end

  test "strips playtoearn footer links from the article body" do
    source = NewsSource.create!(
      name: "PlayToEarn Footer",
      base_url: "https://playtoearn.com",
      active: true,
      crawl_delay_min_seconds: 0,
      crawl_delay_max_seconds: 0,
      config: {
        "article_body_exclude_selectors" => ".__Info, footer"
      }
    )
    section = source.news_sections.create!(
      name: "News",
      url: "https://playtoearn.com/news/category/News",
      active: true,
      config: source.config
    )

    pages = {
      "https://playtoearn.com/news/category/News" => <<~HTML,
        <html>
          <body>
            <article>
              <h2><a href="/news/footer-article">Footer article</a></h2>
              <p class="preview">Feed preview</p>
            </article>
          </body>
        </html>
      HTML
      "https://playtoearn.com/news/footer-article" => article_page(
        title: "Footer article",
        body: "Body with footer and much more surrounding context so the full article page is clearly richer than the feed preview.",
        image_url: "https://img.playtoearn.com/news/footer.jpg",
        canonical_url: "https://playtoearn.com/news/footer-article",
        article_body_html: <<~HTML
          <article>
            <p>Intro</p>
            <div class="__Info">
              <a href="/news/category/News">News on PlayToEarn</a>
              <a href="/about">About</a>
            </div>
            <p>Outro</p>
          </article>
        HTML
      )
    }

    result = News::SectionCrawler.new(
      section:,
      client: FakeClient.new(pages),
      sleeper: NullSleeper.new,
      max_articles: 12,
      max_pages: 2,
      max_retries: 1
    ).call

    assert_equal 1, result.articles_saved
    article = section.news_articles.find_by!(canonical_url: "https://playtoearn.com/news/footer-article")
    refute_includes article.body_html, "News on PlayToEarn"
    refute_includes article.body_html, "/about"
    assert_includes article.body_text, "Intro"
    assert_includes article.body_text, "Outro"
  end

  test "promotes lazy loaded body images to real src attributes" do
    pages = {
      "https://example.com/news" => listing_page(
        [
          { title: "Lazy image", href: "/news/lazy-image", preview: "Preview lazy image" }
        ]
      ),
      "https://example.com/news/lazy-image" => article_page(
        title: "Lazy image",
        body: "Body with lazy image",
        image_url: "https://example.com/images/hero.jpg",
        canonical_url: "https://example.com/news/lazy-image",
        article_body_html: <<~HTML
          <p>Intro paragraph</p>
          <img src="https://assets.playtoearn.com/img/load.png" class="lazy" data-src="https://img.example.com/body-image.jpg" alt="Body image">
          <p>Second paragraph</p>
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
    article = @section.news_articles.find_by!(canonical_url: "https://example.com/news/lazy-image")
    assert_includes article.body_html, "https://img.example.com/body-image.jpg"
    refute_includes article.body_html, "load.png"
  end

  test "removes duplicate smaller leading images from the article body" do
    pages = {
      "https://example.com/news" => listing_page(
        [
          { title: "Duplicate images", href: "/news/duplicate-images", preview: "Preview duplicate images" }
        ]
      ),
      "https://example.com/news/duplicate-images" => <<~HTML
        <html>
          <head>
            <meta property="og:image" content="https://example.com/images/hero.jpg">
            <link rel="canonical" href="https://example.com/news/duplicate-images">
            <title>Duplicate images</title>
          </head>
          <body>
            <article class="story-body">
              <div class="hero">
                <img src="https://example.com/images/hero.jpg" width="1200" height="675">
              </div>
              <div class="hero-small">
                <img src="https://example.com/images/hero-300x169.jpg" width="300" height="169">
              </div>
              <p>Main paragraph after the hero image.</p>
            </article>
          </body>
        </html>
      HTML
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
    article = @section.news_articles.find_by!(canonical_url: "https://example.com/news/duplicate-images")
    assert_includes article.body_html, "https://example.com/images/hero.jpg"
    refute_includes article.body_html, "hero-300x169.jpg"
  end

  test "chooses the most text rich block from a broad article container" do
    source = NewsSource.create!(
      name: "Example News",
      base_url: "https://example.com",
      active: true,
      crawl_delay_min_seconds: 0,
      crawl_delay_max_seconds: 0,
      config: {
        "article_body_selector" => "article",
        "article_image_selector" => "meta[property='og:image'], img"
      }
    )
    section = source.news_sections.create!(
      name: "Latest",
      url: "https://example.com/latest-news",
      active: true,
      config: source.config
    )

    pages = {
      "https://example.com/latest-news" => listing_page(
        [
          { title: "Example story", href: "/post/123", preview: "Preview block" }
        ]
      ),
      "https://example.com/post/123" => <<~HTML
        <html>
          <head>
            <meta property="og:image" content="https://www.tbstat.com/cdn-cgi/image/format=webp">
            <link rel="canonical" href="https://example.com/post/123">
            <title>Example story</title>
          </head>
          <body>
            <article>
              <header>
                <p class="standfirst">Short intro that should not be the main body.</p>
              </header>
              <section class="article-body">
                <p>First long paragraph of the main story.</p>
                <p>Second long paragraph of the main story with more detail.</p>
                <div class="callout">
                  <p>Third important paragraph in the text block.</p>
                </div>
              </section>
              <aside>
                <p>Sidebar noise.</p>
              </aside>
            </article>
          </body>
        </html>
      HTML
    }

    result = News::SectionCrawler.new(
      section:,
      client: FakeClient.new(pages),
      sleeper: NullSleeper.new,
      max_articles: 12,
      max_pages: 2,
      max_retries: 1
    ).call

    assert_equal 1, result.articles_saved
    article = section.news_articles.find_by!(source_article_id: "https://example.com/post/123")
    assert_includes article.body_html, "First long paragraph"
    assert_includes article.body_html, "Third important paragraph"
    refute_includes article.body_html, "Sidebar noise"
    refute_includes article.body_text, "Short intro that should not be the main body."
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

  test "skips existing article when it already exists" do
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

    assert_equal 0, result.articles_saved
    assert_equal 1, result.articles_skipped
    article = @section.news_articles.find_by!(source_article_id: "https://example.com/news/rich")
    assert_equal "Old text", article.body_text
    assert_equal "https://cdn.example.com/old.jpg", article.image_url
  end

  test "prefers data-src and srcset images over placeholder src values" do
    pages = {
      "https://example.com/news" => listing_page(
        [
          { title: "Lazy image", href: "/news/lazy-image", preview: "Preview lazy image" }
        ]
      ),
      "https://example.com/news/lazy-image" => <<~HTML
        <html>
          <head>
            <title>Lazy image</title>
          </head>
          <body>
            <article class="story-body">
              <h1>Lazy image</h1>
              <p>Body with lazy image</p>
              <img src="https://assets.playtoearn.com/img/load.png" data-src="https://img.example.com/body-image.jpg" alt="Body image">
            </article>
          </body>
        </html>
      HTML
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
    article = @section.news_articles.find_by!(canonical_url: "https://example.com/news/lazy-image")
    assert_equal "https://img.example.com/body-image.jpg", article.image_url
  end

  test "extracts the unique content block for massivelyop articles" do
    source = NewsSource.create!(
      name: "MassivelyOP",
      base_url: "https://massivelyop.com",
      active: true,
      crawl_delay_min_seconds: 0,
      crawl_delay_max_seconds: 0,
      config: {
        "article_body_selector" => ".td-post-content",
        "article_body_exclude_selectors" => ".td-post-content .td-page-meta, .td-post-content .td-post-sharing, .td-post-content .related, .td-post-content footer",
        "article_image_selector" => "meta[property='og:image'], .td-post-content img, img"
      }
    )
    section = source.news_sections.create!(
      name: "Patch",
      url: "https://massivelyop.com/category/patch/",
      active: true,
      config: source.config
    )

    pages = {
      "https://massivelyop.com/category/patch/" => listing_page(
        [
          { title: "Patch Article", href: "/2026/03/20/patch-article/", preview: "Feed preview" }
        ]
      ),
      "https://massivelyop.com/2026/03/20/patch-article/" => <<~HTML
        <html>
          <head>
            <meta property="og:image" content="https://massivelyop.com/wp-content/uploads/2026/03/patch.jpg">
            <link rel="canonical" href="https://massivelyop.com/2026/03/20/patch-article/">
            <title>Patch Article</title>
          </head>
          <body>
            <article class="td-post-content">
              <div class="td-page-content">
                <img src="https://massivelyop.com/wp-content/uploads/2026/03/patch.jpg">
                <p>This is the unique body paragraph that should remain.</p>
                <p>Another important paragraph with the article text.</p>
              </div>
              <div class="swiper">
                <img src="https://massivelyop.com/wp-content/uploads/2015/02/swipe_morningmo.png">
                <p>Every morning, the Massively Overpowered writers team up with mascot Mo.</p>
              </div>
              <footer>
                <a href="/code-of-conduct">Code of Conduct</a>
              </footer>
            </article>
          </body>
        </html>
      HTML
    }

    result = News::SectionCrawler.new(
      section:,
      client: FakeClient.new(pages),
      sleeper: NullSleeper.new,
      max_articles: 12,
      max_pages: 2,
      max_retries: 1
    ).call

    assert_equal 1, result.articles_saved
    article = section.news_articles.find_by!(canonical_url: "https://massivelyop.com/2026/03/20/patch-article/")
    assert_includes article.body_text, "unique body paragraph"
    assert_includes article.body_text, "Another important paragraph"
    refute_includes article.body_text, "Massively Overpowered writers team up with mascot Mo"
    refute_includes article.body_text, "Code of Conduct"
    assert_equal "https://massivelyop.com/wp-content/uploads/2026/03/patch.jpg", article.image_url
    refute_includes article.body_html, "swipe_morningmo.png"
  end

  test "removes a duplicated leading featured image block when it matches the article hero" do
    source = NewsSource.create!(
      name: "MassivelyOP",
      base_url: "https://massivelyop.com",
      active: true,
      crawl_delay_min_seconds: 0,
      crawl_delay_max_seconds: 0,
      config: {
        "article_body_selector" => ".td-post-content",
        "article_image_selector" => "meta[property='og:image'], .td-post-content img, img"
      }
    )
    section = source.news_sections.create!(
      name: "Patch",
      url: "https://massivelyop.com/category/patch/",
      active: true,
      config: source.config
    )

    pages = {
      "https://massivelyop.com/category/patch/" => listing_page(
        [
          { title: "Patch Article", href: "/2026/03/20/patch-article/", preview: "Feed preview" }
        ]
      ),
      "https://massivelyop.com/2026/03/20/patch-article/" => <<~HTML
        <html>
          <head>
            <meta property="og:image" content="https://massivelyop.com/wp-content/uploads/2024/03/runes-of-magic-horror-bunny-696x229.jpg">
            <link rel="canonical" href="https://massivelyop.com/2026/03/20/patch-article/">
            <title>Patch Article</title>
          </head>
          <body>
            <article class="td-post-content">
              <div class="td-post-featured-image">
                <img src="https://massivelyop.com/wp-content/uploads/2024/03/runes-of-magic-horror-bunny-696x229.jpg">
              </div>
              <p>This is the unique body paragraph that should remain.</p>
            </article>
          </body>
        </html>
      HTML
    }

    result = News::SectionCrawler.new(
      section:,
      client: FakeClient.new(pages),
      sleeper: NullSleeper.new,
      max_articles: 12,
      max_pages: 2,
      max_retries: 1
    ).call

    assert_equal 1, result.articles_saved
    article = section.news_articles.find_by!(canonical_url: "https://massivelyop.com/2026/03/20/patch-article/")
    assert_includes article.body_html, "unique body paragraph"
    refute_includes article.body_html, "td-post-featured-image"
  end

  test "preserves paragraph blocks when extracting body text" do
    pages = {
      "https://example.com/news" => listing_page(
        [
          { title: "Block article", href: "/news/block-article", preview: "Preview block article" }
        ]
      ),
      "https://example.com/news/block-article" => <<~HTML
        <html>
          <head>
            <meta property="og:image" content="https://example.com/images/block.jpg">
            <link rel="canonical" href="https://example.com/news/block-article">
            <title>Block article</title>
          </head>
          <body>
            <article class="story-body">
              <div>First block paragraph.</div>
              <div>Second block paragraph.</div>
              <blockquote>Quoted block paragraph.</blockquote>
              <div><span>Third block paragraph inside span.</span></div>
            </article>
          </body>
        </html>
      HTML
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
    article = @section.news_articles.find_by!(canonical_url: "https://example.com/news/block-article")
    assert_includes article.body_text, "First block paragraph."
    assert_includes article.body_text, "Second block paragraph."
    assert_includes article.body_text, "Quoted block paragraph."
    assert_includes article.body_text, "Third block paragraph inside span."
    assert_includes article.body_text, "\n\n"
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
