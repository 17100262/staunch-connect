RSpec.describe "AI chat" do
  let(:user) { create(:user) }

  before do
    sign_in_as(user)
    create(:connection, :anthropic)
  end

  it "shows a new chat" do
    get ai_conversations_path

    expect(response).to have_http_status(:ok)
  end

  it "starts a conversation from the first question" do
    stub_anthropic_messages(anthropic_message(anthropic_text("Hi! Ask me about invoices.")))

    expect { post ai_conversations_path, params: { question: "Hello" } }.to change(user.ai_conversations, :count).by(1)

    conversation = user.ai_conversations.last
    expect(response).to redirect_to(ai_conversation_path(conversation))
    follow_redirect!
    expect(response.body).to include("Hi! Ask me about invoices.")
  end

  it "answers a follow-up as a Turbo Stream" do
    conversation = create(:ai_conversation, user: user)
    stub_anthropic_messages(anthropic_message(anthropic_text("**42** invoices.")))

    post ai_conversation_messages_path(conversation), params: { question: "How many?" }, as: :turbo_stream

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include("How many?", "<strong>42</strong> invoices.")
  end

  it "shows a missing API key as an assistant message instead of failing" do
    Connection.where(source: "anthropic").delete_all
    allow(Rails.application.credentials).to receive(:anthropic_api_key).and_return(nil)
    conversation = create(:ai_conversation, user: user)

    with_env("ANTHROPIC_API_KEY" => nil) do
      post ai_conversation_messages_path(conversation), params: { question: "Hi" }
    end

    expect(conversation.ai_messages.last).to have_attributes(role: "assistant", content: match(/Add your Anthropic API key/))
  end

  it "shows an Anthropic API error as an assistant message" do
    conversation = create(:ai_conversation, user: user)
    stub_anthropic_error(status: 400, message: "prompt is too long")

    post ai_conversation_messages_path(conversation), params: { question: "Hi" }

    expect(conversation.ai_messages.last.content).to match(/Something went wrong talking to the assistant/)
  end

  it "shows a Voyage failure as an assistant message", pending: "analysis.md #11: Voyage errors escape as a 500" do
    conversation = create(:ai_conversation, user: user)
    stub_anthropic_messages(anthropic_message(anthropic_tool_use("search_meeting_content", { "query" => "pricing" })),
                            anthropic_message(anthropic_text("done")))
    stub_request(:post, ApiStubs::Voyage::VOYAGE).to_return(status: 500)

    with_env("VOYAGE_API_KEY" => "vk") { post ai_conversation_messages_path(conversation), params: { question: "pricing?" } }

    expect(response).to redirect_to(ai_conversation_path(conversation))
  end

  it "ignores a blank question" do
    conversation = create(:ai_conversation, user: user)

    expect { post ai_conversation_messages_path(conversation), params: { question: "  " } }.not_to change(AiMessage, :count)
  end

  it "searches chats by title and message content" do
    create(:ai_conversation, user: user, title: "Acme totals")
    create(:ai_message, ai_conversation: create(:ai_conversation, user: user, title: "Other"), content: "What about Globex?")
    create(:ai_conversation, user: user, title: "Unrelated")

    get ai_conversations_path(q: "globex")

    expect(response.body).to include("Other")
    expect(response.body).not_to include("Acme totals", "Unrelated")
  end

  it "renames and deletes a chat" do
    conversation = create(:ai_conversation, user: user)

    patch ai_conversation_path(conversation), params: { ai_conversation: { title: "Renamed" } }
    expect(conversation.reload.title).to eq("Renamed")

    patch ai_conversation_path(conversation), params: { ai_conversation: { title: " " } }
    expect(flash[:alert]).to eq("A chat name can't be blank.")

    delete ai_conversation_path(conversation)
    expect(AiConversation.exists?(conversation.id)).to be(false)
  end

  describe "another user's chat" do
    let(:other) { create(:ai_conversation, title: "Private chat") }

    it "can't be read, renamed, deleted or messaged" do
      get ai_conversation_path(other)
      expect(response).to have_http_status(:not_found)

      patch ai_conversation_path(other), params: { ai_conversation: { title: "Mine now" } }
      expect(response).to have_http_status(:not_found)

      delete ai_conversation_path(other)
      expect(response).to have_http_status(:not_found)

      post ai_conversation_messages_path(other), params: { question: "Hi" }
      expect(response).to have_http_status(:not_found)

      expect(other.reload.title).to eq("Private chat")
    end

    it "doesn't show up in the chat list" do
      other

      get ai_conversations_path

      expect(response.body).not_to include("Private chat")
    end
  end
end
