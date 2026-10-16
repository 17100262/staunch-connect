RSpec.describe TranscriptChunk do
  subject { build(:transcript_chunk) }

  it { is_expected.to belong_to(:meeting) }
  it { is_expected.to validate_inclusion_of(:source).in_array(%w[summary transcript]) }

  it "orders chunks by cosine distance to a query embedding" do
    near = create(:transcript_chunk, embedding: Array.new(1023, 0.0) + [ 1.0 ])
    far = create(:transcript_chunk, embedding: [ 1.0 ] + Array.new(1023, 0.0))

    query = Array.new(1023, 0.0) + [ 0.9 ]
    results = described_class.nearest_neighbors(:embedding, query, distance: "cosine").first(2)

    expect(results).to eq([ near, far ])
    expect(results.first.neighbor_distance).to be_within(0.001).of(0)
  end
end
