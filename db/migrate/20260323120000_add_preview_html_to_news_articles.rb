class AddPreviewHtmlToNewsArticles < ActiveRecord::Migration[7.1]
  def change
    add_column :news_articles, :preview_html, :text, default: "", null: false
  end
end
