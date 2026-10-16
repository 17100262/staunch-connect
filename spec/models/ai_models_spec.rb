RSpec.describe AiConversation do
  it { is_expected.to belong_to(:user) }
  it { is_expected.to have_many(:ai_messages).dependent(:destroy) }

  it "returns messages oldest first" do
    conversation = create(:ai_conversation)
    later = create(:ai_message, ai_conversation: conversation, created_at: 1.minute.ago)
    earlier = create(:ai_message, ai_conversation: conversation, created_at: 1.hour.ago)

    expect(conversation.ai_messages).to eq([ earlier, later ])
  end
end

RSpec.describe AiMessage do
  subject { build(:ai_message) }

  it { is_expected.to belong_to(:ai_conversation) }
  it { is_expected.to validate_presence_of(:content) }
  it { is_expected.to validate_inclusion_of(:role).in_array(%w[user assistant]) }
end
