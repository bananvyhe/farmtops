class AddTranslationFieldsToNewsArticles < ActiveRecord::Migration[8.0]
  def change
    add_column :news_articles, :source_title, :text
    add_column :news_articles, :source_preview_text, :text
    add_column :news_articles, :source_body_text, :text
    add_column :news_articles, :translated_at, :datetime
    add_column :news_articles, :translation_model, :string
    add_column :news_articles, :translation_target_locale, :string, null: false, default: "ru"
    add_column :news_articles, :translation_source_locale, :string, null: false, default: "en"
  end
end
