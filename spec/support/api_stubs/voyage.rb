module ApiStubs
  module Voyage
    VOYAGE = "https://api.voyageai.com/v1/embeddings".freeze

    def voyage_vector(seed = 0.01)
      Array.new(1024, seed)
    end

    # Returns one embedding per input text, in input order.
    def stub_voyage_embeddings(vector: voyage_vector, status: 200)
      stub_request(:post, VOYAGE).to_return do |request|
        inputs = JSON.parse(request.body)["input"]
        { status: status, headers: { "Content-Type" => "application/json" },
          body: { data: inputs.each_index.map { |i| { index: i, embedding: vector } } }.to_json }
      end
    end
  end
end

RSpec.configure { |config| config.include ApiStubs::Voyage }
