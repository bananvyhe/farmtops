class SessionsController < ApplicationController
  def new
    redirect_to dashboard_path if user_signed_in?
  end

  def create
    user = User.find_by(email: params[:email].to_s.downcase)

    if user&.authenticate(params[:password]) && user.active?
      sign_in!(user)
      redirect_to dashboard_path, success: "Вход выполнен."
    else
      flash.now[:alert] = "Неверный e-mail, пароль или доступ отключён."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    sign_out!
    redirect_to root_path, notice: "Сессия завершена."
  end
end
