class EnableVectorAndCreateTranscriptChunks < ActiveRecord::Migration[8.1]
  def change
    enable_extension "vector"

    create_table :transcript_chunks do |t|
      t.references :meeting, null: false, foreign_key: true
      t.string :source, null: false
      t.integer :chunk_index, null: false
      t.text :content, null: false
      t.vector :embedding, limit: 1024

      t.timestamps
    end

    add_index :transcript_chunks, [ :meeting_id, :source, :chunk_index ], unique: true,
      name: "index_transcript_chunks_on_meeting_source_chunk"
  end
end
