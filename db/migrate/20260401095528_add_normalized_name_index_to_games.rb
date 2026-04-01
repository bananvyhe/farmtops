class AddNormalizedNameIndexToGames < ActiveRecord::Migration[8.0]
  def change
    add_index :games, :normalized_name
  end
end
