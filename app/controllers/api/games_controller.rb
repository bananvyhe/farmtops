module Api
  class GamesController < BaseController
    before_action :ensure_authenticated!, only: :prime_overlaps

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

    def prime_overlaps
      game = Game.find(params[:game_id])
      slots = current_user.prime_cycle_slots_local
      users = User.visible_in_prime_search
        .where.not(id: current_user.id)
        .joins(:news_game_bookmarks)
        .where(news_game_bookmarks: { game_id: game.id })
        .with_prime_cycle_overlap(slots)
        .distinct

      users_by_slot = Hash.new { |hash, slot| hash[slot] = [] }
      users.each do |user|
        user.prime_cycle_slots_local.each do |slot|
          users_by_slot[slot] << user if slots.include?(slot)
        end
      end

      overlaps = slots.filter_map do |slot|
        matching_users = users_by_slot[slot].uniq { |user| user.id }
        next if matching_users.empty?

        {
          slot_index: slot,
          day_index: slot / 24,
          hour: slot % 24,
          users_count: matching_users.size,
          users: matching_users.sort_by(&:nickname).map { |user| { id: user.id, nickname: user.nickname } }
        }
      end

      render json: { game: game_payload(game), overlaps: }
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
