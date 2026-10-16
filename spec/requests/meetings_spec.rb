RSpec.describe "Meetings" do
  before { sign_in_as(create(:user)) }

  describe "index" do
    it "shows an empty state before anything has synced" do
      get meetings_path

      expect(response).to have_http_status(:ok)
    end

    it "lists meetings newest first" do
      create(:meeting, title: "Older meeting", recorded_at: 3.days.ago)
      create(:meeting, title: "Newer meeting", recorded_at: 1.day.ago)

      get meetings_path

      expect(response.body.index("Newer meeting")).to be < response.body.index("Older meeting")
    end

    it "filters by search, range, open action items and attendee" do
      create(:meeting, :with_action_items, title: "Acme kickoff", recorded_at: 2.days.ago)
      create(:meeting, title: "Old acme review", recorded_at: 60.days.ago)
      create(:meeting, title: "Globex standup", attendees: [ { "name" => "Alan Turing", "email" => "alan@globex.com" } ])

      get meetings_path(q: "acme", range: "7")
      expect(response.body).to include("Acme kickoff")
      expect(response.body).not_to include("Old acme review", "Globex standup")

      get meetings_path(ai: "1")
      expect(response.body).to include("Acme kickoff")
      expect(response.body).not_to include("Globex standup")

      get meetings_path(attendees: [ "alan@globex.com" ])
      expect(response.body).to include("Globex standup")
      expect(response.body).not_to include("Acme kickoff")
    end

    it "paginates 25 per page and clamps out-of-range pages" do
      26.times { |i| create(:meeting, title: "Meeting #{format('%02d', i)}", recorded_at: i.hours.ago) }

      get meetings_path(page: 2)
      expect(response.body).to include("Meeting 25")
      expect(response.body).not_to include("Meeting 00")

      get meetings_path(page: 99)
      expect(response.body).to include("Meeting 25")
    end
  end

  describe "show" do
    it "renders the summary as sanitized HTML" do
      meeting = create(:meeting, summary: "## Purpose\n\nPlan it <script>alert(1)</script>")

      get meeting_path(meeting)

      expect(response.body).to include("<h2>Purpose</h2>")
      expect(response.body).not_to include("<script>alert(1)")
    end

    it "renders a meeting still processing" do
      get meeting_path(create(:meeting, :processing))

      expect(response).to have_http_status(:ok)
    end

    it "404s for an unknown meeting" do
      get meeting_path(0)

      expect(response).to have_http_status(:not_found)
    end
  end
end
