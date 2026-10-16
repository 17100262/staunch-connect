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
      "title ILIKE :term OR EXISTS (SELECT 1 FROM jsonb_array_elements(attendees) AS attendee WHERE attendee->>'name' ILIKE :term OR attendee->>'email' ILIKE :term)",
      term: "%#{sanitize_sql_like(query)}%"
    )
  end

  # At least one action item that is not marked done.
  scope :with_open_action_items, lambda {
    where("EXISTS (SELECT 1 FROM jsonb_array_elements(action_items) AS item WHERE COALESCE((item->>'completed')::boolean, false) = false)")
  }

  scope :recorded_since, ->(time) { where(recorded_at: time..) }

  # Meetings with any of the given people (matched on name or email).
  scope :with_attendees, lambda { |people|
    where(
      "EXISTS (SELECT 1 FROM jsonb_array_elements(attendees) AS attendee WHERE attendee->>'name' IN (:people) OR attendee->>'email' IN (:people))",
      people: Array(people)
    )
  }

  def open_action_items
    Array(action_items).reject { |item| item.is_a?(Hash) && item["completed"] }
  end

  # Attendee display names (falling back to email), in the order Fathom returned them.
  def attendee_names
    Array(attendees).filter_map { |a| a.is_a?(Hash) ? (a["name"].presence || a["email"].presence) : a.presence }
  end

  def processing?
    summary.blank? && transcript.blank?
  end
end
