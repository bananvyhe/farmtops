module Shards
  class WorldStateBuilder
    MAP_WIDTH = 36
    MAP_HEIGHT = 20
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
        world: world_payload,
        chat_messages: chat_messages_payload
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
      current_slot_utc = current_week_slot_utc
      @shard.layers.includes(memberships: :user).order(:layer_index).map do |layer|
        memberships = layer.memberships.includes(:user).order(:joined_at).to_a
        active_members_count = memberships.count { |membership| membership.user.prime_slots_utc.include?(current_slot_utc) }
        {
          id: layer.id,
          layer_index: layer.layer_index,
          status: layer.status,
          capacity: layer.capacity,
          occupancy: layer.occupancy,
          active_occupancy: active_members_count,
          available_capacity: layer.available_capacity,
          members: memberships.map do |membership|
            {
              id: membership.user_id,
              nickname: membership.user.nickname,
              joined_at: membership.joined_at,
              last_seen_at: membership.last_seen_at,
              owner: membership.user_id == @shard.user_id,
              active_now: membership.user.prime_slots_utc.include?(current_slot_utc)
            }
          end
        }
      end
    end

    def world_payload
      Shards::WorldSimulator.new(shard: @shard, layer: @layer || @shard.default_layer).call
    end

    def chat_messages_payload
      @shard.chat_messages.includes(:user).recent_first.limit(50).reverse.map do |message|
        Shards::RealtimeBroadcaster.chat_message_payload(message)
      end
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
        route_cycle_seconds = 180 + index * 26 + (membership.user_id % 5) * 5
        route_offset_seconds = index * 17 + membership.user_id % 13
        route_speed_factor = [0.78 + index * 0.045 + (membership.user_id % 4) * 0.03, 1.16].min
        resource_stop_phase = 0.2 + (index % 3) * 0.08
        resource_stop_window = 0.08 + (index % 2) * 0.03
        route_phase = ((elapsed_seconds + route_offset_seconds) % route_cycle_seconds) / route_cycle_seconds.to_f
        route_path = route_path_points(base_x, base_y, resource_target, index, rng)
        segment_count = route_path.length - 1
        segment_float = route_phase * segment_count
        segment_index = segment_float.floor
        local_phase = segment_float - segment_index
        from = route_path[segment_index]
        to = route_path[segment_index + 1]
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
          resource_target_x: resource_target[:x],
          resource_target_y: resource_target[:y],
          route_progress: (route_phase * 100).round(2),
          route_cycle_seconds: route_cycle_seconds,
          route_offset_seconds: route_offset_seconds,
          route_speed_factor: route_speed_factor.round(2),
          resource_stop_phase: resource_stop_phase.round(2),
          resource_stop_window: resource_stop_window.round(2),
          active_now: true,
          role: index.zero? ? "leader" : "support",
          action: activity,
          path: route_path
        }
      end
    end

    def route_path_points(base_x, base_y, resource_target, index, rng)
      center_x = MAP_WIDTH / 2.0
      center_y = MAP_HEIGHT / 2.0
      boss_x = center_x
      boss_y = center_y
      phase_points = [0.0, 0.12, 0.26, 0.45, 0.62, 0.82, 1.0]

      phase_points.map.with_index do |phase, waypoint_index|
        anchor_x =
          case waypoint_index
          when 0 then base_x
          when 1 then lerp(base_x, resource_target[:x], 0.35)
          when 2 then lerp(resource_target[:x], boss_x, 0.25)
          when 3 then lerp(base_x, boss_x, 0.55)
          when 4 then lerp(resource_target[:x], boss_x, 0.72)
          when 5 then lerp(base_x, boss_x, 0.88)
          else boss_x
          end

        anchor_y =
          case waypoint_index
          when 0 then base_y
          when 1 then lerp(base_y, resource_target[:y], 0.35)
          when 2 then lerp(resource_target[:y], boss_y, 0.25)
          when 3 then lerp(base_y, boss_y, 0.55)
          when 4 then lerp(resource_target[:y], boss_y, 0.72)
          when 5 then lerp(base_y, boss_y, 0.88)
          else boss_y
          end

        jitter_scale = [2.1 - index * 0.12, 0.75].max
        wave_x = Math.sin((phase * Math::PI * 2) + index) * jitter_scale
        wave_y = Math.cos((phase * Math::PI * 2) + index / 2.0) * (jitter_scale * 0.55)
        point = {
          x: anchor_x + wave_x + rng.rand(-0.65..0.65),
          y: anchor_y + wave_y + rng.rand(-0.65..0.65)
        }
        {
          x: [[point[:x], 1.0].max, MAP_WIDTH - 2.0].min.round(2),
          y: [[point[:y], 1.0].max, MAP_HEIGHT - 2.0].min.round(2)
        }
      end
    end

    def mob_payloads(rng, players_count, progress_pct, elapsed_seconds)
      total = 10 + players_count * 3
      Array.new(total) do |index|
        anchor_x = rng.rand(3..MAP_WIDTH - 4)
        anchor_y = rng.rand(3..MAP_HEIGHT - 4)
        {
          id: "mob-#{index}",
          name: ["Slime", "Scout", "Watcher", "Guard"].sample(random: rng),
          x: anchor_x,
          y: anchor_y,
          anchor_x: anchor_x,
          anchor_y: anchor_y,
          patrol_radius: 0.4 + rng.rand * 0.9,
          patrol_speed: 0.08 + rng.rand * 0.07,
          patrol_phase: rng.rand * Math::PI * 2,
          hp: 45 + players_count * 10,
          max_hp: 45 + players_count * 10,
          level: 1 + index / 3,
          asset_key: ["slime", "beast", "hunter"].sample(random: rng),
          hostile: true,
          pressure: progress_pct,
          alive: true,
          state: elapsed_seconds > 0 ? "patrol" : "spawn",
          respawn_in_seconds: 0
        }
      end
    end

    def resource_payloads(rng)
      kinds = [
        { kind: "energy_crystal", asset_key: "resource_energy" },
        { kind: "shard_ore", asset_key: "resource_shard" }
      ]

      Array.new(24) do |index|
        kind = kinds[index % kinds.length]
        {
          id: "resource-#{index}",
          kind: kind[:kind],
          asset_key: kind[:asset_key],
          x: rng.rand(1..MAP_WIDTH - 2),
          y: rng.rand(1..MAP_HEIGHT - 2),
          amount: 12 + rng.rand(36),
          respawns_in: 20 + rng.rand(40),
          pulse_phase: (index * 0.9 + rng.rand).round(2),
          pulse_speed: (0.95 + rng.rand * 0.55).round(2)
        }
      end
    end

    def drop_payloads(rng, players_count, progress_pct, elapsed_seconds)
      return [] if players_count.zero?

      total = [3 + players_count, 12].min
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

    def farm_log_payload(active_members, elapsed_seconds, current_week_slot_utc)
      active_members.each_with_index.flat_map do |left, index|
        active_members[(index + 1)..].to_a.map do |right|
          overlap = left.user.prime_slot_overlap(right.user)
          next if overlap.empty?

          shared_hours = overlap.size
          together_minutes = [elapsed_seconds / 60.0, shared_hours * 60.0].min.round
          {
            players: [left.user.nickname, right.user.nickname],
            shared_prime_hours: shared_hours,
            together_minutes: together_minutes,
            current_week_slot_utc: current_week_slot_utc,
            slots: overlap
          }
        end
      end.compact
    end

    def boss_name(seed)
      suffix = seed.to_s.last(4).upcase
      "Shard Warden #{suffix}"
    end

    def seed_value(layer)
      Digest::SHA256.hexdigest("#{@shard.world_seed}:#{layer.layer_index}").slice(0, 16).to_i(16)
    end

    def current_week_slot_utc
      ((Time.current.utc.wday + 6) % 7) * 24 + Time.current.utc.hour
    end

    def lerp(from, to, progress)
      from + (to - from) * progress
    end
  end
end
