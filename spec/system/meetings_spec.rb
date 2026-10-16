RSpec.describe "Meetings" do
  before { sign_in_via_ui(create(:user)) }

  it "points you to Fathom before it's connected" do
    visit meetings_path

    expect(page).to have_text("Meetings start with Fathom")
    click_on "Connect Fathom"
    expect(page).to have_css("#sm2-t", text: "Connectors")
  end

  it "says when Fathom is connected but nothing has synced" do
    create(:connection, :fathom)

    visit meetings_path

    expect(page).to have_text("No meetings yet")
    expect(page).to have_button("Sync from Fathom")
  end

  it "starts a sync from the page and shows it running" do
    connection = create(:connection, :fathom)
    create(:meeting)

    visit meetings_path
    click_on "Sync from Fathom"

    expect(page).to have_text("Fathom sync started in the background")
    expect(page).to have_button("Syncing…", disabled: true)
    expect(connection.reload).to be_syncing
  end

  it "flags a broken Fathom connection" do
    create(:connection, :fathom, :errored, last_error: "Fathom rejected this API key.")
    create(:meeting)

    visit meetings_path

    expect(page).to have_text("Fathom needs attention")
    expect(page).to have_text("Fathom rejected this API key.")
  end

  describe "the list" do
    before do
      create(:connection, :fathom)
      create(:meeting, :with_action_items, title: "Acme kickoff", recorded_at: 2.days.ago,
                                            attendees: [ { "name" => "Ada Lovelace", "email" => "ada@staunch.co" } ])
      create(:meeting, title: "Globex standup", recorded_at: 3.days.ago, action_items: [],
                       attendees: [ { "name" => "Alan Turing", "email" => "alan@globex.com" } ])
      create(:meeting, :processing, title: "Old retro", recorded_at: 40.days.ago, attendees: [])
    end

    before { visit meetings_path }

    it "shows each meeting's attendees, open action items and processing state" do
      within("tr", text: "Acme kickoff") { expect(page).to have_text("1 open").and have_text("Ada Lovelace") }
      within("tr", text: "Globex standup") { expect(page).to have_text("None") }
      within("tr", text: "Old retro") { expect(page).to have_text("Processing") }
      expect(page).to have_text("3 meetings")
    end

    it "searches as you type" do
      fill_in "Search meetings by title or attendee", with: "globex"

      expect(page).to have_no_text("Acme kickoff")
      expect(page).to have_text("Globex standup")
    end

    it "shows a clearable empty state when nothing matches" do
      fill_in "Search meetings by title or attendee", with: "zzz"

      expect(page).to have_text("No meetings match “zzz”")
      click_on "Clear filters"
      expect(page).to have_text("Acme kickoff")
    end

    it "filters to meetings with open action items" do
      click_on "Has action items"

      expect(page).to have_text("Acme kickoff")
      expect(page).to have_no_text("Globex standup")
      expect(page).to have_css("button[aria-pressed=true]", text: "Has action items")
    end

    it "filters by date range" do
      click_on "Any time"
      click_on "Last 7 days"

      expect(page).to have_no_text("Old retro")
      expect(page).to have_text("Acme kickoff")
    end

    it "filters by attendee and clears the filter" do
      find("[aria-label='Attendees filter'] .chip-main").click
      within("[role=menu][aria-label=Attendees]") { click_on "Alan Turing" }

      expect(page).to have_no_text("Acme kickoff")
      expect(page).to have_text("Globex standup")

      click_on "Clear attendees filter"
      expect(page).to have_text("Acme kickoff")
    end
  end

  it "pages through long lists" do
    create(:connection, :fathom)
    26.times { |i| create(:meeting, title: "Meeting #{format('%02d', i)}", recorded_at: i.hours.ago) }

    visit meetings_path
    expect(page).to have_text("26 meetings")
    click_on "Next"

    expect(page).to have_text("Meeting 25")
    expect(page).to have_button("Next", disabled: true)
    click_on "Previous"
    expect(page).to have_text("Meeting 00")
  end

  describe "a meeting" do
    let(:meeting) do
      create(:meeting, :with_action_items, title: "Acme kickoff", duration_minutes: 45,
                                            summary: "## Purpose\n\nPlan the **launch**.",
                                            transcript: "Ada Lovelace: Let's ship Friday.")
    end

    it "shows the summary, action items and transcript in tabs" do
      visit meetings_path
      visit meeting_path(meeting)

      expect(page).to have_css("h1", text: "Acme kickoff")
      expect(page).to have_text("45 min")
      expect(page).to have_css("strong", text: "launch")

      click_on "Action items"
      expect(page).to have_text("Send the release notes")
      expect(page).to have_text("Book the retro")

      click_on "Transcript"
      expect(page).to have_text("Let's ship Friday.")
      expect(page).to have_no_text("Plan the launch")
    end

    it "explains a meeting still processing" do
      visit meeting_path(create(:meeting, :processing))

      expect(page).to have_text("Still processing in Fathom")
    end

    it "links back to the list and out to Fathom" do
      visit meeting_path(meeting)

      expect(page).to have_link("View in Fathom", href: meeting.fathom_url)
      click_on "Back to all meetings"
      expect(page).to have_current_path(meetings_path)
    end
  end
end
