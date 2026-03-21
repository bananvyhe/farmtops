class RenameNewsCrawlRunErrorsToCrawlErrors < ActiveRecord::Migration[8.0]
  def change
    rename_column :news_crawl_runs, :errors, :crawl_errors
  end
end
