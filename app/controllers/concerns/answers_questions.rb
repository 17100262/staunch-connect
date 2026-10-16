# Runs one assistant turn for a conversation. Failures are recorded as an
# assistant message so the chat shows them in place instead of raising.
module AnswersQuestions
  extend ActiveSupport::Concern

  private

  def answer_question(conversation, question)
    AiAssistant.new(conversation).ask(question)
  rescue AiAssistant::ConfigurationError => e
    conversation.ai_messages.create!(role: "assistant", content: e.message)
  rescue Anthropic::Errors::APIError => e
    conversation.ai_messages.create!(role: "assistant", content: "Something went wrong talking to the assistant: #{e.message}")
  end
end
