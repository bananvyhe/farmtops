module Api
  class ShardsController < BaseController
    before_action :ensure_authenticated!

    def index
      shards = current_user.shards.includes(:game).order(created_at: :desc)
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
        render json: { shard: shard_payload(shard) }, status: :created
      else
        render json: { errors: shard.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def shard_payload(shard)
      {
        id: shard.id,
        user_id: shard.user_id,
        game_id: shard.game_id,
        game_name: shard.game.name,
        name: shard.name,
        world_seed: shard.world_seed,
        status: shard.status,
        created_at: shard.created_at,
        updated_at: shard.updated_at
      }
    end
  end
end
