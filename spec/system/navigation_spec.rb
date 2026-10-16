RSpec.describe "Navigation" do
  before { sign_in_via_ui(create(:user, name: "Ada Lovelace")) }

  it "moves between sections and marks the current one" do
    { "Meetings" => meetings_path, "Invoicing" => invoices_path, "AI Assistant" => ai_conversations_path,
      "Notifications" => notifications_path, "Task 360" => task_360_path, "Home" => root_path }.each do |label, path|
      within("nav[aria-label=Primary]") { click_on label }

      expect(page).to have_current_path(path)
      expect(page).to have_css("nav[aria-label=Primary] a[aria-current=page][aria-label='#{label}']")
    end
  end

  it "collapses the sidebar and remembers it across pages" do
    click_on "Collapse sidebar"
    expect(page).to have_css("aside.sidebar[data-collapsed]")
    expect(page).to have_button("Expand sidebar")

    visit meetings_path
    expect(page).to have_css("aside.sidebar[data-collapsed]")

    click_on "Expand sidebar"
    expect(page).to have_no_css("aside.sidebar[data-collapsed]")
  end

  it "opens search with Ctrl+K, searches meetings and closes with Esc" do
    create(:meeting, title: "Acme kickoff")
    create(:meeting, title: "Globex standup")

    find("body").send_keys([ :control, "k" ])
    expect(page).to have_css("[role=dialog][aria-label=Search]", visible: true)

    find(".search-field").send_keys(:escape)
    expect(page).to have_no_css("[role=dialog][aria-label=Search]", visible: true)

    find(".rail-search").click
    find(".search-field").fill_in(with: "acme")
    find(".search-field").send_keys(:enter)

    expect(page).to have_current_path(meetings_path(q: "acme"))
    expect(page).to have_text("Acme kickoff")
    expect(page).to have_no_text("Globex standup")
  end

  it "switches to dark mode from the account menu and keeps it" do
    click_on "Account menu"
    within("[role=menu][aria-label=Account]") { click_on "Dark" }

    expect(page).to have_css("html[data-theme=dark]")
    visit meetings_path
    expect(page).to have_css("html[data-theme=dark]")
  end

  it "closes the account menu with Escape or a click outside" do
    click_on "Account menu"
    expect(page).to have_css("[role=menu][aria-label=Account]", visible: true)

    find("body").send_keys(:escape)
    expect(page).to have_no_css("[role=menu][aria-label=Account]", visible: true)
  end
end
