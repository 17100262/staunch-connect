FactoryBot.define do
  factory :ai_conversation do
    user
    title { "Invoice totals" }
  end

  factory :ai_message do
    ai_conversation
    role { "user" }
    content { "How much did we bill Acme?" }

    trait(:assistant) do
      role { "assistant" }
      content { "You billed **$1,250.00**." }
    end
  end
end
