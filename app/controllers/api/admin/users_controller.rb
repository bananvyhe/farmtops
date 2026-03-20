module Api
  module Admin
    class UsersController < BaseController
      before_action :ensure_authenticated!
      before_action :ensure_admin!

      def index
        users = User.includes(:tariff).order(:email).sort_by(&:created_at).reverse
        render json: {
          users: users.map { |user| user_payload(user) },
          tariffs: Tariff.active.map { |tariff| tariff_payload(tariff) }
        }
      end

      def update
        user = User.find(params[:id])
        if user.update(admin_user_params)
          render json: { user: user_payload(user) }
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def admin_user_params
        params.permit(:role, :hourly_rate_cents, :active, :tariff_id)
      end
    end
  end
end
