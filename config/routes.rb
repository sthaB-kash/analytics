Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Last 7 days of Google Analytics visitor counts, per site.
  get "analytics/garirbazar" => "analytics#garirbazar"

  # Defines the root path route ("/")
  # root "posts#index"
  root "application#home"
end
