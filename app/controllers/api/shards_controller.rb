module Api
  class ShardsController < BaseController
    before_action :ensure_authenticated!
    before_action :set_shard, only: %i[world group_search_forecast enter leave]

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

    def group_search_forecast
      render json: { forecast: group_search_forecast_payload(@shard) }
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

      payload = world_payload(@shard).merge(left: true)
      Shard.transaction do
        membership.destroy!
      end

      broadcast_world_snapshot(@shard, payload.except(:left))
      render json: payload.merge(shard_deleted: false)
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

    def group_search_forecast_payload(shard)
      current_slots = current_user.prime_cycle_slots_local
      now = Time.current
      memberships = shard.layer_memberships.includes(:user).order(:joined_at).to_a
      member_ids = memberships.map(&:user_id)
      bookmarked_user_ids = NewsGameBookmark.where(game_id: shard.game_id, user_id: member_ids).pluck(:user_id)
      bookmarked_members = memberships.select { |membership| bookmarked_user_ids.include?(membership.user_id) }

      return {
        ready: false,
        reason: "Настройте прайм-цикл, чтобы увидеть фантомный прогноз.",
        shard: {
          id: shard.id,
          game_id: shard.game_id,
          game_name: shard.game.name
        },
        current_user: {
          id: current_user.id,
          nickname: current_user.nickname,
          prime_slots_count: current_slots.size,
          prime_cycle_days: current_user.prime_cycle_days
        },
        members_count: memberships.size,
        bookmarked_members_count: bookmarked_members.size,
        matched_members_count: 0,
        total_shared_hours: 0,
        users: []
      } if current_slots.empty?

      users = bookmarked_members.filter_map do |membership|
        next if membership.user_id == current_user.id

        overlap = current_user.prime_slot_overlap(membership.user, from: now, horizon_days: 14)

        {
          id: membership.user_id,
          nickname: membership.user.nickname,
          owner: membership.user_id == shard.user_id,
          active_now: membership.user.prime_schedule_active?(now),
          shared_prime_hours: overlap.size,
          prime_slots_count: membership.user.prime_cycle_slots_local.size,
          prime_cycle_days: membership.user.prime_cycle_days,
          prime_cycle_anchor_on: membership.user.prime_cycle_anchor_on,
          prime_windows: membership.user.prime_cycle_slots_local.first(4).map { |slot| prime_cycle_slot_label(slot, membership.user.prime_cycle_days) },
          overlap_slots: overlap.first(4).map { |slot| { at: slot, label: forecast_slot_label(slot) } },
          slots: overlap.first(4).map { |slot| { at: slot, label: forecast_slot_label(slot) } }
        }
      end.sort_by { |user| [-user[:shared_prime_hours], user[:nickname]] }

      {
        ready: true,
        shard: {
          id: shard.id,
          game_id: shard.game_id,
          game_name: shard.game.name
        },
        current_user: {
          id: current_user.id,
          nickname: current_user.nickname,
          prime_slots_count: current_slots.size,
          prime_cycle_days: current_user.prime_cycle_days
        },
        members_count: memberships.size,
        bookmarked_members_count: bookmarked_members.size,
        matched_members_count: users.count { |user| user[:shared_prime_hours].to_i.positive? },
        total_shared_hours: users.sum { |user| user[:shared_prime_hours] },
        users: users
      }
    end

    def prime_cycle_slot_label(slot_index, cycle_days)
      day = slot_index / 24
      hour = slot_index % 24
      "День #{day + 1}/#{cycle_days} #{format('%02d:00', hour)}"
    end

    def forecast_slot_label(slot_iso8601)
      Time.zone.parse(slot_iso8601).strftime("%d.%m %H:%M")
    rescue StandardError
      slot_iso8601
    end
  end
end
