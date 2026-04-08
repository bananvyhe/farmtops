module Shards
  class WorldStateBuilder
    MAP_WIDTH = 28
    MAP_HEIGHT = 16

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
      boss_hp = 4_000 + members.size * 1_200 + layer.layer_index * 500
      boss_progress = [members.size * 13 + (Time.current.to_i / 5 % 25), 100].min

      {
        tick: Time.current.to_i / 2,
        seed: "#{@shard.world_seed}:#{layer.layer_index}",
        map: map_payload(rng),
        players: player_payloads(members, rng),
        mobs: mob_payloads(rng, members.size),
        resources: resource_payloads(rng),
        boss: {
          id: "boss-#{layer.id}",
          name: boss_name(seed),
          x: MAP_WIDTH / 2,
          y: MAP_HEIGHT / 2,
          hp: boss_hp,
          max_hp: boss_hp,
          progress: boss_progress
        },
        progress: {
          layer_index: layer.layer_index,
          occupancy: members.size,
          capacity: layer.capacity,
          energy_flow: 40 + members.size * 7,
          group_goal: 100,
          group_progress: boss_progress
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

    def player_payloads(members, rng)
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
        {
          id: membership.user_id,
          nickname: membership.user.nickname,
          x: base_x + (rng.rand(3) - 1),
          y: base_y + (rng.rand(3) - 1),
          hp: 100,
          max_hp: 100,
          energy: 100,
          level: 1 + index / 2,
          bot: true,
          role: index.zero? ? "leader" : "support"
        }
      end
    end

    def mob_payloads(rng, players_count)
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
          hostile: true
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

    def boss_name(seed)
      suffix = seed.to_s.last(4).upcase
      "Shard Warden #{suffix}"
    end

    def seed_value(layer)
      Digest::SHA256.hexdigest("#{@shard.world_seed}:#{layer.layer_index}").slice(0, 16).to_i(16)
    end
  end
end
