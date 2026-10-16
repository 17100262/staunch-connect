FactoryBot.define do
  factory :project_mapping do
    sequence(:clickup_space_id) { |n| "space_#{n}" }
    clickup_space_name { "Acme" }
    sequence(:clickup_folder_id) { |n| "folder_#{n}" }
    clickup_folder_name { "Acme Website" }
    default_hourly_rate { 100 }

    trait :space_only do
      clickup_folder_id { nil }
      clickup_folder_name { nil }
    end

    trait :with_hubstaff do
      hubstaff_project_id { "hs_1" }
      hubstaff_project_name { "Staunch / Acme Website" }
    end
  end

  factory :invoice do
    project_mapping
    sequence(:month) { |n| (Date.new(2026, 1, 1) + (n % 12).months).strftime("%Y-%m") }
    name { "Acme Website" }

    trait :with_line_items do
      after(:create) do |invoice|
        create(:invoice_line_item, invoice: invoice, title: "Build homepage", estimate_hours: 10, hourly_rate: 100)
        create(:invoice_line_item, invoice: invoice, title: "Fix login", estimate_hours: 2.5, hourly_rate: 100)
        create(:invoice_line_item, :non_billable, invoice: invoice, title: "Internal sync", estimate_hours: 1, hourly_rate: 100)
      end
    end
  end

  factory :invoice_line_item do
    invoice
    sequence(:title) { |n| "Task #{n}" }
    sequence(:ticket) { |n| "TCK-#{n}" }
    estimate_hours { 1 }
    hourly_rate { 100 }
    billable { true }

    trait(:non_billable) { billable { false } }
  end
end
