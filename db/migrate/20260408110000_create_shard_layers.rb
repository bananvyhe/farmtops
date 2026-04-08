class CreateShardLayers < ActiveRecord::Migration[8.0]
  def change
    create_table :shard_layers do |t|
      t.references :shard, null: false, foreign_key: true
      t.integer :layer_index, null: false
      t.integer :status, null: false, default: 0
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end

    create_table :shard_layer_memberships do |t|
      t.references :shard, null: false, foreign_key: true
      t.references :shard_layer, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :joined_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end

    add_index :shard_layers, [:shard_id, :layer_index], unique: true
    add_index :shard_layers, :status
    add_index :shard_layer_memberships, [:shard_id, :user_id], unique: true
    add_index :shard_layer_memberships, [:shard_layer_id, :user_id], unique: true
    add_index :shard_layer_memberships, :last_seen_at
  end
end
