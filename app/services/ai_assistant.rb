require "anthropic"

# Runs one turn of the AI Assistant chat (AI_ASSISTANT_SPEC.md): the model is only ever allowed
# to answer by calling the read-only tools in TOOL_PROVIDERS — never with freeform SQL, and never
# with a number/fact it didn't get back from a tool call.
class AiAssistant
  class ConfigurationError < StandardError; end

  TOOL_PROVIDERS = [ InvoicingAssistantTools, MeetingAssistantTools ].freeze

  MODEL = "claude-opus-5"
  MAX_TOKENS = 4096
  MAX_TOOL_ITERATIONS = 6

  def initialize(conversation)
    @conversation = conversation
  end

  def ask(question)
    @conversation.ai_messages.create!(role: "user", content: question)
    @conversation.update!(title: question.truncate(60)) if @conversation.title.blank?

    messages = conversation_history
    tool_calls_log = []
    response = request(messages)
    iterations = 0

    while response.stop_reason == :tool_use && iterations < MAX_TOOL_ITERATIONS
      iterations += 1
      messages << { role: "assistant", content: response.content }
      messages << { role: "user", content: tool_results_for(response, tool_calls_log) }
      response = request(messages)
    end

    reply = response.content.select { |block| block.type == :text }.map(&:text).join("\n").presence
    reply ||= "I wasn't able to reach an answer for that — try rephrasing the question."

    @conversation.ai_messages.create!(role: "assistant", content: reply, tool_calls: tool_calls_log)
  end

  private

  def conversation_history
    @conversation.ai_messages.map { |message| { role: message.role, content: message.content } }
  end

  def tools_by_name
    @tools_by_name ||= TOOL_PROVIDERS.each_with_object({}) do |provider, map|
      provider.definitions.each { |definition| map[definition[:name]] = provider }
    end
  end

  def tool_results_for(response, tool_calls_log)
    response.content.select { |block| block.type == :tool_use }.map do |block|
      provider = tools_by_name[block.name]
      result = provider ? provider.call(block.name, block.input) : { error: "Unknown tool '#{block.name}'." }
      tool_calls_log << { "name" => block.name, "input" => block.input, "result" => result }
      { type: "tool_result", tool_use_id: block.id, content: result.to_json }
    end
  end

  def request(messages)
    client.messages.create(
      model: MODEL,
      max_tokens: MAX_TOKENS,
      system: system_prompt,
      tools: TOOL_PROVIDERS.flat_map(&:definitions),
      messages: messages
    )
  end

  # An instance method (not a frozen class constant) so `Date.current` and the asker's identity
  # are resolved fresh on every call, not once at class-load time.
  def system_prompt
    <<~PROMPT
      You are the AI Assistant inside Staunch Connect, a tool that answers questions about invoicing data and Fathom meeting data (summaries, transcripts, and action items).

      You are answering questions for #{@conversation.user.email_address}. When asked about "my action items" or "my meetings", match against this email (or the name it corresponds to) rather than assuming a specific person unless the question already names someone.

      Rules:
      - Only answer using the provided tools. Never invent or estimate a number, quote, or fact yourself.
      - If a tool result is ambiguous (e.g. a project name matched more than one project, a meeting search matched more than 10 meetings, or nothing matched), ask the user to clarify instead of guessing which one they meant.
      - If a tool reports no matching data was found, say so plainly rather than making something up.
      - The only "hours" figure available today is `estimate_hours` — the ClickUp estimate for a task. There is no per-task "hours actually logged" data yet. If a question asks about hours in a way that could mean logged/actual hours, answer using estimated hours but say explicitly that it's the estimate, not logged time.
      - For meetings: start with search_meetings (title/attendee match) or search_meeting_content (semantic/topic match) to find a valid id — never guess one. Use search_meeting_content when the question is about a topic/subject that might not appear in any title or attendee name. Start with get_meeting_summary; only call get_meeting_transcript if the summary doesn't cover what was asked, and only report something wasn't discussed after checking the transcript too. A meeting still processing in Fathom (no summary/transcript yet) must be reported as "still processing," never treated as if nothing was discussed. When a question spans several meetings (e.g. "my action items this week"), use search_action_items in one call rather than looping get_meeting_summary per meeting. Treat a low-relevance search_meeting_content result as inconclusive — say nothing solid was found rather than asserting a weak match is the answer.
      - Every numeric answer should name which invoice(s), project(s), and/or line item(s) it came from; every claim drawn from a meeting should name the meeting (title + date) and include its Fathom link — so any answer can be checked against the source directly.
      - Resolve relative or bare date references (e.g. "last month", "August", "last week's meetings") against today's date, #{Date.current.strftime("%Y-%m-%d")}, assuming the current year unless the question implies otherwise.
    PROMPT
  end

  def client
    @client ||= Anthropic::Client.new(api_key: api_key)
  end

  # The key saved in Settings wins; the environment variable and Rails credentials
  # stay as fallbacks for deployments that configure it there.
  def api_key
    self.class.api_key || raise(ConfigurationError, "Add your Anthropic API key in Settings > Connectors to use the AI Assistant.")
  end

  def self.api_key
    Connection.anthropic_key || ENV["ANTHROPIC_API_KEY"].presence || Rails.application.credentials.anthropic_api_key.presence
  end

  def self.configured?
    api_key.present?
  end
end
