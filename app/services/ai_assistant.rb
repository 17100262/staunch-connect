require "anthropic"

# Runs one turn of the AI Assistant chat (AI_ASSISTANT_SPEC.md): the model is only ever allowed
# to answer by calling the read-only tools in InvoicingAssistantTools — never with freeform SQL,
# and never with a number it didn't get back from a tool call.
class AiAssistant
  class ConfigurationError < StandardError; end

  MODEL = "claude-opus-5"
  MAX_TOKENS = 4096
  MAX_TOOL_ITERATIONS = 6

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are the AI Assistant inside Staunch Connect, a tool that answers questions about invoicing data.

    Rules:
    - Only answer using the provided tools. Never invent or estimate a number yourself.
    - If a tool result is ambiguous (e.g. a project name matched more than one project, or matched none), ask the user to clarify instead of guessing which one they meant.
    - If a tool reports no matching data was found, say so plainly rather than making something up.
    - The only "hours" figure available today is `estimate_hours` — the ClickUp estimate for a task. There is no per-task "hours actually logged" data yet. If a question asks about hours in a way that could mean logged/actual hours, answer using estimated hours but say explicitly that it's the estimate, not logged time.
    - Every numeric answer should name which invoice(s), project(s), and/or line item(s) it came from, so it can be checked against the invoice screen directly.
    - Resolve relative or bare date references (e.g. "last month", "August") against today's date, #{Date.current.strftime("%Y-%m-%d")}, assuming the current year unless the question implies otherwise.
  PROMPT

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

  def tool_results_for(response, tool_calls_log)
    response.content.select { |block| block.type == :tool_use }.map do |block|
      result = InvoicingAssistantTools.call(block.name, block.input)
      tool_calls_log << { "name" => block.name, "input" => block.input, "result" => result }
      { type: "tool_result", tool_use_id: block.id, content: result.to_json }
    end
  end

  def request(messages)
    client.messages.create(
      model: MODEL,
      max_tokens: MAX_TOKENS,
      system: SYSTEM_PROMPT,
      tools: InvoicingAssistantTools.definitions,
      messages: messages
    )
  end

  def client
    @client ||= Anthropic::Client.new(api_key: api_key)
  end

  def api_key
    ENV["ANTHROPIC_API_KEY"].presence || Rails.application.credentials.anthropic_api_key ||
      raise(ConfigurationError, "Set ANTHROPIC_API_KEY (or credentials.anthropic_api_key) to use the AI Assistant.")
  end
end
