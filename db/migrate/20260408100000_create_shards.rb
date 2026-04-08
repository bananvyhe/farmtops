class CreateShards < ActiveRecord::Migration[8.0]
  def change
    create_table :shards do |t|
      t.references :user, null: false, foreign_key: true
      t.references :game, null: false, foreign_key: true
      t.string :name, null: false
      t.string :world_seed, null: false
      t.integer :status, null: false, default: 0
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end

    add_index :shards, [:user_id, :game_id], unique: true
    add_index :shards, :status
  end
end
