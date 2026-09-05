class AiMessagesController < ApplicationController
  def create
    @conversation = Current.user.ai_conversations.find(params[:ai_conversation_id])
    question = params[:question].to_s.strip
    existing_ids = @conversation.ai_messages.ids

    if question.present?
      begin
        AiAssistant.new(@conversation).ask(question)
      rescue AiAssistant::ConfigurationError => e
        @conversation.ai_messages.create!(role: "assistant", content: e.message)
      rescue Anthropic::Errors::APIError => e
        @conversation.ai_messages.create!(role: "assistant", content: "Something went wrong talking to the assistant: #{e.message}")
      end
    end

    @new_messages = @conversation.ai_messages.where.not(id: existing_ids).order(:created_at)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to ai_conversation_path(@conversation) }
    end
  end
end
