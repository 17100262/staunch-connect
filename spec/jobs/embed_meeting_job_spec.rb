RSpec.describe EmbedMeetingJob do
  around { |example| with_env("VOYAGE_API_KEY" => "voyage-key") { example.run } }

  it "stores one embedded chunk per summary section and transcript chunk" do
    meeting = create(:meeting)
    stub_voyage_embeddings(vector: voyage_vector(0.5))

    described_class.perform_now(meeting.id)

    chunks = meeting.transcript_chunks.order(:source, :chunk_index)
    expect(chunks.map { |c| [ c.source, c.chunk_index ] }).to eq([ [ "summary", 0 ], [ "summary", 1 ], [ "transcript", 0 ] ])
    expect(chunks.first.embedding.first).to eq(0.5)
  end

  it "replaces previous chunks instead of adding to them" do
    meeting = create(:meeting)
    create(:transcript_chunk, meeting: meeting, source: "summary", chunk_index: 7)
    stub_voyage_embeddings

    described_class.perform_now(meeting.id)

    expect(meeting.transcript_chunks.pluck(:chunk_index)).not_to include(7)
  end

  it "skips meetings still processing or already deleted" do
    processing = create(:meeting, :processing)

    described_class.perform_now(processing.id)
    described_class.perform_now(0)

    expect(a_request(:post, ApiStubs::Voyage::VOYAGE)).not_to have_been_made
  end

  it "explains a missing Voyage key" do
    meeting = create(:meeting)

    with_env("VOYAGE_API_KEY" => nil) do
      allow(Rails.application.credentials).to receive(:voyage_api_key).and_return(nil)

      expect { described_class.perform_now(meeting.id) }.to raise_error(RuntimeError, /VOYAGE_API_KEY/)
    end
  end

  it "keeps existing chunks when embedding fails" do
    meeting = create(:meeting)
    create(:transcript_chunk, meeting: meeting)
    stub_request(:post, ApiStubs::Voyage::VOYAGE).to_return(status: 500)

    expect { described_class.perform_now(meeting.id) }.to raise_error(VoyageClient::RequestError)
    expect(meeting.transcript_chunks.count).to eq(1)
  end
end
