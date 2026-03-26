class AddTranslationTrackingToNewsArticles < ActiveRecord::Migration[8.0]
  def change
    add_column :news_articles, :translation_started_at, :datetime
    add_column :news_articles, :translation_request_id, :string
    add_column :news_articles, :translation_attempts, :integer, null: false, default: 0

    add_index :news_articles, :translation_request_id
    add_index :news_articles, %i[translation_status translation_started_at]
  end
end
