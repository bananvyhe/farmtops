class CreateNewsArticleGames < ActiveRecord::Migration[8.0]
  def change
    create_table :news_article_games do |t|
      t.references :news_article, null: false, foreign_key: true, index: { unique: true }
      t.references :game, foreign_key: true
      t.string :request_id, null: false
      t.string :identified_game_name, null: false
      t.string :slug
      t.decimal :confidence, precision: 5, scale: 4
      t.string :model
      t.string :external_game_id
      t.jsonb :raw_response, null: false, default: {}

      t.timestamps
    end

    add_index :news_article_games, :request_id
    add_index :news_article_games, :slug
  end
end
