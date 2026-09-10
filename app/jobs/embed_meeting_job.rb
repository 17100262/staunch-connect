# Turns a synced meeting's summary/transcript into embedded TranscriptChunk rows, so
# MeetingAssistantTools#search_meeting_content can find it by topic, not just by title/attendee.
# Enqueued from Fathom::MeetingSync right after a meeting's summary/transcript actually changes —
# runs in the background since embedding is a network call and shouldn't hold up a sync/webhook.
class EmbedMeetingJob < ApplicationJob
  queue_as :default

  def perform(meeting_id)
    meeting = Meeting.find_by(id: meeting_id)
    return if meeting.nil? || meeting.processing?

    chunks = MeetingChunker.call(meeting)
    return if chunks.empty?

    embeddings = voyage_client.embed_documents(chunks.map { |chunk| chunk[:content] })

    meeting.transcript_chunks.destroy_all
    chunks.each_with_index do |chunk, index|
      meeting.transcript_chunks.create!(chunk.merge(embedding: embeddings[index]))
    end
  end

  private

  def voyage_client
    api_key = ENV["VOYAGE_API_KEY"].presence || Rails.application.credentials.voyage_api_key
    raise "Set VOYAGE_API_KEY (or credentials.voyage_api_key) to embed meeting content." if api_key.blank?

    VoyageClient.new(api_key)
  end
end
