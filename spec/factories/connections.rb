FactoryBot.define do
  factory :connection do
    source { "clickup" }
    credential { "pk_test_token" }
    status { "connected" }

    trait(:clickup) { source { "clickup" } }
    trait(:hubstaff) do
      source { "hubstaff" }
      credential { "hubstaff-refresh-token" }
    end
    trait(:fathom) do
      source { "fathom" }
      credential { "fathom-api-key" }
      webhook_id { "wh_123" }
      webhook_secret { FathomWebhookHelpers::WEBHOOK_SECRET }
    end
    trait(:anthropic) do
      source { "anthropic" }
      credential { "sk-ant-test" }
    end

    trait(:disconnected) { status { "disconnected" } }
    trait(:errored) do
      status { "error" }
      last_error { "Token rejected." }
    end
    trait(:syncing) { status { "syncing" } }
  end
end
