module Api
  class ShardsController < BaseController
    before_action :ensure_authenticated!
    before_action :set_shard, only: %i[world enter leave]

    def index
      shards = current_user.shards.includes(:game, layers: :memberships).order(created_at: :desc)
      render json: { shards: shards.map { |shard| shard_payload(shard) } }
    end

    def create
      game = Game.find(params[:game_id])
      return render_error("Game not available", status: :not_found) if game.followers_count.zero?

      shard = current_user.shards.find_or_initialize_by(game_id: game.id)
      shard.assign_attributes(
        name: Shard.build_name(game, current_user),
        world_seed: shard.world_seed.presence || Shard.build_seed,
        status: shard.status || :draft
      )

      if shard.save
        Shards::LayerAllocator.new(shard:, user: current_user).call
        render json: world_payload(shard), status: :created
      else
        render json: { errors: shard.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def world
      render json: world_payload(@shard)
    end

    def enter
      result = Shards::LayerAllocator.new(shard: @shard, user: current_user, desired_layer_id: params[:layer_id]).call
      render json: world_payload(@shard).merge(joined_layer_id: result.layer.id)
    rescue ActiveRecord::RecordNotFound
      render_error("Layer not found", status: :not_found)
    rescue StandardError => e
      render_error(e.message, status: :unprocessable_entity)
    end

    def leave
      membership = @shard.layer_memberships.find_by(user_id: current_user.id)
      return render json: world_payload(@shard).merge(left: false) unless membership

      membership.destroy!
      render json: world_payload(@shard).merge(left: true)
    end

    private

    def set_shard
      @shard = current_user.shards.includes(layers: { memberships: :user }).find_by(id: params[:id])
      return if @shard.present?

      @shard = Shard.joins(:layer_memberships).includes(layers: { memberships: :user }).find_by(id: params[:id], shard_layer_memberships: { user_id: current_user.id })
      render_error("Shard not found", status: :not_found) if @shard.blank?
    end

    def world_payload(shard)
      Shards::WorldStateBuilder.new(shard:, current_user:).call
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
