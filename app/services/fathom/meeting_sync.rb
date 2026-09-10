module Fathom
  # Upserts one `meetings` row from a Fathom payload — used by both the manual
  # "Sync Now" path (a `/meetings` list entry) and the webhook path (a
  # new-meeting-content-ready delivery) so there's exactly one place that
  # decides how a Fathom payload becomes a Meeting. Keyed on Fathom's own
  # recording id, so re-syncing or a redelivered webhook never duplicates a row.
  #
  # Field names below are confirmed against a real `GET /meetings` response
  # (recording_id, title, share_url, recording_start_time/end_time,
  # calendar_invitees, transcript, default_summary, action_items) — the
  # webhook delivery's exact shape is still unconfirmed (FATHOM_INTEGRATION_SPEC.md
  # Section 4/7), so a couple of alternate/nested key names are kept as
  # fallbacks. `raw_payload` keeps the untouched response regardless, so
  # nothing is lost if the webhook shape turns out to differ.
  class MeetingSync
    def self.call(payload)
      recording = payload["recording"] || payload["meeting"] || payload
      recording_id = recording["recording_id"] || recording["id"] || payload["id"]
      return nil if recording_id.blank?

      meeting = Meeting.find_or_initialize_by(fathom_recording_id: recording_id.to_s)
      meeting.assign_attributes(
        title: recording["title"] || recording["meeting_title"],
        fathom_url: recording["share_url"] || recording["url"] || payload["url"],
        recorded_at: recording["recording_start_time"] || recording["scheduled_start_time"] || recording["recorded_at"],
        duration_minutes: duration_minutes_for(recording),
        attendees: recording["calendar_invitees"] || recording["attendees"] || recording["invitees"] || [],
        summary: extract_text(recording["default_summary"] || payload["summary"] || recording["summary"]),
        transcript: extract_text(payload["transcript"] || recording["transcript"]),
        action_items: payload["action_items"] || recording["action_items"] || [],
        raw_payload: payload,
        synced_at: Time.current
      )
      meeting.save!
      EmbedMeetingJob.perform_later(meeting.id) if meeting.saved_change_to_summary? || meeting.saved_change_to_transcript?
      meeting
    end

    def self.duration_minutes_for(recording)
      start = recording["recording_start_time"]
      finish = recording["recording_end_time"]
      return recording["duration_minutes"] || recording["duration"] if start.blank? || finish.blank?

      ((Time.parse(finish) - Time.parse(start)) / 60.0).round
    rescue ArgumentError, TypeError
      nil
    end

    # Confirmed against a real payload: `default_summary` is
    # `{"template_name" => ..., "markdown_formatted" => "## Meeting Purpose\n\n..."}`,
    # and `transcript` is an array of `{"text" => ..., "speaker" => {"display_name" => ...}, "timestamp" => ...}`
    # segments — not the generic "text"/"markdown" keys this originally guessed.
    def self.extract_text(value)
      case value
      when String then value
      when Hash then value["markdown_formatted"] || value["text"] || value["markdown"]
      when Array then value.map { |item| transcript_line(item) }.join("\n")
      end
    end

    def self.transcript_line(item)
      return item.to_s unless item.is_a?(Hash)

      speaker = item.dig("speaker", "display_name")
      speaker.present? ? "#{speaker}: #{item['text']}" : item["text"]
    end
  end
end
