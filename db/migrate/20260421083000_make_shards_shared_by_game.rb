class MakeShardsSharedByGame < ActiveRecord::Migration[8.0]
  def up
    deduplicate_shards_per_game!
    collapse_all_shards_to_single_layer!

    remove_index :shards, name: "index_shards_on_user_id_and_game_id", if_exists: true
    remove_index :shards, name: "index_shards_on_game_id", if_exists: true
    add_index :shards, :game_id, unique: true, name: "index_shards_on_game_id_unique"
  end

  def down
    remove_index :shards, name: "index_shards_on_game_id_unique", if_exists: true
    add_index :shards, :game_id, name: "index_shards_on_game_id", if_not_exists: true
    add_index :shards, [:user_id, :game_id], unique: true, name: "index_shards_on_user_id_and_game_id", if_not_exists: true
  end

  private

  def deduplicate_shards_per_game!
    duplicates = select_values(<<~SQL.squish)
      SELECT game_id
      FROM shards
      GROUP BY game_id
      HAVING COUNT(*) > 1
    SQL

    duplicates.each do |game_id|
      shard_ids = select_values(<<~SQL.squish)
        SELECT id
        FROM shards
        WHERE game_id = #{quote(game_id)}
        ORDER BY created_at ASC, id ASC
      SQL
      next if shard_ids.size <= 1

      canonical_shard_id = shard_ids.shift
      canonical_layer_id = ensure_default_layer_for_shard(canonical_shard_id)

      shard_ids.each do |duplicate_shard_id|
        execute <<~SQL.squish
          INSERT INTO shard_layer_memberships (
            shard_id, shard_layer_id, user_id, joined_at, last_seen_at, created_at, updated_at
          )
          SELECT
            #{canonical_shard_id},
            #{canonical_layer_id},
            user_id,
            joined_at,
            last_seen_at,
            NOW(),
            NOW()
          FROM shard_layer_memberships
          WHERE shard_id = #{duplicate_shard_id}
          ON CONFLICT (shard_id, user_id)
          DO UPDATE SET
            shard_layer_id = EXCLUDED.shard_layer_id,
            joined_at = LEAST(shard_layer_memberships.joined_at, EXCLUDED.joined_at),
            last_seen_at = GREATEST(shard_layer_memberships.last_seen_at, EXCLUDED.last_seen_at),
            updated_at = NOW()
        SQL

        execute "DELETE FROM shard_layer_memberships WHERE shard_id = #{duplicate_shard_id}"
        execute "DELETE FROM shard_layers WHERE shard_id = #{duplicate_shard_id}"
        execute "DELETE FROM shards WHERE id = #{duplicate_shard_id}"
      end
    end
  end

  def collapse_all_shards_to_single_layer!
    shard_ids = select_values("SELECT id FROM shards")

    shard_ids.each do |shard_id|
      default_layer_id = ensure_default_layer_for_shard(shard_id)
      execute <<~SQL.squish
        UPDATE shard_layer_memberships
        SET shard_layer_id = #{default_layer_id}, updated_at = NOW()
        WHERE shard_id = #{shard_id}
      SQL
      execute "DELETE FROM shard_layers WHERE shard_id = #{shard_id} AND id <> #{default_layer_id}"
    end
  end

  def ensure_default_layer_for_shard(shard_id)
    existing_layer_id = select_value(<<~SQL.squish)
      SELECT id
      FROM shard_layers
      WHERE shard_id = #{shard_id}
      ORDER BY layer_index ASC, id ASC
      LIMIT 1
    SQL
    return existing_layer_id if existing_layer_id.present?

    execute <<~SQL.squish
      INSERT INTO shard_layers (
        shard_id, layer_index, status, created_at, updated_at,
        campaign_started_at, campaign_target_players, world_state, world_state_version
      )
      VALUES (
        #{shard_id}, 1, 0, NOW(), NOW(),
        NULL, 2, '{}'::jsonb, 0
      )
    SQL

    select_value(<<~SQL.squish)
      SELECT id
      FROM shard_layers
      WHERE shard_id = #{shard_id}
      ORDER BY layer_index ASC, id ASC
      LIMIT 1
    SQL
  end
end
