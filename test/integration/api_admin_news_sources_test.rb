require "test_helper"

class ApiAdminNewsSourcesTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(
      email: "admin-news@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: :admin,
      active: true
    )
  end

  test "admin can create source and section" do
    csrf = login_as(@admin)

    post "/api/admin/news_sources",
      params: {
        name: "Reuters",
        base_url: "https://www.reuters.com",
        active: true,
        crawl_delay_min_seconds: 0,
        crawl_delay_max_seconds: 0,
        config: {
          list_item_selector: "article"
        }
      }.to_json,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "X-CSRF-Token" => csrf
      }

    assert_response :created
    source_id = json_response.dig("news_source", "id")

    post "/api/admin/news_sources/#{source_id}/news_sections",
      params: {
        name: "World",
        url: "https://www.reuters.com/world/",
        active: true,
        config: {
          list_item_selector: "article"
        }
      }.to_json,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "X-CSRF-Token" => csrf
      }

    assert_response :created
    assert_equal "World", json_response.dig("news_section", "name")
  end

  test "admin can queue crawl for all source sections" do
    source = NewsSource.create!(name: "Reuters", base_url: "https://www.reuters.com", active: true)
    source.news_sections.create!(name: "World", url: "https://www.reuters.com/world/", active: true)
    source.news_sections.create!(name: "Business", url: "https://www.reuters.com/business/", active: true)
    csrf = login_as(@admin)
    queued = []

    original = NewsCrawlSectionJob.method(:perform_async)
    NewsCrawlSectionJob.define_singleton_method(:perform_async) do |section_id|
      queued << section_id
    end

    begin
      post "/api/admin/news_sources/#{source.id}/crawl",
        headers: {
          "CONTENT_TYPE" => "application/json",
          "X-CSRF-Token" => csrf
        }

      assert_response :success
    ensure
      NewsCrawlSectionJob.define_singleton_method(:perform_async, original.to_proc)
    end

    assert_equal source.news_sections.pluck(:id).sort, queued.sort
  end
end
