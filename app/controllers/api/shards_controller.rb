module Api
  class ShardsController < BaseController
    before_action :ensure_authenticated!
    before_action :set_shard, only: %i[world enter leave]

    def index
      shards = Shard.visible_to_user(current_user).includes(:game, layers: :memberships).order("shards.created_at DESC")
      render json: { shards: shards.map { |shard| shard_payload(shard) } }
    end

    def create
      game = Game.find(params[:game_id])
      return render_error("Game not available", status: :not_found) if game.followers_count.zero?

      shard = Shard.find_or_initialize_by(game_id: game.id)
      shard.assign_attributes(
        user_id: shard.user_id || current_user.id,
        name: shard.name.presence || Shard.build_name(game),
        world_seed: shard.world_seed.presence || Shard.build_seed,
        status: shard.status || :draft
      )

      if shard.save
        Shards::LayerAllocator.new(shard:, user: current_user).call
        payload = world_payload(shard)
        broadcast_world_snapshot(shard, payload)
        render json: payload, status: :created
      else
        render json: { errors: shard.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def world
      Shards::MembershipPresence.touch(shard: @shard, user: current_user)
      payload = world_payload(@shard)
      broadcast_world_snapshot(@shard, payload)
      render json: payload
    end

    def enter
      result = Shards::LayerAllocator.new(shard: @shard, user: current_user, desired_layer_id: params[:layer_id]).call
      payload = world_payload(@shard).merge(joined_layer_id: result.layer.id)
      broadcast_world_snapshot(@shard, payload.except(:joined_layer_id))
      render json: payload
    rescue ActiveRecord::RecordNotFound
      render_error("Layer not found", status: :not_found)
    rescue StandardError => e
      render_error(e.message, status: :unprocessable_entity)
    end

    def leave
      membership = @shard.layer_memberships.find_by(user_id: current_user.id)
      unless membership
        payload = world_payload(@shard).merge(left: false)
        return render json: payload
      end

      membership.destroy!
      payload = world_payload(@shard).merge(left: true)
      broadcast_world_snapshot(@shard, payload.except(:left))
      render json: payload
    end

    private

    def set_shard
      @shard = Shard.visible_to_user(current_user).includes(layers: { memberships: :user }).find_by(id: params[:id])
      render_error("Shard not found", status: :not_found) if @shard.blank?
    end

    def world_payload(shard)
      Shards::WorldStateBuilder.new(shard:, current_user:).call
    end

    def broadcast_world_snapshot(shard, payload)
      Shards::RealtimeBroadcaster.broadcast_world_snapshot(shard:, payload:)
    end

    def shard_payload(shard)
      {
        id: shard.id,
        user_id: shard.user_id,
        game_id: shard.game_id,
        game_name: shard.game.name,
        name: shard.name,
        world_seed: shard.world_seed,
        status: shard.status,
        layers_count: shard.layers.size,
        created_at: shard.created_at,
        updated_at: shard.updated_at
      }
    end
  end
end
