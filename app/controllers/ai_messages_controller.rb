class AiMessagesController < ApplicationController
  def create
    conversation = Current.user.ai_conversations.find(params[:ai_conversation_id])
    question = params[:question].to_s.strip

    if question.present?
      begin
        AiAssistant.new(conversation).ask(question)
      rescue AiAssistant::ConfigurationError => e
        conversation.ai_messages.create!(role: "assistant", content: e.message)
      rescue Anthropic::Errors::APIError => e
        conversation.ai_messages.create!(role: "assistant", content: "Something went wrong talking to the assistant: #{e.message}")
      end
    end

    redirect_to ai_conversation_path(conversation)
  end
end
