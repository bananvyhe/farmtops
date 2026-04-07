module Api
  class ProfilesController < BaseController
    before_action :ensure_authenticated!

    def show
      render json: { user: user_payload(current_user) }
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
      {
        prime_time_zone: params[:prime_time_zone],
        prime_slots_utc: Array(params[:prime_slots_utc])
      }
    end
  end
end
