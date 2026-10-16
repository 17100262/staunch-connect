FactoryBot.define do
  factory :meeting do
    sequence(:fathom_recording_id) { |n| (1000 + n).to_s }
    title { "Weekly sync" }
    fathom_url { "https://fathom.video/share/abc" }
    recorded_at { 2.days.ago }
    duration_minutes { 30 }
    attendees { [ { "name" => "Ada Lovelace", "email" => "ada@staunch.co" }, { "name" => "Grace Hopper", "email" => "grace@client.com" } ] }
    summary { "## Meeting Purpose\n\nPlan the release.\n\n## Key Takeaways\n\nShip on Friday." }
    transcript { "Ada Lovelace: Let's ship Friday.\nGrace Hopper: Agreed." }
    action_items { [] }
    synced_at { Time.current }

    trait :processing do
      summary { nil }
      transcript { nil }
    end

    trait :with_action_items do
      action_items do
        [
          { "description" => "Send the release notes", "completed" => false, "assignee" => { "name" => "Ada Lovelace", "email" => "ada@staunch.co" } },
          { "description" => "Book the retro", "completed" => true, "assignee" => { "name" => "Grace Hopper", "email" => "grace@client.com" } }
        ]
      end
    end
  end

  factory :transcript_chunk do
    meeting
    source { "transcript" }
    sequence(:chunk_index)
    content { "Ada Lovelace: Let's ship Friday." }
    embedding { Array.new(1024, 0.01) }
  end
end
