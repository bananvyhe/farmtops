module Admin
  class UsersController < ApplicationController
    before_action :require_authentication
    before_action :require_admin!
    before_action :set_user, only: %i[edit update]

    def index
      @users = User.includes(:tariff).order(:email)
    end

    def edit
      @tariffs = Tariff.active
    end

    def update
      @tariffs = Tariff.active
      if @user.update(admin_user_params)
        redirect_to admin_users_path, success: "Права и тариф обновлены."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    def admin_user_params
      params.require(:user).permit(:role, :hourly_rate_cents, :active, :tariff_id)
    end
  end
end
