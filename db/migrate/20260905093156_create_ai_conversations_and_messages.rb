class CreateAiConversationsAndMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_conversations do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title

      t.timestamps
    end

    create_table :ai_messages do |t|
      t.references :ai_conversation, null: false, foreign_key: true
      t.string :role, null: false
      t.text :content, null: false
      t.jsonb :tool_calls, null: false, default: []

      t.timestamps
    end
  end
end
