class CreateMeetings < ActiveRecord::Migration[8.1]
  def change
    create_table :meetings do |t|
      t.string :fathom_recording_id, null: false
      t.string :title
      t.string :fathom_url
      t.datetime :recorded_at
      t.integer :duration_minutes
      t.jsonb :attendees, null: false, default: []
      t.text :summary
      t.text :transcript
      t.jsonb :action_items, null: false, default: []
      t.jsonb :raw_payload
      t.datetime :synced_at

      t.timestamps
    end

    add_index :meetings, :fathom_recording_id, unique: true
  end
end
