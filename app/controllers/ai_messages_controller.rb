class AiMessagesController < ApplicationController
  include AnswersQuestions

  def create
    @conversation = Current.user.ai_conversations.find(params[:ai_conversation_id])
    question = params[:question].to_s.strip
    existing_ids = @conversation.ai_messages.ids

    answer_question(@conversation, question) if question.present?

    @new_messages = @conversation.ai_messages.where.not(id: existing_ids).order(:created_at)
    @conversations = Current.user.ai_conversations.order(updated_at: :desc)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to ai_conversation_path(@conversation) }
    end
  end
end
