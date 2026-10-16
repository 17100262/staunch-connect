RSpec.describe "AI Assistant" do
  let(:user) { create(:user) }

  before { sign_in_via_ui(user) }

  it "asks for an Anthropic key first" do
    allow(Rails.application.credentials).to receive(:anthropic_api_key).and_return(nil)

    with_env("ANTHROPIC_API_KEY" => nil) do
      visit ai_conversations_path

      expect(page).to have_text("Add your Anthropic key to start chatting")
      expect(page).to have_field("Message", disabled: true)
    end
  end

  it "asks for a data source when nothing is connected" do
    create(:connection, :anthropic)

    visit ai_conversations_path

    expect(page).to have_text("The assistant needs something to read")
  end

  context "when ready" do
    before do
      create(:connection, :anthropic)
      create(:connection, :fathom)
    end

    it "answers a first question and lists the new chat" do
      stub_anthropic_messages(anthropic_message(anthropic_text("You have **3** meetings this week.")))
      visit ai_conversations_path
      expect(page).to have_text("What do you want to know?")

      fill_in "Message", with: "How many meetings this week?"
      click_on "Send"

      expect(page).to have_css(".msg-user", text: "How many meetings this week?")
      expect(page).to have_css(".msg-ai strong", text: "3")
      within("[aria-label=Chats]") { expect(page).to have_text("How many meetings this week?") }
    end

    it "sends follow-ups with Enter and shows which lookups were used" do
      create(:invoice, month: "2026-09")
      conversation = create(:ai_conversation, user: user, title: "Invoices")
      stub_anthropic_messages(
        anthropic_message(anthropic_tool_use("count_invoices", { "month_from" => "2026-09" })),
        anthropic_message(anthropic_text("There is 1 invoice."))
      )

      visit ai_conversation_path(conversation)
      find_field("Message").fill_in(with: "How many invoices?")
      find_field("Message").send_keys(:enter)

      expect(page).to have_css(".msg-ai", text: "There is 1 invoice.")
      find("summary", text: "Used 1 lookup to answer").click
      expect(page).to have_text("count_invoices")
    end

    it "shows Anthropic errors in the thread" do
      stub_anthropic_error(status: 400, message: "prompt is too long")
      conversation = create(:ai_conversation, user: user)

      visit ai_conversation_path(conversation)
      fill_in "Message", with: "Hi"
      click_on "Send"

      expect(page).to have_text("Something went wrong talking to the assistant")
    end

    it "renames and deletes a chat" do
      conversation = create(:ai_conversation, user: user, title: "Old name")
      visit ai_conversation_path(conversation)

      click_on "More actions"
      click_on "Rename"
      fill_in "Chat name", with: "Acme billing"
      click_on "Save"
      expect(page).to have_css("#t-chat", text: "Acme billing")

      click_on "More actions"
      within("[role=menu][aria-label='Chat actions']") { click_on "Delete" }
      within("[aria-labelledby=del-t]") { click_on "Delete chat" }

      expect(page).to have_current_path(ai_conversations_path)
      expect(page).to have_text("Chat deleted.")
      expect(AiConversation.exists?(conversation.id)).to be(false)
    end

    it "searches past chats" do
      create(:ai_conversation, user: user, title: "Acme billing")
      create(:ai_conversation, user: user, title: "Globex meetings")
      visit ai_conversations_path

      click_on "Search chats"
      fill_in "Search chats", with: "globex"

      within("[aria-label=Chats]") do
        expect(page).to have_no_text("Acme billing")
        expect(page).to have_text("Globex meetings")
      end
    end

    it "sends a question only once when Enter is pressed twice" do
      stub_anthropic_messages(anthropic_message(anthropic_text("Once.")), anthropic_message(anthropic_text("Twice.")))
      conversation = create(:ai_conversation, user: user)

      visit ai_conversation_path(conversation)
      find_field("Message").fill_in(with: "Hi")
      find_field("Message").send_keys(:enter, :enter)

      expect(page).to have_css(".msg-ai", text: "Once.")
      expect(page).to have_no_css(".msg-ai", text: "Twice.")
      expect(conversation.ai_messages.where(role: "user").count).to eq(1)
    end
  end
end
