class AddWorldProgressToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :world_level, :integer, null: false, default: 1
    add_column :users, :world_xp_total, :bigint, null: false, default: 0
    add_column :users, :world_xp_bank, :bigint, null: false, default: 0
    add_column :users, :world_boss_kills, :integer, null: false, default: 0
  end
end
