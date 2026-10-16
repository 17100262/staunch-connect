RSpec.describe MeetingAssistantTools do
  let!(:kickoff) do
    create(:meeting, :with_action_items, title: "Acme kickoff", recorded_at: Time.zone.parse("2026-10-01 10:00"),
                                          attendees: [ { "name" => "Ada Lovelace", "email" => "ada@staunch.co" } ])
  end
  let!(:retro) do
    create(:meeting, title: "Sprint retro", recorded_at: Time.zone.parse("2026-09-15 10:00"),
                     attendees: [ { "name" => "Grace Hopper", "email" => "grace@client.com" } ])
  end

  def call(name, input = {})
    described_class.call(name, input)
  end

  it "defines a closed JSON schema for every tool" do
    expect(described_class.definitions.map { |d| d[:name] })
      .to contain_exactly("search_meetings", "get_meeting_summary", "get_meeting_transcript", "search_action_items", "search_meeting_content")
    expect(described_class.definitions.map { |d| d.dig(:input_schema, :additionalProperties) }).to all(be(false))
  end

  describe "search_meetings" do
    it "matches title or attendee, newest first" do
      result = call("search_meetings", "query" => "ada")

      expect(result).to include(total_matches: 1, truncated: false)
      expect(result[:meetings].first).to include(id: kickoff.id, title: "Acme kickoff", attendees: [ "Ada Lovelace" ])
    end

    it "filters by date range" do
      result = call("search_meetings", "date_from" => "2026-09-01", "date_to" => "2026-09-30")

      expect(result[:meetings].map { |m| m[:id] }).to eq([ retro.id ])
    end

    it "rejects a malformed date" do
      expect(call("search_meetings", "date_from" => "last week")).to eq(error: "Invalid date_from — use YYYY-MM-DD.")
    end

    it "caps results at ten and says so" do
      11.times { create(:meeting, title: "Standup") }

      result = call("search_meetings", "query" => "standup")

      expect(result).to include(total_matches: 11, truncated: true)
      expect(result[:meetings].size).to eq(10)
    end
  end

  describe "get_meeting_summary" do
    it "returns the summary and action items" do
      result = call("get_meeting_summary", "id" => kickoff.id)

      expect(result[:meeting]).to include(title: "Acme kickoff", summary: kickoff.summary)
      expect(result[:meeting][:action_items].map { |i| i[:description] }).to eq([ "Send the release notes", "Book the retro" ])
    end

    it "flags a meeting still processing instead of returning an empty summary" do
      processing = create(:meeting, :processing)

      expect(call("get_meeting_summary", "id" => processing.id)[:meeting]).to include(processing: true, summary: nil)
    end

    it "refuses a guessed id" do
      expect(call("get_meeting_summary", "id" => 0)[:found]).to be(false)
    end
  end

  describe "get_meeting_transcript" do
    it "returns the transcript" do
      expect(call("get_meeting_transcript", "id" => kickoff.id)).to include(found: true, transcript: kickoff.transcript)
    end

    it "reports processing meetings as such" do
      processing = create(:meeting, :processing)

      expect(call("get_meeting_transcript", "id" => processing.id)).to include(processing: true)
    end
  end

  describe "search_action_items" do
    it "filters by assignee" do
      result = call("search_action_items", "assignee" => "grace")

      expect(result[:action_items].map { |i| i[:description] }).to eq([ "Book the retro" ])
    end

    it "filters by completion" do
      result = call("search_action_items", "completed" => false)

      expect(result[:action_items].map { |i| i[:description] }).to eq([ "Send the release notes" ])
    end

    it "reports how many meetings were scanned" do
      expect(call("search_action_items")).to include(total_meetings_scanned: 2, total_action_items: 2)
    end
  end

  describe "search_meeting_content" do
    around { |example| with_env("VOYAGE_API_KEY" => "voyage-key") { example.run } }

    it "returns the closest chunks with their meeting and relevance" do
      create(:transcript_chunk, meeting: kickoff, content: "We discussed pricing.", embedding: Array.new(1023, 0.0) + [ 1.0 ])
      create(:transcript_chunk, meeting: retro, content: "Velocity was low.", embedding: [ 1.0 ] + Array.new(1023, 0.0))
      stub_voyage_embeddings(vector: Array.new(1023, 0.0) + [ 1.0 ])

      results = call("search_meeting_content", "query" => "pricing")[:results]

      expect(results.first).to include(meeting_id: kickoff.id, excerpt: "We discussed pricing.", relevance: 1.0)
    end

    it "only searches meetings in the date range" do
      create(:transcript_chunk, meeting: retro)
      stub_voyage_embeddings

      expect(call("search_meeting_content", "query" => "x", "date_from" => "2026-10-01")[:results]).to be_empty
    end

    it "requires a query" do
      expect(call("search_meeting_content", "query" => "")).to eq(error: "query is required.")
    end
  end
end
