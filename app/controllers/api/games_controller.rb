module Api
  class GamesController < BaseController
    def search
      pinned_games = pinned_game_scope
      query = params[:q].to_s.strip
      games = if query.blank?
        pinned_games
      else
        (pinned_games + Game.search_candidates(query:, limit: limit_param)).uniq { |game| game.id }.first(limit_param)
      end
      render json: {
        games: games.map { |game| game_payload(game) }
      }
    end

    private

    def pinned_game_scope
      ids = Array(params[:ids]).flat_map { |value| value.to_s.split(",") }.map(&:to_i).reject(&:zero?)
      return Game.none if ids.blank?

      Game.where(id: ids)
    end

    def limit_param
      value = params.fetch(:limit, 20).to_i
      value = 20 if value <= 0
      [value, 50].min
    end

    def game_payload(game)
      {
        id: game.id,
        name: game.name,
        slug: game.slug,
        normalized_name: game.normalized_name
      }
    end
  end
end
