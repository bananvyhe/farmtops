class CreateNewsCrawler < ActiveRecord::Migration[8.0]
  def change
    create_table :news_sources do |t|
      t.string :name, null: false
      t.string :base_url, null: false
      t.boolean :active, null: false, default: true
      t.integer :crawl_delay_min_seconds, null: false, default: 1
      t.integer :crawl_delay_max_seconds, null: false, default: 3
      t.jsonb :config, null: false, default: {}
      t.timestamps
    end

    add_index :news_sources, :name, unique: true

    create_table :news_sections do |t|
      t.references :news_source, null: false, foreign_key: true
      t.string :name, null: false
      t.string :url, null: false
      t.boolean :active, null: false, default: true
      t.jsonb :config, null: false, default: {}
      t.datetime :last_crawled_at
      t.timestamps
    end

    add_index :news_sections, [:news_source_id, :name], unique: true

    create_table :news_articles do |t|
      t.references :news_source, null: false, foreign_key: true
      t.references :news_section, null: false, foreign_key: true
      t.string :source_article_id
      t.string :canonical_url, null: false
      t.string :title
      t.text :preview_text
      t.text :body_text
      t.string :image_url
      t.datetime :published_at
      t.datetime :fetched_at, null: false
      t.string :content_hash, null: false
      t.jsonb :raw_payload, null: false, default: {}
      t.timestamps
    end

    add_index :news_articles, [:news_source_id, :content_hash], unique: true
    add_index :news_articles, [:news_source_id, :source_article_id], unique: true, where: "source_article_id IS NOT NULL"
    add_index :news_articles, :canonical_url
    add_index :news_articles, :published_at

    create_table :news_crawl_runs do |t|
      t.references :news_source, null: false, foreign_key: true
      t.references :news_section, foreign_key: true
      t.integer :status, null: false, default: 0
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.integer :pages_visited, null: false, default: 0
      t.integer :articles_found, null: false, default: 0
      t.integer :articles_saved, null: false, default: 0
      t.integer :articles_skipped, null: false, default: 0
      t.jsonb :errors, null: false, default: []
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :news_crawl_runs, [:news_source_id, :status]
    add_index :news_crawl_runs, :started_at
  end
end
