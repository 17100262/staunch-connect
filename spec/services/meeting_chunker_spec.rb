RSpec.describe MeetingChunker do
  it "splits the summary into one chunk per ## section" do
    meeting = build(:meeting, summary: "## Purpose\n\nPlan.\n\n## Takeaways\n\nShip.", transcript: nil)

    expect(described_class.call(meeting)).to eq([
      { source: "summary", chunk_index: 0, content: "## Purpose\n\nPlan." },
      { source: "summary", chunk_index: 1, content: "## Takeaways\n\nShip." }
    ])
  end

  it "keeps a summary without sections as a single chunk" do
    chunks = described_class.chunk_summary("Just one paragraph.")

    expect(chunks).to eq([ { source: "summary", chunk_index: 0, content: "Just one paragraph." } ])
  end

  it "groups transcript lines into chunks within the character budget" do
    line = "Ada: #{'x' * 1000}"
    chunks = described_class.chunk_transcript(([ line ] * 7).join("\n"))

    expect(chunks.map { |c| c[:chunk_index] }).to eq([ 0, 1 ])
    expect(chunks.first[:content].lines.count).to eq(4)
    expect(chunks.last[:content].lines.count).to eq(3)
    expect(chunks).to all(include(source: "transcript"))
  end

  it "drops blank transcript lines" do
    chunks = described_class.chunk_transcript("Ada: hi\n\n\nGrace: hello\n")

    expect(chunks.first[:content]).to eq("Ada: hi\nGrace: hello")
  end

  it "returns nothing for a meeting still processing" do
    expect(described_class.call(build(:meeting, :processing))).to eq([])
  end

  it "chunks both summary and transcript" do
    sources = described_class.call(build(:meeting)).map { |c| c[:source] }

    expect(sources).to include("summary", "transcript")
  end
end
