Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  resources :games, only: [ :index, :show ] do
    resources :analyses, only: [ :index, :show ] do
      get :prompt, on: :member
    end
    resources :events, only: [ :index ], controller: "game_events"
    resource :geometry, only: [ :show ], controller: "empire_geometries"
    resource :army, only: [ :show ], controller: "army_compositions"
    resource :cultural, only: [ :show ], controller: "cultural_standings"
    resource :congress, only: [ :show ], controller: "congress_histories"
    resource :victory_progress, only: [ :show ], controller: "victory_progress_histories"
  end

  # Defines the root path route ("/")
  root "games#index"
end
