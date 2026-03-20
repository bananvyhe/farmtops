module Api
  module Admin
    class TariffsController < BaseController
      before_action :ensure_authenticated!
      before_action :ensure_admin!
      before_action :set_tariff, only: %i[update destroy]

      def index
        render json: { tariffs: Tariff.order(:monthly_price_cents, :name).map { |tariff| tariff_payload(tariff) } }
      end

      def create
        tariff = Tariff.new(tariff_params)
        if tariff.save
          render json: { tariff: tariff_payload(tariff) }, status: :created
        else
          render json: { errors: tariff.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @tariff.update(tariff_params)
          render json: { tariff: tariff_payload(@tariff) }
        else
          render json: { errors: @tariff.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @tariff.destroy!
        head :no_content
      end

      private

      def set_tariff
        @tariff = Tariff.find(params[:id])
      end

      def tariff_params
        params.permit(:name, :monthly_price_cents, :billing_period_days, :description, :active)
      end
    end
  end
end
