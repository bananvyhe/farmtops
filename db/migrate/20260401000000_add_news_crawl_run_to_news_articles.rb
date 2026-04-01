class AddNewsCrawlRunToNewsArticles < ActiveRecord::Migration[8.0]
  def change
    add_reference :news_articles, :news_crawl_run, foreign_key: true, index: true
  end
end
