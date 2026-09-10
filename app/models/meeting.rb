class Meeting < ApplicationRecord
  has_many :transcript_chunks, dependent: :destroy

  validates :fathom_recording_id, presence: true, uniqueness: true

  # Matches on title or any attendee's name (attendees is a jsonb array of
  # {"name" => ..., "email" => ...} objects — see Fathom::MeetingSync) —
  # done at the DB level via jsonb_array_elements rather than loading every
  # row into Ruby, so this stays cheap as the table grows past a page.
  def self.search(query)
    return all if query.blank?

    where(
      "title ILIKE :term OR EXISTS (SELECT 1 FROM jsonb_array_elements(attendees) AS attendee WHERE attendee->>'name' ILIKE :term)",
      term: "%#{query}%"
    )
  end

  def processing?
    summary.blank? && transcript.blank?
  end
end
