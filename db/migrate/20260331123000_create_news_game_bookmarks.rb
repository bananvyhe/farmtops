class CreateNewsGameBookmarks < ActiveRecord::Migration[8.0]
  def change
    create_table :news_game_bookmarks do |t|
      t.bigint :game_id, null: false
      t.bigint :user_id
      t.uuid :visitor_uuid
      t.datetime :bookmarked_at, null: false
      t.timestamps
    end

    add_index :news_game_bookmarks, :game_id
    add_index :news_game_bookmarks, [:game_id, :user_id], unique: true, where: "user_id IS NOT NULL"
    add_index :news_game_bookmarks, [:game_id, :visitor_uuid], unique: true, where: "visitor_uuid IS NOT NULL"
    add_index :news_game_bookmarks, [:user_id, :bookmarked_at]
    add_index :news_game_bookmarks, [:visitor_uuid, :bookmarked_at]

    add_foreign_key :news_game_bookmarks, :games
    add_foreign_key :news_game_bookmarks, :users
  end
end
