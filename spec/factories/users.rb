FactoryBot.define do
  factory :user do
    sequence(:email_address) { |n| "person#{n}@staunch.co" }
    password { AuthHelpers::DEFAULT_PASSWORD }
    name { "Ada Lovelace" }
  end

  factory :session do
    user
    user_agent { "RSpec" }
    ip_address { "127.0.0.1" }
  end
end
