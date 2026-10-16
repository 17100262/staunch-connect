RSpec.describe Fathom::MeetingSync do
  let(:payload) { fathom_meeting_payload }

  it "creates a meeting from a /meetings list entry" do
    meeting = described_class.call(payload)

    expect(meeting).to be_persisted
    expect(meeting).to have_attributes(
      fathom_recording_id: "9001",
      title: "Acme kickoff",
      fathom_url: "https://fathom.video/share/9001",
      recorded_at: Time.zone.parse("2026-10-01T10:00:00Z"),
      duration_minutes: 45,
      summary: "## Purpose\n\nKick off the project.",
      transcript: "Ada Lovelace: Welcome everyone.",
      raw_payload: payload
    )
    expect(meeting.attendees).to eq([ { "name" => "Ada Lovelace", "email" => "ada@staunch.co" } ])
    expect(meeting.action_items.first["description"]).to eq("Send the SOW")
  end

  it "upserts on the recording id instead of duplicating" do
    described_class.call(payload)

    expect { described_class.call(payload.merge("title" => "Renamed")) }.not_to change(Meeting, :count)
    expect(Meeting.sole.title).to eq("Renamed")
  end

  it "reads a webhook payload nested under recording" do
    meeting = described_class.call("recording" => { "id" => 77, "title" => "Nested" }, "summary" => "Plain summary")

    expect(meeting).to have_attributes(fathom_recording_id: "77", title: "Nested", summary: "Plain summary")
  end

  it "ignores payloads with no recording id" do
    expect(described_class.call("title" => "No id")).to be_nil
    expect(Meeting.count).to eq(0)
  end

  it "uses the payload's duration when start or end time is missing" do
    meeting = described_class.call("id" => 5, "duration_minutes" => 12)

    expect(meeting.duration_minutes).to eq(12)
  end

  describe "embedding" do
    it "enqueues an embed job when content arrives" do
      expect { described_class.call(payload) }.to have_enqueued_job(EmbedMeetingJob)
    end

    it "does not re-embed when the content is unchanged" do
      described_class.call(payload)

      expect { described_class.call(payload.merge("title" => "Renamed")) }.not_to have_enqueued_job(EmbedMeetingJob)
    end

    it "re-embeds when the transcript changes" do
      described_class.call(payload)
      changed = payload.merge("transcript" => [ { "text" => "New line." } ])

      expect { described_class.call(changed) }.to have_enqueued_job(EmbedMeetingJob)
    end
  end

  it "keeps the existing summary when a later payload omits it",
     pending: "analysis.md #10: a partial payload overwrites content with nil" do
    described_class.call(payload)
    described_class.call(payload.except("default_summary", "transcript"))

    expect(Meeting.sole.summary).to be_present
  end
end
