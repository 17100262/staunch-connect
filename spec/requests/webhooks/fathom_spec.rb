RSpec.describe "Fathom webhook" do
  let(:body) { fathom_meeting_payload(recording_id: 4242, title: "Live meeting").to_json }

  def deliver(body = self.body, headers: signed_fathom_headers(body))
    post webhooks_fathom_path, params: body, headers: headers.merge("Content-Type" => "application/json")
  end

  context "with Fathom connected" do
    let!(:connection) { create(:connection, :fathom, last_error: "old error") }

    it "accepts a signed delivery without a session or CSRF token and upserts the meeting" do
      deliver

      expect(response).to have_http_status(:ok)
      expect(Meeting.find_by(fathom_recording_id: "4242").title).to eq("Live meeting")
      expect(connection.reload).to have_attributes(last_error: nil, last_used_at: be_present)
    end

    it "is idempotent across redeliveries" do
      2.times { deliver }

      expect(Meeting.where(fathom_recording_id: "4242").count).to eq(1)
    end

    it "rejects a bad signature" do
      deliver(headers: signed_fathom_headers(body, secret: "whsec_#{Base64.strict_encode64('wrong')}"))

      expect(response).to have_http_status(:unauthorized)
      expect(Meeting.count).to eq(0)
    end

    it "rejects a replay outside the time window" do
      deliver(headers: signed_fathom_headers(body, timestamp: 10.minutes.ago.to_i))

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a correctly signed body that isn't JSON" do
      deliver("not json")

      expect(response).to have_http_status(:bad_request)
    end
  end

  it "404s when Fathom isn't connected" do
    deliver

    expect(response).to have_http_status(:not_found)
  end
end
