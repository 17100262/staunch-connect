class AiConversationsController < ApplicationController
  def index
    @conversations = Current.user.ai_conversations.order(updated_at: :desc)
  end

  def show
    @conversation = Current.user.ai_conversations.find(params[:id])
  end

  def create
    @conversation = Current.user.ai_conversations.create!
    redirect_to ai_conversation_path(@conversation)
  end

  def destroy
    Current.user.ai_conversations.find(params[:id]).destroy
    redirect_to ai_conversations_path, notice: "Conversation deleted."
  end
end
