RSpec.describe Connection do
  subject { build(:connection) }

  it { is_expected.to validate_presence_of(:credential) }
  it { is_expected.to validate_inclusion_of(:source).in_array(Connection::SOURCES) }

  it "allows only one connection per source" do
    create(:connection, :clickup)

    expect(build(:connection, :clickup)).not_to be_valid
  end

  it "defaults to disconnected" do
    expect(described_class.new.status).to eq("disconnected")
  end

  it "exposes the status enum" do
    expect(build(:connection, :syncing)).to be_syncing
  end

  it "encrypts credentials, access tokens and webhook secrets at rest" do
    connection = create(:connection, :fathom, credential: "secret-key", access_token: "access-123")

    raw = described_class.connection.select_one("SELECT credential, access_token, webhook_secret FROM connections WHERE id = #{connection.id}")

    expect(raw.values).to all(be_present)
    expect(raw["credential"]).not_to include("secret-key")
    expect(raw["access_token"]).not_to include("access-123")
    expect(connection.reload.credential).to eq("secret-key")
  end

  describe ".anthropic_key" do
    it "returns the key of a connected Anthropic connection" do
      create(:connection, :anthropic, credential: "sk-ant-live")

      expect(described_class.anthropic_key).to eq("sk-ant-live")
    end

    it "ignores an Anthropic connection that isn't connected" do
      create(:connection, :anthropic, :errored)

      expect(described_class.anthropic_key).to be_nil
    end

    it "is nil without one" do
      expect(described_class.anthropic_key).to be_nil
    end
  end
end
