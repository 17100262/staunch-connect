RSpec.describe FathomWebhookVerifier do
  subject(:verifier) { described_class.new(FathomWebhookHelpers::WEBHOOK_SECRET) }

  let(:body) { { recording_id: 1 }.to_json }
  let(:headers) { signed_fathom_headers(body) }

  def verify(headers: self.headers, raw_body: body)
    verifier.verify!(id: headers["webhook-id"], timestamp: headers["webhook-timestamp"],
                     signature_header: headers["webhook-signature"], raw_body: raw_body)
  end

  it "accepts a correctly signed delivery" do
    expect(verify).to be(true)
  end

  it "rejects a tampered body" do
    expect { verify(raw_body: body.sub("1", "2")) }.to raise_error(described_class::InvalidSignature, /did not match/)
  end

  it "rejects a delivery signed with another secret" do
    other = signed_fathom_headers(body, secret: "whsec_#{Base64.strict_encode64('another-key')}")

    expect { verify(headers: other) }.to raise_error(described_class::InvalidSignature)
  end

  it "rejects a reused signature under a different message id" do
    expect { verify(headers: headers.merge("webhook-id" => "msg_other")) }.to raise_error(described_class::InvalidSignature)
  end

  it "rejects stale and future timestamps beyond five minutes" do
    expect { verify(headers: signed_fathom_headers(body, timestamp: 6.minutes.ago.to_i)) }
      .to raise_error(described_class::InvalidSignature, /tolerance/)
    expect { verify(headers: signed_fathom_headers(body, timestamp: 6.minutes.from_now.to_i)) }
      .to raise_error(described_class::InvalidSignature, /tolerance/)
  end

  it "accepts a timestamp inside the tolerance" do
    expect(verify(headers: signed_fathom_headers(body, timestamp: 4.minutes.ago.to_i))).to be(true)
  end

  it "accepts a header carrying several signatures when one matches" do
    multi = headers.merge("webhook-signature" => "v1,bm90LWl0 #{headers['webhook-signature']}")

    expect(verify(headers: multi)).to be(true)
  end

  it "rejects missing headers" do
    expect { verify(headers: headers.except("webhook-signature")) }
      .to raise_error(described_class::InvalidSignature, /Missing/)
  end

  it "works with a secret that has no whsec_ prefix" do
    plain = described_class.new(FathomWebhookHelpers::WEBHOOK_SECRET.delete_prefix("whsec_"))

    expect(plain.verify!(id: headers["webhook-id"], timestamp: headers["webhook-timestamp"],
                         signature_header: headers["webhook-signature"], raw_body: body)).to be(true)
  end
end
