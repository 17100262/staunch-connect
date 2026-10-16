RSpec.describe "Pages" do
  before { sign_in_as(create(:user)) }

  describe "home dashboard" do
    it "nudges you to connect sources when nothing is connected" do
      get root_path

      expect(response).to have_http_status(:ok)
    end

    it "summarises this month's invoices and recent meetings" do
      travel_to Time.zone.local(2026, 10, 16, 12) do
        create(:connection, :clickup)
        create(:invoice, :with_line_items, month: "2026-10", name: "Acme Website")
        create(:invoice_line_item, invoice: create(:invoice, month: "2026-10", name: "Globex"), hourly_rate: nil)
        create(:meeting, title: "Yesterday's sync", recorded_at: 1.day.ago)

        get root_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Yesterday&#39;s sync").or include("Yesterday's sync")
        expect(response.body).to include("without a rate")
      end
    end
  end

  it "renders Task 360" do
    get task_360_path

    expect(response).to have_http_status(:ok)
  end

  it "renders notifications" do
    get notifications_path

    expect(response).to have_http_status(:ok)
  end
end
