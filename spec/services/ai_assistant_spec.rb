RSpec.describe AiAssistant do
  let(:user) { create(:user, email_address: "ada@staunch.co") }
  let(:conversation) { create(:ai_conversation, user: user, title: nil) }

  before { create(:connection, :anthropic, credential: "sk-ant-test") }

  def sent_bodies
    bodies = []
    expect(a_request(:post, ApiStubs::Anthropic::MESSAGES_URL).with { |req| bodies << JSON.parse(req.body) }).to have_been_made.at_least_once
    bodies
  end

  it "answers a simple question and saves both turns" do
    stub_anthropic_messages(anthropic_message(anthropic_text("Hello Ada.")))

    reply = described_class.new(conversation).ask("Hi there")

    expect(reply).to have_attributes(role: "assistant", content: "Hello Ada.", tool_calls: [])
    expect(conversation.ai_messages.pluck(:role, :content)).to eq([ [ "user", "Hi there" ], [ "assistant", "Hello Ada." ] ])
  end

  it "titles a new conversation from the first question" do
    stub_anthropic_messages(anthropic_message(anthropic_text("ok")))

    question = "How much did we bill Acme in September across every single one of their projects?"
    described_class.new(conversation).ask(question)

    expect(conversation.reload.title).to eq(question.truncate(60))
    expect(conversation.title.length).to eq(60)
  end

  it "sends the model, tools, system prompt and full history with the configured key" do
    create(:ai_message, ai_conversation: conversation, content: "Earlier question")
    create(:ai_message, :assistant, ai_conversation: conversation, content: "Earlier answer")
    stub_anthropic_messages(anthropic_message(anthropic_text("ok")))

    described_class.new(conversation).ask("Follow-up")

    body = sent_bodies.first
    expect(body).to include("model" => described_class::MODEL, "max_tokens" => described_class::MAX_TOKENS)
    expect(body["system"]).to include("ada@staunch.co", Date.current.iso8601)
    expect(body["tools"].map { |t| t["name"] }).to include("list_invoices", "search_meetings")
    expect(body["messages"].map { |m| m["content"] }).to eq([ "Earlier question", "Earlier answer", "Follow-up" ])
    expect(a_request(:post, ApiStubs::Anthropic::MESSAGES_URL).with(headers: { "x-api-key" => "sk-ant-test" })).to have_been_made
  end

  it "runs the tool the model asks for and sends the result back" do
    create(:invoice, :with_line_items, month: "2026-09")
    stub_anthropic_messages(
      anthropic_message(anthropic_tool_use("count_invoices", { "month_from" => "2026-09" }, id: "toolu_1")),
      anthropic_message(anthropic_text("You have 1 invoice."))
    )

    reply = described_class.new(conversation).ask("How many invoices?")

    expect(reply.content).to eq("You have 1 invoice.")
    expect(reply.tool_calls).to eq([ { "name" => "count_invoices", "input" => { "month_from" => "2026-09" }, "result" => { "count" => 1 } } ])

    tool_result = sent_bodies.last["messages"].last["content"].first
    expect(tool_result).to include("type" => "tool_result", "tool_use_id" => "toolu_1", "content" => { count: 1 }.to_json)
  end

  it "reports an unknown tool to the model instead of crashing" do
    stub_anthropic_messages(
      anthropic_message(anthropic_tool_use("delete_everything", {})),
      anthropic_message(anthropic_text("Sorry."))
    )

    reply = described_class.new(conversation).ask("Do it")

    expect(reply.tool_calls.first["result"]).to eq("error" => "Unknown tool 'delete_everything'.")
  end

  it "stops after the tool-iteration cap and gives a fallback answer" do
    looping = anthropic_message(anthropic_tool_use("count_invoices", {}))
    stub_anthropic_messages(*Array.new(described_class::MAX_TOOL_ITERATIONS + 1, looping))

    reply = described_class.new(conversation).ask("Loop forever")

    expect(a_request(:post, ApiStubs::Anthropic::MESSAGES_URL)).to have_been_made.times(described_class::MAX_TOOL_ITERATIONS + 1)
    expect(reply.content).to match(/wasn't able to reach an answer/)
  end

  describe "API key" do
    before do
      Connection.where(source: "anthropic").delete_all
      allow(Rails.application.credentials).to receive(:anthropic_api_key).and_return(nil)
    end

    it "falls back to ANTHROPIC_API_KEY" do
      with_env("ANTHROPIC_API_KEY" => "sk-ant-env") do
        expect(described_class.api_key).to eq("sk-ant-env")
        expect(described_class).to be_configured
      end
    end

    it "prefers the key saved in Settings over the environment" do
      create(:connection, :anthropic, credential: "sk-ant-settings")

      with_env("ANTHROPIC_API_KEY" => "sk-ant-env") { expect(described_class.api_key).to eq("sk-ant-settings") }
    end

    it "raises a ConfigurationError that tells the user where to add one" do
      with_env("ANTHROPIC_API_KEY" => nil) do
        expect(described_class).not_to be_configured
        expect { described_class.new(conversation).ask("Hi") }.to raise_error(described_class::ConfigurationError, /Settings > Connectors/)
      end
    end
  end
end
