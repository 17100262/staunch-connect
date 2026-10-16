RSpec.describe "Dashboard and preview pages" do
  before { sign_in_via_ui(create(:user)) }

  it "nudges a new workspace to connect its sources" do
    visit root_path

    expect(page).to have_css("h1", text: "Dashboard")
    expect(page).to have_text("No invoices yet")
    expect(page).to have_text("No meetings yet")
  end

  it "summarises billing, invoices that need attention and new meetings" do
    create(:connection, :clickup)
    create(:connection, :hubstaff)
    create(:connection, :fathom)
    create(:invoice, :with_line_items, month: Date.current.strftime("%Y-%m"), name: "Acme Website")
    create(:invoice_line_item, invoice: create(:invoice, month: Date.current.strftime("%Y-%m"), name: "Globex"), hourly_rate: nil)
    create(:meeting, title: "Acme kickoff", recorded_at: 1.day.ago)

    visit root_path

    expect(page).to have_text("Billed this month\n$1,250")
    expect(page).to have_text("Globex #{Date.current.strftime('%b %Y')}\n1 line without a rate")
    expect(page).to have_text("Acme kickoff")
    expect(page).to have_text("1 new")
  end

  it "shows the notifications preview" do
    visit notifications_path

    expect(page).to have_css("h1", text: "Notifications")
    expect(page).to have_button("Mark all as read", disabled: true)
  end

  it "shows the Task 360 preview" do
    visit task_360_path

    expect(page).to have_css("h1", text: "Task 360")
    expect(page).to have_button("Over estimate")
  end

  it "filters search results by type", pending: "analysis.md #21: the search dialog's type chips do nothing yet" do
    find(".rail-search").click
    within("[role=dialog][aria-label=Search]") { click_on "Meetings" }

    expect(page).to have_css(".search-chips button[aria-pressed=true]", text: "Meetings")
  end
end
