class AiConversationsController < ApplicationController
  include AnswersQuestions

  before_action :load_chat_list, only: %i[index show]
  before_action :load_sources, only: %i[index show]

  # A blank new chat. The conversation is created when the first question is sent.
  def index
  end

  def show
    @conversation = Current.user.ai_conversations.find(params[:id])
  end

  def create
    @conversation = Current.user.ai_conversations.create!
    question = params[:question].to_s.strip
    answer_question(@conversation, question) if question.present?
    redirect_to ai_conversation_path(@conversation)
  end

  def update
    conversation = Current.user.ai_conversations.find(params[:id])
    title = params.dig(:ai_conversation, :title).to_s.strip

    if title.present? && conversation.update(title: title.truncate(120))
      redirect_to ai_conversation_path(conversation), notice: "Chat renamed."
    else
      redirect_to ai_conversation_path(conversation), alert: "A chat name can't be blank."
    end
  end

  def destroy
    Current.user.ai_conversations.find(params[:id]).destroy
    redirect_to ai_conversations_path, notice: "Chat deleted."
  end

  private

  def load_chat_list
    @query = params[:q].to_s.strip
    scope = Current.user.ai_conversations.order(updated_at: :desc)

    if @query.present?
      like = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
      scope = scope.where(id: AiMessage.where("content ILIKE ?", like).select(:ai_conversation_id))
                   .or(scope.where("ai_conversations.title ILIKE ?", like))
    end

    @conversations = scope
  end

  # The assistant has nothing to answer with when no source is connected.
  def load_sources
    @sources_connected = helpers.assistant_source_names.any?
    @ai_ready = AiAssistant.configured?
  end
end
