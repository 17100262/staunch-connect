# Splits a meeting's summary/transcript into embeddable chunks — by topic segment (markdown
# section) for the summary, by speaker turn for the transcript — per FATHOM_INTEGRATION_SPEC.md's
# guidance to chunk before embedding rather than treat a whole meeting as one block.
class MeetingChunker
  TRANSCRIPT_CHUNK_CHAR_BUDGET = 3200

  def self.call(meeting)
    chunks = []
    chunks.concat(chunk_summary(meeting.summary)) if meeting.summary.present?
    chunks.concat(chunk_transcript(meeting.transcript)) if meeting.transcript.present?
    chunks
  end

  def self.chunk_summary(summary)
    sections = summary.split(/(?=^## )/).map(&:strip).reject(&:blank?)
    sections = [ summary.strip ] if sections.size <= 1

    sections.each_with_index.map { |content, index| { source: "summary", chunk_index: index, content: content } }
  end

  def self.chunk_transcript(transcript)
    lines = transcript.split("\n").reject(&:blank?)
    texts = []
    buffer = []
    buffer_size = 0

    lines.each do |line|
      buffer << line
      buffer_size += line.length

      if buffer_size >= TRANSCRIPT_CHUNK_CHAR_BUDGET
        texts << buffer.join("\n")
        buffer = []
        buffer_size = 0
      end
    end
    texts << buffer.join("\n") if buffer.any?

    texts.each_with_index.map { |content, index| { source: "transcript", chunk_index: index, content: content } }
  end
end
