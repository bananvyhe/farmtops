class CreateGames < ActiveRecord::Migration[8.0]
  def change
    create_table :games do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :normalized_name
      t.string :external_game_id

      t.timestamps
    end

    add_index :games, :slug, unique: true
    add_index :games, :external_game_id
  end
end
