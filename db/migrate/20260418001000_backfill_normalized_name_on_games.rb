class BackfillNormalizedNameOnGames < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL.squish
      UPDATE games
      SET normalized_name = LOWER(TRIM(name))
      WHERE normalized_name IS NULL OR normalized_name = ''
    SQL
  end

  def down
    # No-op: the values can be regenerated from game names.
  end
end
