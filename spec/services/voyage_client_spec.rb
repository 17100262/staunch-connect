RSpec.describe VoyageClient do
  subject(:client) { described_class.new("voyage-key") }

  it "embeds documents with input_type document and returns vectors in input order" do
    stub_request(:post, ApiStubs::Voyage::VOYAGE)
      .with(headers: { "Authorization" => "Bearer voyage-key" },
            body: hash_including("input" => [ "a", "b" ], "input_type" => "document", "model" => "voyage-4", "output_dimension" => 1024))
      .to_return(body: { data: [ { index: 1, embedding: [ 2 ] }, { index: 0, embedding: [ 1 ] } ] }.to_json)

    expect(client.embed_documents([ "a", "b" ])).to eq([ [ 1 ], [ 2 ] ])
  end

  it "embeds a query with input_type query" do
    stub = stub_voyage_embeddings.with(body: hash_including("input_type" => "query"))

    expect(client.embed_query("pricing").size).to eq(1024)
    expect(stub).to have_been_requested
  end

  it "maps 401 to AuthenticationError and other failures to RequestError" do
    stub_request(:post, ApiStubs::Voyage::VOYAGE).to_return({ status: 401 }, { status: 500 })

    expect { client.embed_query("x") }.to raise_error(described_class::AuthenticationError)
    expect { client.embed_query("x") }.to raise_error(described_class::RequestError, /500/)
  end

  it "retries rate limits, then gives up after three attempts" do
    stub_request(:post, ApiStubs::Voyage::VOYAGE).to_return(status: 429)

    expect { client.embed_query("x") }.to raise_error(described_class::RequestError, /rate-limited/)
    expect(client).to have_received(:sleep).twice
  end
end
