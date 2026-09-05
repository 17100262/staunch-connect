class AiConversation < ApplicationRecord
  belongs_to :user
  has_many :ai_messages, -> { order(:created_at) }, dependent: :destroy
end
