module Shards
  class WorldStateBuilder
    MAP_WIDTH = 28
    MAP_HEIGHT = 16
    MIN_BOSS_PARTICIPANTS = 2

    def initialize(shard:, current_user: nil, layer: nil)
      @shard = shard
      @current_user = current_user
      @layer = layer || resolved_layer
    end

    def call
      {
        shard: shard_payload,
        layers: layer_payloads,
        active_layer_id: @layer&.id,
        world: world_payload
      }
    end

    private

    def resolved_layer
      if @current_user.present?
        membership = @shard.layer_memberships.find_by(user_id: @current_user.id)
        return membership.shard_layer if membership
      end

      @shard.layers.order(:layer_index).first || @shard.default_layer
    end

    def shard_payload
      {
        id: @shard.id,
        game_id: @shard.game_id,
        game_name: @shard.game.name,
        name: @shard.name,
        world_seed: @shard.world_seed,
        status: @shard.status,
        layers_count: @shard.layers.size,
        created_at: @shard.created_at,
        updated_at: @shard.updated_at
      }
    end

    def layer_payloads
      @shard.layers.includes(memberships: :user).order(:layer_index).map do |layer|
        {
          id: layer.id,
          layer_index: layer.layer_index,
          status: layer.status,
          capacity: layer.capacity,
          occupancy: layer.occupancy,
          available_capacity: layer.available_capacity,
          members: layer.memberships.includes(:user).order(:joined_at).map do |membership|
            {
              id: membership.user_id,
              nickname: membership.user.nickname,
              joined_at: membership.joined_at,
              last_seen_at: membership.last_seen_at,
              owner: membership.user_id == @shard.user_id
            }
          end
        }
      end
    end

    def world_payload
      layer = @layer || @shard.default_layer
      seed = seed_value(layer)
      rng = Random.new(seed)
      members = layer.memberships.includes(:user).order(:joined_at).to_a
      occupancy = [members.size, 1].max
      campaign_started_at = layer.campaign_started_at || layer.created_at
      elapsed_seconds = [Time.current - campaign_started_at, 0].max
      elapsed_hours = (elapsed_seconds / 3600.0)
      target_players = [layer.campaign_target_players || occupancy, MIN_BOSS_PARTICIPANTS].max
      required_hours = [10.0 / target_players, 1.0].max
      group_progress = [[(elapsed_hours / required_hours) * 100.0, 100.0].min.round, 0].max
      boss_ready = occupancy >= MIN_BOSS_PARTICIPANTS && group_progress >= 100
      boss_hp = 4_000 + occupancy * 1_200 + layer.layer_index * 500
      inventory = inventory_payload(elapsed_hours, occupancy, members)
      resources = resource_payloads(rng)

      {
        tick: Time.current.to_i / 2,
        seed: "#{@shard.world_seed}:#{layer.layer_index}",
        map: map_payload(rng),
        players: player_payloads(members, resources, group_progress, inventory, rng, elapsed_seconds),
        mobs: mob_payloads(rng, occupancy, group_progress, elapsed_seconds),
        resources: resources,
        drops: drop_payloads(rng, occupancy, group_progress, elapsed_seconds),
        inventory: inventory,
        boss: {
          id: "boss-#{layer.id}",
          name: boss_name(seed),
          x: MAP_WIDTH / 2,
          y: MAP_HEIGHT / 2,
          hp: boss_hp,
          max_hp: boss_hp,
          progress: group_progress,
          required_hours: required_hours.round(2),
          required_participants: MIN_BOSS_PARTICIPANTS,
          ready: boss_ready,
          reward_xp: inventory[:pending_xp]
        },
        progress: {
          layer_index: layer.layer_index,
          occupancy: members.size,
          capacity: layer.capacity,
          energy_flow: 40 + members.size * 7,
          elapsed_hours: elapsed_hours.round(2),
          required_hours: required_hours.round(2),
          boss_unlock_progress: group_progress,
          session_progress: group_progress,
          group_goal: 100,
          group_progress: group_progress,
          boss_unlock_minutes: (required_hours * 60).round
        }
      }
    end

    def map_payload(rng)
      tiles = Array.new(MAP_HEIGHT) do |y|
        Array.new(MAP_WIDTH) do |x|
          value = (x * 31 + y * 17 + rng.rand(1000)) % 100
          case value
          when 0..7 then "water"
          when 8..17 then "stone"
          when 18..34 then "dirt"
          else "grass"
          end
        end
      end

      center_x = MAP_WIDTH / 2
      center_y = MAP_HEIGHT / 2
      tiles[center_y][center_x] = "boss"
      {
        width: MAP_WIDTH,
        height: MAP_HEIGHT,
        tiles:
      }
    end

    def player_payloads(members, resources, progress_pct, inventory, rng, elapsed_seconds)
      spawn_points = [
        [1, 1],
        [MAP_WIDTH - 2, 1],
        [1, MAP_HEIGHT - 2],
        [MAP_WIDTH - 2, MAP_HEIGHT - 2],
        [MAP_WIDTH / 2, 1],
        [1, MAP_HEIGHT / 2],
        [MAP_WIDTH - 2, MAP_HEIGHT / 2],
        [MAP_WIDTH / 2, MAP_HEIGHT - 2]
      ]

      members.each_with_index.map do |membership, index|
        base_x, base_y = spawn_points[index % spawn_points.length]
        resource_target = resources[index % resources.size]
        route_cycle_seconds = 40 + index * 7
        route_offset_seconds = index * 11 + membership.user_id % 9
        route_phase = ((elapsed_seconds + route_offset_seconds) % route_cycle_seconds) / route_cycle_seconds.to_f
        route_segments = [
          { x: base_x, y: base_y },
          { x: resource_target[:x], y: resource_target[:y] },
          { x: MAP_WIDTH / 2, y: MAP_HEIGHT / 2 },
          { x: base_x, y: base_y }
        ]
        segment_count = route_segments.length - 1
        segment_float = route_phase * segment_count
        segment_index = segment_float.floor
        local_phase = segment_float - segment_index
        from = route_segments[segment_index]
        to = route_segments[segment_index + 1]
        activity = case segment_index
                   when 0 then "gather"
                   when 1 then "fight"
                   when 2 then "return"
                   else "gather"
                   end
        {
          id: membership.user_id,
          nickname: membership.user.nickname,
          x: lerp(from[:x], to[:x], local_phase).round(2),
          y: lerp(from[:y], to[:y], local_phase).round(2),
          hp: 100,
          max_hp: 100,
          energy: 100,
          level: membership.user.world_level,
          xp: membership.user.world_xp_total,
          world_xp_bank: membership.user.world_xp_bank,
          pending_xp: inventory[:pending_xp],
          loot: inventory[:loot],
          energy_income: inventory[:energy],
          healing_items: inventory[:healing],
          resource_target: resource_target[:kind],
          route_progress: (route_phase * 100).round(2),
          route_cycle_seconds: route_cycle_seconds,
          route_offset_seconds: route_offset_seconds,
          bot: true,
          role: index.zero? ? "leader" : "support",
          action: activity,
          path: route_segments
        }
      end
    end

    def mob_payloads(rng, players_count, progress_pct, elapsed_seconds)
      total = 6 + players_count * 2
      Array.new(total) do |index|
        {
          id: "mob-#{index}",
          name: ["Slime", "Scout", "Watcher", "Guard"].sample(random: rng),
          x: rng.rand(2..MAP_WIDTH - 3),
          y: rng.rand(2..MAP_HEIGHT - 3),
          hp: 45 + players_count * 10,
          max_hp: 45 + players_count * 10,
          level: 1 + index / 3,
          asset_key: ["slime", "beast", "hunter"].sample(random: rng),
          hostile: true,
          pressure: progress_pct,
          state: elapsed_seconds > 0 ? "patrol" : "spawn"
        }
      end
    end

    def resource_payloads(rng)
      kinds = [
        { kind: "energy_crystal", asset_key: "resource_energy" },
        { kind: "heal_herb", asset_key: "resource_heal" },
        { kind: "shard_ore", asset_key: "resource_shard" }
      ]

      Array.new(7) do |index|
        kind = kinds[index % kinds.length]
        {
          id: "resource-#{index}",
          kind: kind[:kind],
          asset_key: kind[:asset_key],
          x: rng.rand(1..MAP_WIDTH - 2),
          y: rng.rand(1..MAP_HEIGHT - 2),
          amount: 10 + rng.rand(30),
          respawns_in: 20 + rng.rand(40)
        }
      end
    end

    def drop_payloads(rng, players_count, progress_pct, elapsed_seconds)
      total = [2 + players_count, 10].min
      Array.new(total) do |index|
        kind = index.even? ? "loot_coin" : "loot_bundle"
        {
          id: "drop-#{index}",
          kind: kind,
          x: rng.rand(2..MAP_WIDTH - 3),
          y: rng.rand(2..MAP_HEIGHT - 3),
          amount: 1 + rng.rand(4),
          rarity: progress_pct >= 50 ? "rare" : "common",
          pulse_phase: ((elapsed_seconds / 4.0) + index).round(2)
        }
      end
    end

    def inventory_payload(elapsed_hours, occupancy, members)
      farm_points = (elapsed_hours * occupancy * 12.0).floor
      banked_xp = members.sum { |membership| membership.user.world_xp_bank }
      {
        energy: farm_points * 2,
        healing: [farm_points / 2, 0].max,
        shard_ore: [farm_points / 3, 0].max,
        loot: [farm_points / 4, 0].max,
        pending_xp: (elapsed_hours * occupancy * 300).floor,
        applied_xp: members.sum { |membership| membership.user.world_xp_total },
        banked_xp: banked_xp
      }
    end

    def boss_name(seed)
      suffix = seed.to_s.last(4).upcase
      "Shard Warden #{suffix}"
    end

    def seed_value(layer)
      Digest::SHA256.hexdigest("#{@shard.world_seed}:#{layer.layer_index}").slice(0, 16).to_i(16)
    end

    def lerp(from, to, progress)
      from + (to - from) * progress
    end
  end
end
