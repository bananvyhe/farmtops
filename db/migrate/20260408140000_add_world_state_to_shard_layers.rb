class AddWorldStateToShardLayers < ActiveRecord::Migration[8.0]
  def change
    add_column :shard_layers, :world_state, :jsonb, null: false, default: {}
    add_column :shard_layers, :world_state_version, :integer, null: false, default: 0
    add_column :shard_layers, :world_state_simulated_at, :datetime
  end
end
