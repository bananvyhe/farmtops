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
  end
end
