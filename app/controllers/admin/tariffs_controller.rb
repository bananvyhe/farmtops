module Admin
  class TariffsController < ApplicationController
    before_action :require_authentication
    before_action :require_admin!
    before_action :set_tariff, only: %i[edit update]

    def index
      @tariffs = Tariff.order(:monthly_price_cents, :name)
    end

    def new
      @tariff = Tariff.new(billing_period_days: 30, active: true)
    end

    def create
      @tariff = Tariff.new(tariff_params)
      if @tariff.save
        redirect_to admin_tariffs_path, success: "Тариф создан."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @tariff.update(tariff_params)
        redirect_to admin_tariffs_path, success: "Тариф обновлён."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_tariff
      @tariff = Tariff.find(params[:id])
    end

    def tariff_params
      params.require(:tariff).permit(:name, :monthly_price_cents, :billing_period_days, :description, :active)
    end
  end
end
