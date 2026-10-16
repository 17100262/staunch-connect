RSpec.describe FathomSyncJob do
  let!(:connection) { create(:connection, :fathom, :syncing) }

  it "pulls meetings, upserts them and marks the connection connected" do
    stub_fathom_meetings([ fathom_meeting_payload(recording_id: 1), fathom_meeting_payload(recording_id: 2) ])

    described_class.perform_now(connection.id)

    expect(Meeting.pluck(:fathom_recording_id)).to contain_exactly("1", "2")
    expect(connection.reload).to have_attributes(status: "connected", last_error: nil)
    expect(connection.last_used_at).to be_present
  end

  it "backfills everything on the first sync" do
    stub = stub_request(:get, /meetings/).with(query: hash_excluding("created_after")).to_return(body: { items: [] }.to_json)

    described_class.perform_now(connection.id)

    expect(stub).to have_been_requested.twice # verify! + list_meetings
  end

  it "only asks for meetings since the newest synced one afterwards" do
    create(:meeting, synced_at: Time.utc(2026, 10, 1, 9))
    stub_request(:get, /meetings/).with(query: hash_including("limit" => "1")).to_return(body: { items: [] }.to_json)
    list = stub_fathom_meetings(query: { "created_after" => "2026-10-01T09:00:00Z" })

    described_class.perform_now(connection.id)

    expect(list).to have_been_requested
  end

  it "records a Fathom error on the connection without raising" do
    stub_fathom_meetings(status: 401)

    expect { described_class.perform_now(connection.id) }.not_to raise_error
    expect(connection.reload).to have_attributes(status: "error", last_error: "Fathom rejected this API key.")
  end

  it "records and re-raises unexpected errors so the job can retry" do
    stub_fathom_meetings([ fathom_meeting_payload ])
    allow(Fathom::MeetingSync).to receive(:call).and_raise(ActiveRecord::StatementInvalid, "db down")

    expect { described_class.perform_now(connection.id) }.to raise_error(ActiveRecord::StatementInvalid)
    expect(connection.reload).to have_attributes(status: "error", last_error: "Sync failed: db down")
  end

  it "does nothing for a connection that isn't Fathom" do
    other = create(:connection, :clickup)

    expect { described_class.perform_now(other.id) }.not_to raise_error
    expect(a_request(:any, /fathom/)).not_to have_been_made
  end

  it "does not let a webhook push the backfill cutoff past missed meetings",
     pending: "analysis.md #10: the cutoff uses synced_at, which webhooks also bump" do
    create(:meeting, recorded_at: 3.days.ago, synced_at: 1.minute.ago) # arrived by webhook after an outage
    stub_request(:get, /meetings/).with(query: hash_including("limit" => "1")).to_return(body: { items: [] }.to_json)
    list = stub_fathom_meetings(query: { "created_after" => 1.minute.ago.utc.iso8601 })

    described_class.perform_now(connection.id)

    expect(list).not_to have_been_requested
  end
end
