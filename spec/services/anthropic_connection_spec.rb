RSpec.describe AnthropicConnection do
  it "verifies a working key with a cheap models call" do
    stub = stub_anthropic_models.with(headers: { "x-api-key" => "sk-ant-good" })

    expect(described_class.new("sk-ant-good").verify!).to be(true)
    expect(stub).to have_been_requested
  end

  it "raises AuthenticationError for a rejected key" do
    stub_anthropic_models(status: 401)

    expect { described_class.new("sk-ant-bad").verify! }.to raise_error(described_class::AuthenticationError, /rejected/)
  end

  it "raises RequestError when Anthropic can't be reached" do
    stub_request(:get, ApiStubs::Anthropic::MODELS_URL).to_return(status: 500, body: { type: "error", error: { type: "api_error", message: "down" } }.to_json)

    expect { described_class.new("sk-ant").verify! }.to raise_error(described_class::RequestError)
  end
end
