class YooMoneyNotificationsController < ActionController::Base
  protect_from_forgery with: :null_session

  def create
    if Payments::YooMoneyNotificationProcessor.new(params.to_unsafe_h).call
      head :ok
    else
      head :unprocessable_entity
    end
  end
end
