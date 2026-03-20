class AddBodyHtmlToNewsArticles < ActiveRecord::Migration[8.0]
  def change
    add_column :news_articles, :body_html, :text, null: false, default: ""
  end
end
