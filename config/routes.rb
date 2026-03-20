require "sidekiq/web"

Rails.application.routes.draw do
  protected_sidekiq_web = Rack::Builder.new do
    use Rack::Auth::Basic, "Sidekiq" do |username, password|
      sidekiq_web_username = Rails.application.credentials.dig(:sidekiq, :web_username) || ENV["SIDEKIQ_WEB_USERNAME"]
      sidekiq_web_password = Rails.application.credentials.dig(:sidekiq, :web_password) || ENV["SIDEKIQ_WEB_PASSWORD"]

      next false if sidekiq_web_username.blank? || sidekiq_web_password.blank?

      ActiveSupport::SecurityUtils.secure_compare(username.to_s, sidekiq_web_username.to_s) &
        ActiveSupport::SecurityUtils.secure_compare(password.to_s, sidekiq_web_password.to_s)
    end

    run Sidekiq::Web
  end

  get "up" => "rails/health#show", as: :rails_health_check
  root "home#index"
  mount protected_sidekiq_web, at: "/sidekiq"

  namespace :api do
    resource :session, only: %i[show create destroy]
    resource :registration, only: :create
    resource :dashboard, only: :show, controller: :dashboard
    resources :payment_transactions, path: "payments", only: %i[create show]
    resources :news, only: %i[index show]

    namespace :admin do
      resources :users, only: %i[index update]
      resources :tariffs, only: %i[index create update destroy]
      resources :news_sources do
        post :crawl, on: :member
        resources :news_sections, only: %i[create update destroy]
      end
    end
  end

  resource :session, only: %i[new create destroy]
  resource :dashboard, only: :show, controller: :dashboard
  resources :payment_transactions, path: "payments", only: %i[create show]

  post "payments/yoomoney/notifications", to: "yoo_money_notifications#create", as: :yoo_money_notifications
  # Legacy YooMoney webhook path seen in logs.
  post "api/v1/inb", to: "yoo_money_notifications#create"

  namespace :admin do
    resources :tariffs, except: %i[show destroy]
    resources :users, only: %i[index edit update]
  end
end
