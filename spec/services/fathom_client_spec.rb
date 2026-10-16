RSpec.describe FathomClient do
  subject(:client) { described_class.new("fathom-key") }

  it "verifies the key with the X-Api-Key header" do
    stub = stub_fathom_meetings.with(headers: { "X-Api-Key" => "fathom-key" })

    expect(client.verify!).to be(true)
    expect(stub).to have_been_requested
  end

  it "maps 401 to AuthenticationError" do
    stub_fathom_meetings(status: 401)

    expect { client.verify! }.to raise_error(described_class::AuthenticationError)
  end

  it "includes Fathom's error message in a RequestError" do
    stub_request(:get, /meetings/).to_return(status: 422, body: { error: "destination_url must be https" }.to_json)

    expect { client.verify! }.to raise_error(described_class::RequestError, /422.*must be https/)
  end

  describe "#list_meetings" do
    it "follows the cursor across pages" do
      stub_request(:get, /meetings/).with(query: hash_excluding("cursor"))
        .to_return(body: { items: [ { recording_id: 1 } ], next_cursor: "c2" }.to_json)
      stub_request(:get, /meetings/).with(query: hash_including("cursor" => "c2"))
        .to_return(body: { items: [ { recording_id: 2 } ], next_cursor: nil }.to_json)

      expect(client.list_meetings.map { |m| m["recording_id"] }).to eq([ 1, 2 ])
    end

    it "asks for transcripts, summaries and action items" do
      stub = stub_fathom_meetings(query: { "include_transcript" => "true", "include_summary" => "true", "include_action_items" => "true" })

      client.list_meetings

      expect(stub).to have_been_requested
    end

    it "passes since as created_after" do
      stub = stub_fathom_meetings(query: { "created_after" => "2026-10-01T00:00:00Z" })

      client.list_meetings(since: Time.utc(2026, 10, 1))

      expect(stub).to have_been_requested
    end

    it "accepts the alternate meetings/pagination keys" do
      stub_request(:get, /meetings/).to_return(body: { meetings: [ { id: 3 } ], pagination: { next_cursor: nil } }.to_json)

      expect(client.list_meetings.size).to eq(1)
    end
  end

  describe "rate limiting" do
    it "retries a 429 and then succeeds" do
      stub_request(:get, /meetings/).to_return(
        { status: 429, headers: { "Retry-After" => "2" } },
        { status: 200, body: { items: [] }.to_json }
      )

      expect(client.verify!).to be(true)
      expect(client).to have_received(:sleep).with(2)
    end

    it "gives up after three attempts" do
      stub_request(:get, /meetings/).to_return(status: 429)

      expect { client.verify! }.to raise_error(described_class::RequestError, /rate-limited/)
      expect(client).to have_received(:sleep).twice
    end
  end

  it "creates a webhook for every recording scope and returns its id and secret" do
    stub = stub_fathom_create_webhook(id: "wh_1", secret: "whsec_abc").with { |request|
      body = JSON.parse(request.body)
      body["destination_url"] == "https://app.test/webhooks/fathom" && body["triggered_for"] == described_class::TRIGGERED_FOR &&
        body.values_at("include_transcript", "include_summary", "include_action_items").all?(true)
    }

    expect(client.create_webhook("https://app.test/webhooks/fathom")).to eq(id: "wh_1", secret: "whsec_abc")
    expect(stub).to have_been_requested
  end

  it "deletes a webhook" do
    stub = stub_fathom_delete_webhook("wh_1")

    expect(client.delete_webhook("wh_1")).to be(true)
    expect(stub).to have_been_requested
  end
end
