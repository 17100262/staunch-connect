module ApiStubs
  module Fathom
    FATHOM = "https://api.fathom.ai/external/v1".freeze

    def stub_fathom_meetings(items = [], status: 200, next_cursor: nil, query: nil)
      request = stub_request(:get, %r{\A#{Regexp.escape(FATHOM)}/meetings(\?.*)?\z})
      request = request.with(query: hash_including(query)) if query
      request.to_return(status: status, body: { items: items, next_cursor: next_cursor }.to_json,
                        headers: { "Content-Type" => "application/json" })
    end

    def stub_fathom_create_webhook(id: "wh_new", secret: FathomWebhookHelpers::WEBHOOK_SECRET, status: 201, error: nil)
      body = error ? { error: error } : { id: id, secret: secret }
      stub_request(:post, "#{FATHOM}/webhooks").to_return(status: status, body: body.to_json,
                                                          headers: { "Content-Type" => "application/json" })
    end

    def stub_fathom_delete_webhook(id = "wh_123", status: 204)
      stub_request(:delete, "#{FATHOM}/webhooks/#{id}").to_return(status: status, body: "")
    end

    # A /meetings list entry in the shape Fathom::MeetingSync was confirmed against.
    def fathom_meeting_payload(recording_id: 9001, title: "Acme kickoff", summary: "## Purpose\n\nKick off the project.",
                               transcript: [ { "text" => "Welcome everyone.", "speaker" => { "display_name" => "Ada Lovelace" } } ])
      {
        "recording_id" => recording_id,
        "title" => title,
        "share_url" => "https://fathom.video/share/#{recording_id}",
        "recording_start_time" => "2026-10-01T10:00:00Z",
        "recording_end_time" => "2026-10-01T10:45:00Z",
        "calendar_invitees" => [ { "name" => "Ada Lovelace", "email" => "ada@staunch.co" } ],
        "default_summary" => summary && { "template_name" => "General", "markdown_formatted" => summary },
        "transcript" => transcript,
        "action_items" => [ { "description" => "Send the SOW", "completed" => false } ]
      }
    end
  end
end

RSpec.configure { |config| config.include ApiStubs::Fathom }
