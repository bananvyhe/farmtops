module Api
  class ProfilesController < BaseController
    before_action :ensure_authenticated!

    def show
      render json: { user: user_payload(current_user) }
    end

    def nickname_check
      nickname = normalized_nickname_param

      return render json: { available: false, normalized: nickname, errors: ["Nickname is too short"] } if nickname.blank?
      return render json: { available: false, normalized: nickname, errors: ["Nickname has invalid format"] } unless nickname.match?(User::NICKNAME_PATTERN)

      taken = User.where.not(id: current_user.id).exists?(nickname: nickname)
      render json: { available: !taken, normalized: nickname }
    end

    def prime_overlaps
      render json: { overlaps: prime_overlap_payload }
    end

    def update
      current_user.assign_attributes(profile_params)

      if current_user.save
        render json: { user: user_payload(current_user) }
      else
        render json: { errors: current_user.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def profile_params
      attrs = {}
      attrs[:nickname] = params[:nickname] if params.key?(:nickname)
      attrs[:prime_time_zone] = params[:prime_time_zone] if params.key?(:prime_time_zone)
      attrs[:prime_slots_utc] = Array(params[:prime_slots_utc]) if params.key?(:prime_slots_utc)
      attrs[:prime_cycle_days] = params[:prime_cycle_days] if params.key?(:prime_cycle_days)
      attrs[:prime_cycle_anchor_on] = params[:prime_cycle_anchor_on] if params.key?(:prime_cycle_anchor_on)
      attrs[:prime_cycle_slots_local] = Array(params[:prime_cycle_slots_local]) if params.key?(:prime_cycle_slots_local)
      attrs
    end

    def normalized_nickname_param
      params[:nickname].to_s.strip.downcase
    end

    def prime_overlap_payload
      horizon_days = [[params[:days].to_i, 1].max, User::PRIME_CYCLE_DAYS_RANGE.max].min
      horizon_days = User::PRIME_CYCLE_DAYS_RANGE.max if params[:days].blank?
      zone = Time.find_zone(current_user.prime_time_zone) || Time.zone
      local_start = zone.now.beginning_of_day
      shards = prime_overlap_shards.to_a
      shards_by_id = shards.index_by(&:id)
      cells = {}

      users_by_shard = shards.each_with_object({}) do |shard, result|
        result[shard.id] = shard.layer_memberships.map(&:user).uniq { |user| user.id }.reject { |user| user.id == current_user.id }
      end

      horizon_days.times do |day_offset|
        HOURS_IN_DAY.times do |hour|
          local_time = local_start + day_offset.days + hour.hours
          utc_time = local_time.utc
          next unless current_user.prime_schedule_active?(utc_time)

          matched_users = []
          matched_shards = []

          users_by_shard.each do |shard_id, users|
            shard_matches = users.select { |user| user.prime_schedule_active?(utc_time) }
            next if shard_matches.empty?

            matched_users.concat(shard_matches)
            matched_shards << shards_by_id[shard_id]
          end

          unique_users = matched_users.uniq { |user| user.id }
          next if unique_users.empty?

          cells[[day_offset, hour]] = {
            day_offset:,
            hour:,
            users_count: unique_users.size,
            users: unique_users.sort_by(&:nickname).map { |user| { id: user.id, nickname: user.nickname } },
            shards: matched_shards.compact.uniq { |shard| shard.id }.map { |shard| { id: shard.id, name: shard.name, game_name: shard.game.name } }
          }
        end
      end

      cells.values.sort_by { |cell| [cell[:day_offset], cell[:hour]] }
    end

    HOURS_IN_DAY = 24

    def prime_overlap_shards
      scope = Shard.visible_to_user(current_user).active.includes(:game, layer_memberships: :user)
      return scope.where(id: params[:shard_id]) if params[:shard_id].present?

      scope
    end
  end
end
