class CreateNewsArticleReads < ActiveRecord::Migration[7.2]
  def change
    create_table :news_article_reads do |t|
      t.references :news_article, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.uuid :visitor_uuid
      t.datetime :read_at, null: false

      t.timestamps
    end

    add_index :news_article_reads, [:news_article_id, :user_id], unique: true, where: "user_id IS NOT NULL"
    add_index :news_article_reads, [:news_article_id, :visitor_uuid], unique: true, where: "visitor_uuid IS NOT NULL"
    add_index :news_article_reads, [:user_id, :read_at]
    add_index :news_article_reads, [:visitor_uuid, :read_at]
  end
end
