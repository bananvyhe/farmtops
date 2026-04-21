module Shards
  class WorldSimulator
    MAP_WIDTH = 36
    MAP_HEIGHT = 20
    MIN_BOSS_PARTICIPANTS = 2
    ENTITY_RESPAWN_SECONDS = 60

    def initialize(shard:, layer: nil)
      @shard = shard
      @layer = layer || shard.default_layer
    end

    def call
      @layer.with_lock do
        state = ensure_state!
        now = Time.current
        current_slot_utc = current_week_slot_utc(now)
        members = @layer.memberships.includes(:user).order(:joined_at).to_a
        active_members = members.select { |membership| membership.user.prime_slots_utc.include?(current_slot_utc) }

        tick_state!(state, active_members, now, current_slot_utc)
        persist_state!(state, now)
        build_snapshot(state, active_members, members, now, current_slot_utc)
      end
    end

    private

    def ensure_state!
      persisted_state = @layer.world_state
      if persisted_state.present?
        normalized_state = normalize_state(persisted_state.deep_dup)
        if normalized_state != persisted_state
          @layer.update_columns(
            world_state: normalized_state,
            world_state_version: @layer.world_state_version.to_i + 1,
            world_state_simulated_at: Time.current
          )
        end
        return normalized_state.deep_dup
      end

      initial_state = initial_world_state
      @layer.update_columns(
        world_state: initial_state,
        world_state_version: 1,
        world_state_simulated_at: Time.current
      )
      initial_state.deep_dup
    end

    def persist_state!(state, now)
      @layer.update_columns(
        world_state: state,
        world_state_version: @layer.world_state_version.to_i + 1,
        world_state_simulated_at: now
      )
    end

    def normalize_state(state)
      normalized_state = state.deep_dup
      template_resources = resource_payloads(Random.new(seed_value))
      existing_resources = Array(normalized_state["resources"]).each_with_object({}) do |resource, memo|
        memo[resource["id"].to_s] = resource
      end

      normalized_state["resources"] = template_resources.map do |template|
        existing = existing_resources[template["id"].to_s]
        next template if existing.blank?

        template.merge(
          "amount" => existing["amount"] || template["amount"],
          "base_amount" => existing["base_amount"] || template["base_amount"],
          "respawns_at" => existing["respawns_at"],
          "alive" => existing.key?("alive") ? existing["alive"] : template["alive"],
          "last_collected_at" => existing["last_collected_at"]
        )
      end

      normalized_state["players"] = Array(normalized_state["players"]).map do |player|
        player = player.deep_dup
        player["speed_factor"] = [player["speed_factor"].to_f, 0.34].max.round(3)
        player
      end

      normalized_state
    end

    def initial_world_state
      rng = Random.new(seed_value)

      {
        "seed" => "#{@shard.world_seed}:#{@layer.layer_index}",
        "map" => map_payload(rng),
        "mobs" => mob_payloads(rng),
        "resources" => resource_payloads(rng),
        "drops" => [],
        "players" => [],
        "inventory" => {
          "energy" => 0,
          "healing" => 0,
          "shard_ore" => 0,
          "loot" => 0,
          "pending_xp" => 0,
          "applied_xp" => 0,
          "banked_xp" => 0
        },
        "farm_log" => [],
        "boss" => {
          "id" => "boss-#{@layer.id}",
          "name" => boss_name,
          "x" => MAP_WIDTH / 2,
          "y" => MAP_HEIGHT / 2,
          "hp" => boss_hp_base,
          "max_hp" => boss_hp_base,
          "progress" => 0,
          "required_hours" => 1.0,
          "required_participants" => MIN_BOSS_PARTICIPANTS,
          "ready" => false,
          "reward_xp" => 0
        }
      }
    end

    def tick_state!(state, active_members, now, current_slot_utc)
      state["players"] = tick_player_states(state, active_members, now)
      @player_positions = build_player_positions(state)

      state["mobs"] = Array(state["mobs"]).map do |mob|
        tick_mob(mob, active_members, state, now)
      end

      state["resources"] = Array(state["resources"]).map do |resource|
        tick_resource(resource, active_members, state, now)
      end

      state["drops"] = Array(state["drops"]).select do |drop|
        respawns_at = parse_time(drop["expires_at"])
        respawns_at.blank? || respawns_at > now
      end

      state["farm_log"] = Array(state["farm_log"]).last(40)
      update_inventory_bank!(state, active_members)
      update_boss!(state, active_members, now, current_slot_utc)
    end

    def tick_player_states(state, active_members, now)
      existing_players = Array(state["players"]).each_with_object({}) do |player, memo|
        memo[player["user_id"].to_s] = player.deep_dup
      end
      alive_resources = Array(state["resources"]).select { |resource| resource["alive"] != false }
      alive_mobs = Array(state["mobs"]).select { |mob| mob["alive"] != false }
      boss = state["boss"] || {}
      boss_ready = boss["ready"] == true

      claimed_resource_ids = {}
      claimed_mob_ids = {}

      active_members.each_with_index.map do |membership, index|
        runtime = existing_players[membership.user_id.to_s] || default_player_runtime(membership, index)
        target = select_player_target(
          runtime:,
          alive_resources:,
          alive_mobs:,
          boss:,
          boss_ready:,
          claimed_resource_ids:,
          claimed_mob_ids:,
          index:
        )

        moved = advance_player_runtime(runtime, target, index, now)
        if moved["target_kind"] == "resource" && moved["target_id"].present?
          claimed_resource_ids[moved["target_id"].to_s] = true
        elsif moved["target_kind"] == "mob" && moved["target_id"].present?
          claimed_mob_ids[moved["target_id"].to_s] = true
        end

        moved
      end
    end

    def tick_mob(mob, active_members, state, now)
      mob = mob.deep_dup
      respawns_at = parse_time(mob["respawns_at"])
      if mob["alive"] == false && respawns_at.present? && respawns_at <= now
        mob["alive"] = true
        mob["hp"] = mob["max_hp"]
        mob["respawns_at"] = nil
        mob["last_defeated_at"] = nil
      end

      return mob unless mob["alive"]

      mob_position = mob_position_at(mob, now)
      killer = active_members.find { |membership| distance(player_position_for_membership(membership), mob_position[:x], mob_position[:y]) < 0.8 }

      return mob.merge("x" => mob_position[:x].round(2), "y" => mob_position[:y].round(2)) unless killer

      drop = {
        "id" => "drop-mob-#{mob["id"]}-#{now.to_i}",
        "kind" => "loot_bundle",
        "x" => mob_position[:x].round(2),
        "y" => mob_position[:y].round(2),
        "amount" => 1,
        "rarity" => "common",
        "expires_at" => (now + 20.seconds).iso8601,
        "source" => "mob"
      }
      state["drops"] << drop
      state["inventory"]["loot"] = state["inventory"]["loot"].to_i + 1
      state["inventory"]["pending_xp"] = state["inventory"]["pending_xp"].to_i + 12
      bank_session_xp!(active_members, 12)
      state["farm_log"] << farm_log_entry("mob", killer.user.nickname, mob["name"], now)
      player_runtime_for_user(state, killer.user_id)&.update("next_mode" => "resource")

      mob.merge(
        "x" => mob_position[:x].round(2),
        "y" => mob_position[:y].round(2),
        "alive" => false,
        "hp" => 0,
        "respawns_at" => (now + ENTITY_RESPAWN_SECONDS.seconds).iso8601,
        "last_defeated_at" => now.iso8601
      )
    end

    def tick_resource(resource, active_members, state, now)
      resource = resource.deep_dup
      respawns_at = parse_time(resource["respawns_at"])
      if resource["alive"] == false && respawns_at.present? && respawns_at <= now
        resource["alive"] = true
        resource["amount"] = resource["base_amount"]
        resource["respawns_at"] = nil
        resource["last_collected_at"] = nil
      end

      return resource unless resource["alive"]

      resource_position = { x: number(resource["x"]), y: number(resource["y"]) }
      collector = active_members.find { |membership| distance(player_position_for_membership(membership), resource_position[:x], resource_position[:y]) < 0.7 }

      return resource unless collector

      gain = case resource["kind"]
             when "energy_crystal" then { "energy" => 6, "healing" => 0, "shard_ore" => 0, "loot" => 1, "xp" => 5 }
             else { "energy" => 0, "healing" => 0, "shard_ore" => 4, "loot" => 1, "xp" => 6 }
             end
      xp_gain = gain.delete("xp")
      gain.each { |key, value| state["inventory"][key] = state["inventory"][key].to_i + value }
      state["inventory"]["pending_xp"] = state["inventory"]["pending_xp"].to_i + xp_gain
      bank_session_xp!(active_members, xp_gain)
      state["farm_log"] << farm_log_entry("resource", collector.user.nickname, resource["kind"], now)
      player_runtime_for_user(state, collector.user_id)&.update("next_mode" => "mob")

      resource.merge(
        "alive" => false,
        "amount" => 0,
        "respawns_at" => (now + ENTITY_RESPAWN_SECONDS.seconds).iso8601,
        "last_collected_at" => now.iso8601
      )
    end

    def update_inventory_bank!(state, active_members)
      banked_xp = active_members.sum { |membership| membership.user.world_xp_bank }
      state["inventory"]["banked_xp"] = banked_xp
      state["inventory"]["applied_xp"] = active_members.sum { |membership| membership.user.world_xp_total }
    end

    def update_boss!(state, active_members, now, current_slot_utc)
      active_count = active_members.size
      campaign_started_at = @layer.campaign_started_at || @layer.created_at
      elapsed_seconds = [now - campaign_started_at, 0].max
      elapsed_hours = active_count.positive? ? (elapsed_seconds / 3600.0) : 0.0
      target_players = [@layer.campaign_target_players || active_count, MIN_BOSS_PARTICIPANTS].max
      required_hours = active_count.positive? ? [10.0 / target_players, 1.0].max : 0.0
      progress = active_count.positive? ? [[(elapsed_hours / required_hours) * 100.0, 100.0].min.round, 0].max : 0
      progress_value = progress
      boss = state["boss"]
      boss["progress"] = progress_value
      boss["required_hours"] = required_hours.round(2)
      boss["required_participants"] = MIN_BOSS_PARTICIPANTS
      boss["ready"] = active_count >= MIN_BOSS_PARTICIPANTS && progress_value >= 100
      boss["reward_xp"] = state["inventory"]["pending_xp"]
      boss["hp"] = boss_hp_base + active_count * 1_200
      boss["max_hp"] = boss["hp"]

      if boss["ready"]
        resolve_boss_reward!(state, active_members, now)
        boss["ready"] = false
        boss["reward_xp"] = 0
        boss["progress"] = 0
        @layer.update_columns(campaign_started_at: now)
        progress_value = 0
        elapsed_hours = 0.0
      end

      state["progress"] = {
        "layer_index" => @layer.layer_index,
        "occupancy" => active_count,
        "members_count" => @layer.memberships.count,
        "capacity" => @layer.capacity,
        "energy_flow" => active_count.positive? ? 40 + active_count * 7 : 0,
        "elapsed_hours" => elapsed_hours.round(2),
        "required_hours" => required_hours.round(2),
        "boss_unlock_progress" => progress_value,
        "session_progress" => progress_value,
        "group_goal" => 100,
        "group_progress" => progress_value,
        "boss_unlock_minutes" => (required_hours * 60).round,
        "active_players_count" => active_count,
        "current_week_slot_utc" => current_slot_utc
      }

      state["mode"] = active_count.positive? ? "active" : "idle"
      state["current_week_slot_utc"] = current_slot_utc
      state["active_players_count"] = active_count
      state["active_players_required"] = MIN_BOSS_PARTICIPANTS
    end

    def build_snapshot(state, active_members, members, now, current_slot_utc)
      {
        tick: now.to_i / 2,
        seed: "#{@shard.world_seed}:#{@layer.layer_index}",
        map: state["map"],
        players: player_payloads(active_members, state, now),
        mobs: Array(state["mobs"]),
        resources: Array(state["resources"]),
        drops: Array(state["drops"]),
        inventory: state["inventory"].merge(
          "pending_xp" => state["inventory"]["pending_xp"].to_i,
          "banked_xp" => state["inventory"]["banked_xp"].to_i
        ),
        farm_log: Array(state["farm_log"]).last(20),
        current_week_slot_utc: current_slot_utc,
        active_players_count: active_members.size,
        active_players_required: MIN_BOSS_PARTICIPANTS,
        mode: active_members.any? ? "active" : "idle",
        boss: state["boss"],
        progress: state["progress"] || {
          "layer_index" => @layer.layer_index,
          "occupancy" => active_members.size,
          "members_count" => members.size,
          "capacity" => @layer.capacity,
          "energy_flow" => active_members.any? ? 40 + active_members.size * 7 : 0,
          "elapsed_hours" => 0,
          "required_hours" => 0,
          "boss_unlock_progress" => 0,
          "session_progress" => 0,
          "group_goal" => 100,
          "group_progress" => 0,
          "boss_unlock_minutes" => 0,
          "active_players_count" => active_members.size,
          "current_week_slot_utc" => current_slot_utc
        }
      }
    end

    def player_payloads(active_members, state, now)
      player_states = Array(state["players"]).each_with_object({}) do |player, memo|
        memo[player["user_id"].to_s] = player
      end

      active_members.each_with_index.map do |membership, index|
        runtime = player_states[membership.user_id.to_s] || default_player_runtime(membership, index)
        {
          id: membership.user_id,
          nickname: membership.user.nickname,
          x: number(runtime["x"]).round(2),
          y: number(runtime["y"]).round(2),
          hp: 100,
          max_hp: 100,
          energy: 100,
          level: membership.user.world_level,
          xp: membership.user.world_xp_total,
          world_xp_bank: membership.user.world_xp_bank,
          resource_target: runtime["target_kind"] == "resource" ? runtime["target_label"] : nil,
          resource_target_x: runtime["target_kind"] == "resource" ? runtime["target_x"] : nil,
          resource_target_y: runtime["target_kind"] == "resource" ? runtime["target_y"] : nil,
          mob_target: runtime["target_kind"] == "mob" ? runtime["target_label"] : nil,
          mob_target_x: runtime["target_kind"] == "mob" ? runtime["target_x"] : nil,
          mob_target_y: runtime["target_kind"] == "mob" ? runtime["target_y"] : nil,
          target_kind: runtime["target_kind"],
          target_label: runtime["target_label"],
          target_x: runtime["target_x"],
          target_y: runtime["target_y"],
          target_distance: runtime["target_distance"],
          route_progress: runtime["route_progress"],
          route_cycle_seconds: runtime["speed_seconds"],
          route_offset_seconds: runtime["target_changed_at"],
          route_speed_factor: runtime["speed_factor"],
          resource_stop_phase: 0.22,
          resource_stop_window: 0.05,
          mob_stop_phase: 0.56,
          mob_stop_window: 0.05,
          active_now: true,
          role: index.zero? ? "leader" : "support",
          action: runtime["action"],
          path: []
        }
      end
    end

    def default_player_runtime(membership, index)
      spawn = player_spawn_points[index % player_spawn_points.length]
      {
        "user_id" => membership.user_id,
        "nickname" => membership.user.nickname,
        "x" => spawn[0].to_f,
        "y" => spawn[1].to_f,
        "target_kind" => "resource",
        "target_id" => nil,
        "target_label" => nil,
        "target_x" => spawn[0].to_f,
        "target_y" => spawn[1].to_f,
        "target_distance" => 0.0,
        "target_changed_at" => 0,
        "speed_factor" => (0.34 + index * 0.02).round(3),
        "action" => "idle",
        "route_progress" => 0.0
      }
    end

    def select_player_target(runtime:, alive_resources:, alive_mobs:, boss:, boss_ready:, claimed_resource_ids:, claimed_mob_ids:, index:)
      current_kind = runtime["target_kind"].presence
      current_id = runtime["target_id"].to_s.presence

      if boss_ready && boss["x"].present? && boss["y"].present?
        return {
          "kind" => "boss",
          "id" => boss["id"],
          "label" => boss["name"],
          "x" => number(boss["x"]),
          "y" => number(boss["y"])
        }
      end

      if current_kind == "resource"
        existing_resource = alive_resources.find { |resource| resource["id"].to_s == current_id && !claimed_resource_ids[resource["id"].to_s] }
        return target_from_resource(existing_resource) if existing_resource
      elsif current_kind == "mob"
        existing_mob = alive_mobs.find { |mob| mob["id"].to_s == current_id && !claimed_mob_ids[mob["id"].to_s] }
        return target_from_mob(existing_mob) if existing_mob
      end

      preferred_kind = runtime["next_mode"].presence || current_kind.presence || "resource"
      current_point = { x: number(runtime["x"]), y: number(runtime["y"]) }

      if preferred_kind == "resource"
        resource = nearest_available_resource(alive_resources, current_point, claimed_resource_ids, index)
        return target_from_resource(resource) if resource

        mob = nearest_available_mob(alive_mobs, current_point, claimed_mob_ids, index)
        return target_from_mob(mob) if mob
      else
        mob = nearest_available_mob(alive_mobs, current_point, claimed_mob_ids, index)
        return target_from_mob(mob) if mob

        resource = nearest_available_resource(alive_resources, current_point, claimed_resource_ids, index)
        return target_from_resource(resource) if resource
      end

      {
        "kind" => "idle",
        "id" => nil,
        "label" => "idle",
        "x" => current_point[:x],
        "y" => current_point[:y]
      }
    end

    def nearest_available_resource(resources, current_point, claimed_ids, index)
      scored_targets(resources, current_point, claimed_ids, index).first
    end

    def nearest_available_mob(mobs, current_point, claimed_ids, index)
      scored_targets(mobs, current_point, claimed_ids, index).first
    end

    def scored_targets(entities, current_point, claimed_ids, index)
      entities
        .reject { |entity| claimed_ids[entity["id"].to_s] }
        .map do |entity|
          distance_to_entity = Math.hypot(number(entity["x"]) - current_point[:x], number(entity["y"]) - current_point[:y])
          jitter_seed = entity["id"].to_s.each_byte.sum + index * 17 + seed_value % 97
          jitter = (jitter_seed % 100) / 1000.0
          [distance_to_entity + jitter, entity]
        end
        .sort_by(&:first)
        .map(&:last)
    end

    def target_from_resource(resource)
      return nil unless resource.present?

      {
        "kind" => "resource",
        "id" => resource["id"],
        "label" => resource["kind"],
        "x" => number(resource["x"]),
        "y" => number(resource["y"])
      }
    end

    def target_from_mob(mob)
      return nil unless mob.present?

      {
        "kind" => "mob",
        "id" => mob["id"],
        "label" => mob["name"],
        "x" => number(mob["x"]),
        "y" => number(mob["y"])
      }
    end

    def advance_player_runtime(runtime, target, index, now)
      runtime = runtime.deep_dup
      previous_target_key = [runtime["target_kind"], runtime["target_id"].to_s].join(":")
      speed_factor = runtime["speed_factor"].to_f.nonzero? || (0.34 + index * 0.02)
      current_x = number(runtime["x"])
      current_y = number(runtime["y"])
      target_x = number(target["x"])
      target_y = number(target["y"])
      dx = target_x - current_x
      dy = target_y - current_y
      distance_to_target = Math.hypot(dx, dy)
      step_size = [0.18 + speed_factor * 0.75, 0.42].min
      arrive = distance_to_target <= step_size

      if arrive
        current_x = target_x
        current_y = target_y
      else
        progress = step_size / distance_to_target
        current_x = current_x + dx * progress
        current_y = current_y + dy * progress
        sway = Math.sin(now.to_f / 2_200 + index) * 0.02
        perpendicular_x = distance_to_target.zero? ? 0.0 : -dy / distance_to_target
        perpendicular_y = distance_to_target.zero? ? 0.0 : dx / distance_to_target
        current_x += perpendicular_x * sway
        current_y += perpendicular_y * sway
      end

      runtime["x"] = [[current_x, 1.0].max, MAP_WIDTH - 2.0].min.round(3)
      runtime["y"] = [[current_y, 1.0].max, MAP_HEIGHT - 2.0].min.round(3)
      runtime["target_kind"] = target["kind"]
      runtime["target_id"] = target["id"]
      runtime["target_label"] = target["label"]
      runtime["target_x"] = target_x.round(3)
      runtime["target_y"] = target_y.round(3)
      runtime["target_distance"] = distance_to_target.round(3)
      runtime["route_progress"] = arrive ? 100.0 : [[(1 - (distance_to_target / 8.0)) * 100.0, 0].max, 100.0].min.round(2)
      runtime["speed_factor"] = speed_factor.round(3)
      runtime["action"] =
        case target["kind"]
        when "resource" then "gather"
        when "mob" then "fight"
        when "boss" then "boss"
        else "idle"
        end
      current_target_key = [target["kind"], target["id"].to_s].join(":")
      runtime["target_changed_at"] = now.to_i if previous_target_key != current_target_key
      runtime
    end

    def player_runtime_for_user(state, user_id)
      Array(state["players"]).find { |player| player["user_id"].to_i == user_id.to_i }
    end

    def resources_for_player(state, index)
      resources = Array(state["resources"])
      resources[index % resources.length] || {
        "kind" => "shard_ore",
        "x" => MAP_WIDTH / 2,
        "y" => MAP_HEIGHT / 2
      }
    end

    def mobs_for_player(state, index)
      mobs = Array(state["mobs"]).select { |mob| mob["alive"] != false }
      mobs[index % mobs.length] || {
        "name" => "Watcher",
        "x" => MAP_WIDTH / 2,
        "y" => MAP_HEIGHT / 2
      }
    end

    def route_position_at_timestamp(path, cycle_seconds, route_offset_seconds, route_speed_factor, now, resource_target, mob_target, index)
      phase = ((((now.to_f) + route_offset_seconds) / cycle_seconds) * route_speed_factor) % 1.0
      raw_phase = phase
      phase = raw_phase < 0.5 ? raw_phase * 2 : (1 - raw_phase) * 2
      resource_stop_phase = 0.24
      resource_stop_window = 0.08
      mob_stop_phase = 0.58
      mob_stop_window = 0.08
      stop_distance = phase_distance(raw_phase, resource_stop_phase)
      mob_stop_distance = phase_distance(raw_phase, mob_stop_phase)
      resource_x = number(resource_target["x"])
      resource_y = number(resource_target["y"])
      mob_x = number(mob_target["x"])
      mob_y = number(mob_target["y"])

      if stop_distance < resource_stop_window / 2
        orbit_phase = now.to_f / 1200 + route_offset_seconds / 7.0
        orbit_radius = 0.18 + cycle_seconds / 1200.0
        return {
          x: resource_x + Math.cos(orbit_phase) * orbit_radius,
          y: resource_y + Math.sin(orbit_phase * 1.2) * orbit_radius * 0.7,
          phase: raw_phase,
          action: raw_phase < 0.5 ? "gather" : "return"
        }
      end

      if mob_stop_distance < mob_stop_window / 2
        orbit_phase = now.to_f / 1000 + route_offset_seconds / 9.0
        orbit_radius = 0.16 + cycle_seconds / 1600.0
        return {
          x: mob_x + Math.cos(orbit_phase * 1.15) * orbit_radius,
          y: mob_y + Math.sin(orbit_phase) * orbit_radius * 0.8,
          phase: raw_phase,
          action: "fight"
        }
      end

      segment_count = path.length - 1
      segment_float = phase * segment_count
      segment_index = [segment_count - 1, segment_float.floor].min
      local_phase = ease_in_out_cubic(segment_float - segment_index)
      from = path[segment_index]
      to = path[segment_index + 1]
      dx = number(to["x"]) - number(from["x"])
      dy = number(to["y"]) - number(from["y"])
      length = [Math.hypot(dx, dy), 0.0001].max
      sway_phase = Math.sin(now.to_f / 2400 + route_offset_seconds / 3.0)
      sway = 0.06 + cycle_seconds / 2600.0
      sway_x = (-dy / length) * sway * sway_phase
      sway_y = (dx / length) * sway * sway_phase
      action =
        case segment_index
        when 0, 1 then "gather"
        when 2, 3 then "fight"
        when 4, 5 then "return"
        else "gather"
        end

      {
        x: lerp(number(from["x"]), number(to["x"]), local_phase) + sway_x,
        y: lerp(number(from["y"]), number(to["y"]), local_phase) + sway_y,
        phase: raw_phase,
        action: action
      }
    end

    def build_player_positions(state)
      positions = {}
      Array(state["players"]).each do |player|
        positions[player["user_id"].to_i] = { x: number(player["x"]), y: number(player["y"]) }
      end
      positions
    end

    def player_position_for_membership(membership)
      @player_positions[membership.user_id] || { x: 0.0, y: 0.0 }
    end

    def player_spawn_points
      [
        [1, 1],
        [MAP_WIDTH - 2, 1],
        [1, MAP_HEIGHT - 2],
        [MAP_WIDTH - 2, MAP_HEIGHT - 2],
        [MAP_WIDTH / 2, 1],
        [1, MAP_HEIGHT / 2],
        [MAP_WIDTH - 2, MAP_HEIGHT / 2],
        [MAP_WIDTH / 2, MAP_HEIGHT - 2]
      ]
    end

    def route_path_points(base_point, resource_target, mob_target, index)
      base_x, base_y = base_point
      center_x = MAP_WIDTH / 2.0
      center_y = MAP_HEIGHT / 2.0
      boss_x = center_x
      boss_y = center_y
      phase_points = [0.0, 0.08, 0.16, 0.24, 0.32, 0.44, 0.56, 0.68, 0.82, 1.0]
      rng = Random.new(seed_value ^ (index + 13_579))

      phase_points.map.with_index do |phase, waypoint_index|
        anchor_x =
          case waypoint_index
          when 0 then base_x
          when 1 then lerp(base_x, resource_target["x"], 0.42)
          when 2 then resource_target["x"]
          when 3 then lerp(resource_target["x"], mob_target["x"], 0.36)
          when 4 then mob_target["x"]
          when 5 then lerp(mob_target["x"], boss_x, 0.35)
          when 6 then boss_x
          when 7 then lerp(boss_x, base_x, 0.42)
          when 8 then lerp(base_x, resource_target["x"], 0.68)
          else boss_x
          end

        anchor_y =
          case waypoint_index
          when 0 then base_y
          when 1 then lerp(base_y, resource_target["y"], 0.42)
          when 2 then resource_target["y"]
          when 3 then lerp(resource_target["y"], mob_target["y"], 0.36)
          when 4 then mob_target["y"]
          when 5 then lerp(mob_target["y"], boss_y, 0.35)
          when 6 then boss_y
          when 7 then lerp(boss_y, base_y, 0.42)
          when 8 then lerp(base_y, resource_target["y"], 0.68)
          else boss_y
          end

        jitter_scale = [0.65 - index * 0.03, 0.22].max
        wave_x = Math.sin((phase * Math::PI * 2) + index) * jitter_scale
        wave_y = Math.cos((phase * Math::PI * 2) + index / 2.0) * (jitter_scale * 0.45)
        point = {
          x: anchor_x + wave_x + rng.rand(-0.65..0.65),
          y: anchor_y + wave_y + rng.rand(-0.65..0.65)
        }
        {
          "x" => [[point[:x], 1.0].max, MAP_WIDTH - 2.0].min.round(2),
          "y" => [[point[:y], 1.0].max, MAP_HEIGHT - 2.0].min.round(2)
        }
      end
    end

    def mob_payloads(rng)
      total = 10
      Array.new(total) do |index|
        anchor_x = rng.rand(3..MAP_WIDTH - 4)
        anchor_y = rng.rand(3..MAP_HEIGHT - 4)
        {
          "id" => "mob-#{index}",
          "name" => ["Slime", "Scout", "Watcher", "Guard"].sample(random: rng),
          "x" => anchor_x,
          "y" => anchor_y,
          "anchor_x" => anchor_x,
          "anchor_y" => anchor_y,
          "patrol_radius" => (0.2 + rng.rand * 0.45).round(2),
          "patrol_speed" => (0.03 + rng.rand * 0.04).round(2),
          "patrol_phase" => (rng.rand * Math::PI * 2).round(4),
          "hp" => 45,
          "max_hp" => 45,
          "level" => 1 + index / 3,
          "asset_key" => ["slime", "beast", "hunter"].sample(random: rng),
          "hostile" => true,
          "pressure" => 0,
          "alive" => true,
          "respawns_at" => nil,
          "last_defeated_at" => nil
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
        amount = 12 + rng.rand(36)
        {
          "id" => "resource-#{index}",
          "kind" => kind[:kind],
          "asset_key" => kind[:asset_key],
          "x" => rng.rand(1..MAP_WIDTH - 2),
          "y" => rng.rand(1..MAP_HEIGHT - 2),
          "amount" => amount,
          "base_amount" => amount,
          "respawns_at" => nil,
          "alive" => true,
          "pulse_phase" => (index * 0.9 + rng.rand).round(2),
          "pulse_speed" => (0.38 + rng.rand * 0.28).round(2)
        }
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
        "width" => MAP_WIDTH,
        "height" => MAP_HEIGHT,
        "tiles" => tiles
      }
    end

    def mob_position_at(mob, now)
      anchor_x = number(mob["anchor_x"] || mob["x"] || 0)
      anchor_y = number(mob["anchor_y"] || mob["y"] || 0)
      patrol_radius = number(mob["patrol_radius"] || 0.9)
      patrol_speed = number(mob["patrol_speed"] || 0.12)
      patrol_phase = number(mob["patrol_phase"] || 0)
      drift_x = Math.sin(now.to_f / (1100 / patrol_speed) + patrol_phase) * patrol_radius
      drift_y = Math.cos(now.to_f / (1300 / patrol_speed) + patrol_phase) * (patrol_radius * 0.7)
      {
        x: anchor_x + drift_x,
        y: anchor_y + drift_y
      }
    end

    def farm_log_entry(kind, nickname, target, now)
      {
        "kind" => kind,
        "player" => nickname,
        "target" => target,
        "at" => now.iso8601
      }
    end

    def bank_session_xp!(active_members, amount)
      amount = amount.to_i
      return if amount <= 0 || active_members.blank?

      share = amount / active_members.size
      remainder = amount % active_members.size

      active_members.each_with_index do |membership, index|
        banked = share + (index < remainder ? 1 : 0)
        next if banked <= 0

        membership.user.with_lock do
          membership.user.update_columns(
            world_xp_bank: membership.user.world_xp_bank.to_i + banked
          )
        end
      end
    end

    def resolve_boss_reward!(state, active_members, now)
      reward_xp = state["inventory"]["pending_xp"].to_i
      active_members.each do |membership|
        membership.user.apply_world_xp_bank!
        membership.user.with_lock do
          membership.user.update_columns(
            world_boss_kills: membership.user.world_boss_kills.to_i + 1
          )
        end
      end

      state["inventory"]["pending_xp"] = 0
      state["inventory"]["banked_xp"] = 0
      state["inventory"]["applied_xp"] = active_members.sum { |membership| membership.user.world_xp_total }
      state["farm_log"] << farm_log_entry("boss", "system", "#{boss_name} reward #{reward_xp}", now)
    end

    def current_week_slot_utc(now)
      ((now.utc.wday + 6) % 7) * 24 + now.utc.hour
    end

    def boss_name
      suffix = seed_value.to_s.last(4).upcase
      "Shard Warden #{suffix}"
    end

    def boss_hp_base
      4_000 + @layer.layer_index * 500
    end

    def seed_value
      Digest::SHA256.hexdigest("#{@shard.world_seed}:#{@layer.layer_index}").slice(0, 16).to_i(16)
    end

    def parse_time(value)
      return nil if value.blank?

      Time.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    def distance(from_point, to_x, to_y)
      Math.hypot(number(from_point[:x]) - number(to_x), number(from_point[:y]) - number(to_y))
    end

    def lerp(from, to, progress)
      from + (to - from) * progress
    end

    def ease_in_out_cubic(value)
      return 4 * value * value * value if value < 0.5

      offset = -2 * value + 2
      1 - (offset * offset * offset) / 2
    end

    def phase_distance(from, to)
      forward = ((to - from) % 1 + 1) % 1
      [forward, 1 - forward].min
    end

    def number(value)
      Float(value || 0)
    rescue ArgumentError, TypeError
      0.0
    end
  end
end
