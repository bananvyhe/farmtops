class CreateNewsTags < ActiveRecord::Migration[8.0]
  def change
    create_table :news_tags do |t|
      t.string :name, null: false
      t.string :slug, null: false

      t.timestamps
    end

    add_index :news_tags, :slug, unique: true
    add_index :news_tags, :name

    create_table :news_article_tags do |t|
      t.references :news_article, null: false, foreign_key: true
      t.references :news_tag, null: false, foreign_key: true

      t.timestamps
    end

    add_index :news_article_tags, %i[news_article_id news_tag_id], unique: true
  end
end
