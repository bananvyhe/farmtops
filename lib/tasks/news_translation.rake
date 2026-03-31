namespace :news do
  namespace :translation do
    desc "Recover the translation queue after deploy or a translator outage"
    task recover: :environment do
      result = News::Translation::Recovery.new.call

      puts "Cleared stale lock: #{result[:cleared_lock]}"
      puts "Reset recent failed articles: #{result[:reset_recent_failed]}"
      puts "Enqueued translation job: #{result[:enqueued]}"
    end

    desc "Rebuild translated body HTML for a single article from the saved source HTML"
    task :rebuild_html, [:article_id] => :environment do |_task, args|
      article_id = args[:article_id].to_s.strip
      raise ArgumentError, "article_id is required" if article_id.blank?

      article = NewsArticle.find(article_id)
      source_html = article.raw_payload.to_h["source_body_html"].to_s
      raise ArgumentError, "source_body_html is missing for article #{article_id}" if source_html.blank?

      body_text = article.body_text.to_s
      rebuilt_html = News::Translation::HtmlBodyRenderer.new(source_html: source_html).call(body_text)

      article.update!(body_html: rebuilt_html)

      puts "Rebuilt body_html for article #{article.id}"
    end
  end
end
