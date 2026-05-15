class AddFullArticleAvailableToNewsArticles < ActiveRecord::Migration[8.0]
  def change
    add_column :news_articles, :full_article_available, :boolean, default: false, null: false
    add_index :news_articles, :full_article_available
  end
end
