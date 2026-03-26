require "test_helper"

class NewsTranslatePendingArticlesJobTest < ActiveSupport::TestCase
  class FakeRedis
    def initialize
      @store = {}
    end

    def set(key, value, nx: false, ex: nil)
      return false if nx && @store.key?(key)

      @store[key] = value
      true
    end

    def get(key)
      @store[key]
    end

    def del(key)
      @store.delete(key)
    end

    def expire(_key, _ttl)
      true
    end
  end

  class FakeClient
    def initialize(article_ids)
      @article_ids = article_ids
    end

    def translate_article(**kwargs)
      @article_ids << kwargs[:source_article_id]

      News::Translation::Result.new(
        request_id: "req-1",
        translated_title: "Translated #{kwargs[:title]}",
        translated_preview_text: "Translated #{kwargs[:preview_text]}",
        translated_body_text: "Translated #{kwargs[:body_text]}",
        model: "fake-translator",
        latency_ms: 1,
        status: "ok",
        error: nil
      )
    end
  end

  setup do
    source = NewsSource.create!(
      name: "Example",
      base_url: "https://example.com",
      active: true,
      crawl_delay_min_seconds: 0,
      crawl_delay_max_seconds: 0
    )
    @section = source.news_sections.create!(
      name: "Main",
      url: "https://example.com/news",
      active: true
    )

    @articles = 2.times.map do |index|
      @section.news_articles.create!(
        news_source: source,
        news_section: @section,
        source_article_id: "article-#{index + 1}",
        canonical_url: "https://example.com/news/#{index + 1}",
        title: "Article #{index + 1}",
        preview_text: "Preview #{index + 1}",
        body_text: "Body #{index + 1}",
        body_html: "<p>Body #{index + 1}</p>",
        fetched_at: Time.current,
        content_hash: "hash-#{index + 1}",
        raw_payload: {},
        source_title: "Article #{index + 1}",
        source_preview_text: "Preview #{index + 1}",
        source_body_text: "Body #{index + 1}",
        translation_status: :pending,
        translation_target_locale: "ru",
        translation_source_locale: "en"
      )
    end
  end

  test "processes pending articles one by one in creation order" do
    article_ids = []
    fake_client = FakeClient.new(article_ids)
    job = NewsTranslatePendingArticlesJob.new

    job.stub(:redis, FakeRedis.new) do
      News::Translation::Client.stub(:new, fake_client) do
        job.perform
      end
    end

    assert_equal %w[article-1 article-2], article_ids
    assert_equal %w[translated translated], @articles.map(&:reload).map(&:translation_status)
  end
end
