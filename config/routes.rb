Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resources :connections, only: %i[index create destroy] do
    member { post :sync }
  end

  resources :meetings, only: %i[index show]

  namespace :webhooks do
    post "fathom", to: "fathom#create"
  end

  get "invoicing", to: "invoices#new", as: :invoicing
  get "invoicing/draft", to: "invoices#draft", as: :invoicing_draft
  resources :invoices, only: %i[index create show update destroy] do
    member { get :export }
  end
  resources :project_mappings, only: %i[create destroy]

  resources :ai_conversations, only: %i[index show create destroy] do
    resources :messages, only: %i[create], controller: "ai_messages"
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "home#index"
end
