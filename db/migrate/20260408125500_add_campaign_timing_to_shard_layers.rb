class AddCampaignTimingToShardLayers < ActiveRecord::Migration[8.0]
  def change
    add_column :shard_layers, :campaign_started_at, :datetime
    add_column :shard_layers, :campaign_target_players, :integer, null: false, default: 2
  end
end
