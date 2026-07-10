Rails.application.routes.draw do
  namespace :api do
    resources :flash_sales, only: [:create, :show] do
      member do
        post :reserve
      end
    end
  end

  namespace :webhooks do
    post "orders/create", to: "orders#create"
  end

  get "/dashboard", to: "dashboard#show"
  get "/up", to: "rails/health#show", as: :rails_health_check
end
