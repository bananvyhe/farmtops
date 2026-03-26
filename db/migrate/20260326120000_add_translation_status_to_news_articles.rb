class AddTranslationStatusToNewsArticles < ActiveRecord::Migration[8.0]
  def change
    add_column :news_articles, :translation_status, :string, null: false, default: "pending"
    add_column :news_articles, :translation_error, :text
    add_column :news_articles, :translation_completed_at, :datetime
    add_index :news_articles, [:translation_status, :created_at], name: "index_news_articles_on_translation_status_and_created_at"
  end
end
