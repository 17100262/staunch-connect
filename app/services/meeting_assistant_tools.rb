# The AI Assistant's fixed query surface over meeting data (AI_ASSISTANT_SPEC.md Phase B).
# Mirrors InvoicingAssistantTools' conventions exactly: read-only, named/validated arguments only,
# and every discovery tool (search_meetings/search_action_items/search_meeting_content) is the only
# way to get an `id` — get_meeting_summary/get_meeting_transcript never accept a guessed one.
class MeetingAssistantTools
  MAX_MEETING_RESULTS = 10
  MAX_ACTION_ITEM_MEETINGS = 50
  MAX_ACTION_ITEMS = 50
  MAX_CONTENT_RESULTS = 8

  class << self
    def definitions
      [
        {
          name: "search_meetings",
          description: "Search meetings by title or attendee name, optionally narrowed by a recorded date range. Only matches titles/attendee names — for a topic/content question ('which meeting discussed X'), use search_meeting_content instead. Returns up to 10 matches; if more matched, ask the user to narrow down rather than guessing which one they meant.",
          input_schema: {
            type: "object",
            properties: {
              query: { type: "string", description: "Matches against the meeting title or any attendee's name. Omit to list recent meetings." },
              date_from: date_property("Earliest recorded date to include (inclusive)."),
              date_to: date_property("Latest recorded date to include (inclusive).")
            },
            additionalProperties: false
          }
        },
        {
          name: "get_meeting_summary",
          description: "Get one meeting's summary, attendees, and action items. Requires an id from a prior search_meetings/search_action_items/search_meeting_content call — never guess one.",
          input_schema: {
            type: "object",
            properties: { id: { type: "integer", description: "A meeting id returned by a prior search call." } },
            required: %w[id],
            additionalProperties: false
          }
        },
        {
          name: "get_meeting_transcript",
          description: "Get a meeting's full transcript. Only call this after get_meeting_summary if the summary doesn't answer the question — transcripts can be long. Requires an id from a prior search call.",
          input_schema: {
            type: "object",
            properties: { id: { type: "integer", description: "A meeting id returned by a prior search call." } },
            required: %w[id],
            additionalProperties: false
          }
        },
        {
          name: "search_action_items",
          description: "Find action items across meetings matching a title/attendee query and/or date range and/or assignee — use this instead of calling get_meeting_summary once per meeting when a question spans several meetings (e.g. 'my action items this week').",
          input_schema: {
            type: "object",
            properties: {
              query: { type: "string", description: "Matches against meeting title or attendee name, same as search_meetings. Omit to consider all meetings in range." },
              date_from: date_property("Earliest recorded date to include (inclusive)."),
              date_to: date_property("Latest recorded date to include (inclusive)."),
              assignee: { type: "string", description: "Only include action items assigned to someone whose name or email matches this (case-insensitive substring)." },
              completed: { type: "boolean", description: "true = only completed items, false = only open items. Omit to include both." }
            },
            additionalProperties: false
          }
        },
        {
          name: "search_meeting_content",
          description: "Semantic search across meeting summaries and transcripts by topic/content — finds a meeting even if the exact words in your query never appear in its title or attendee names. Use this before assuming search_meetings covers a 'which meeting discussed X' style question.",
          input_schema: {
            type: "object",
            properties: {
              query: { type: "string", description: "What to search for, in natural language (e.g. 'AWS IAM permissions', 'pricing concerns')." },
              date_from: date_property("Earliest recorded date to include (inclusive)."),
              date_to: date_property("Latest recorded date to include (inclusive).")
            },
            required: %w[query],
            additionalProperties: false
          }
        }
      ]
    end

    def call(name, input)
      input = input.is_a?(String) ? JSON.parse(input) : input.stringify_keys

      case name
      when "search_meetings" then search_meetings(input)
      when "get_meeting_summary" then get_meeting_summary(input)
      when "get_meeting_transcript" then get_meeting_transcript(input)
      when "search_action_items" then search_action_items(input)
      when "search_meeting_content" then search_meeting_content(input)
      else { error: "Unknown tool '#{name}'." }
      end
    rescue ArgumentError => e
      { error: "Invalid arguments: #{e.message}" }
    end

    private

    def date_property(description)
      { type: "string", pattern: '^\d{4}-\d{2}-\d{2}$', description: "#{description} Format: YYYY-MM-DD." }
    end

    def search_meetings(input)
      scope, error = scoped_meetings(input)
      return error if error

      total = scope.count
      {
        total_matches: total,
        truncated: total > MAX_MEETING_RESULTS,
        meetings: scope.limit(MAX_MEETING_RESULTS).map { |meeting| meeting_summary(meeting) }
      }
    end

    def get_meeting_summary(input)
      meeting = Meeting.find_by(id: input["id"])
      return { found: false, reason: "No meeting found with id #{input["id"]}. Call a search tool first." } unless meeting

      {
        found: true,
        meeting: meeting_summary(meeting).merge(
          summary: meeting.processing? ? nil : meeting.summary,
          action_items: meeting.action_items.map { |item| action_item_summary(item, meeting) }
        )
      }
    end

    def get_meeting_transcript(input)
      meeting = Meeting.find_by(id: input["id"])
      return { found: false, reason: "No meeting found with id #{input["id"]}. Call a search tool first." } unless meeting
      return { found: true, processing: true, reason: "This meeting is still processing in Fathom — no transcript yet." } if meeting.processing?

      { found: true, title: meeting.title, transcript: meeting.transcript, fathom_url: meeting.fathom_url }
    end

    def search_action_items(input)
      scope, error = scoped_meetings(input)
      return error if error

      meetings = scope.limit(MAX_ACTION_ITEM_MEETINGS).to_a
      assignee_filter = input["assignee"].to_s.downcase.presence
      completed_filter = input.key?("completed") ? ActiveModel::Type::Boolean.new.cast(input["completed"]) : nil

      items = meetings.flat_map do |meeting|
        meeting.action_items.filter_map do |item|
          next if assignee_filter && !assignee_matches?(item, assignee_filter)
          next if !completed_filter.nil? && item["completed"] != completed_filter

          action_item_summary(item, meeting)
        end
      end

      {
        total_meetings_scanned: meetings.size,
        total_action_items: items.size,
        action_items: items.first(MAX_ACTION_ITEMS)
      }
    end

    def search_meeting_content(input)
      return { error: "query is required." } if input["query"].blank?

      date_scope, error = scoped_meetings(input.except("query"))
      return error if error

      query_embedding = voyage_client.embed_query(input["query"])
      chunks = TranscriptChunk.where(meeting_id: date_scope.select(:id))
        .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
        .includes(:meeting)
        .first(MAX_CONTENT_RESULTS)

      { results: chunks.map { |chunk| content_result(chunk) } }
    end

    # Shared by every tool: applies the title/attendee query (Meeting.search) and date range
    # common to search_meetings/search_action_items/search_meeting_content. Returns [scope, nil]
    # normally, or [nil, error_hash] if a date argument didn't parse — callers return that as-is.
    def scoped_meetings(input)
      scope = Meeting.search(input["query"]).order(recorded_at: :desc)

      if input["date_from"].present?
        date_from = parse_date(input["date_from"])
        return [ nil, { error: "Invalid date_from — use YYYY-MM-DD." } ] unless date_from

        scope = scope.where("recorded_at >= ?", date_from.beginning_of_day)
      end

      if input["date_to"].present?
        date_to = parse_date(input["date_to"])
        return [ nil, { error: "Invalid date_to — use YYYY-MM-DD." } ] unless date_to

        scope = scope.where("recorded_at <= ?", date_to.end_of_day)
      end

      [ scope, nil ]
    end

    def parse_date(value)
      Date.iso8601(value)
    rescue ArgumentError, TypeError
      nil
    end

    def assignee_matches?(item, assignee_filter)
      name = item.dig("assignee", "name").to_s.downcase
      email = item.dig("assignee", "email").to_s.downcase
      name.include?(assignee_filter) || email.include?(assignee_filter)
    end

    def meeting_summary(meeting)
      {
        id: meeting.id,
        title: meeting.title.presence || "Untitled meeting",
        recorded_at: meeting.recorded_at&.iso8601,
        duration_minutes: meeting.duration_minutes,
        attendees: Array(meeting.attendees).map { |a| a["matched_speaker_display_name"] || a["name"] || a["email"] }.compact,
        processing: meeting.processing?,
        fathom_url: meeting.fathom_url
      }
    end

    def action_item_summary(item, meeting)
      {
        meeting_id: meeting.id,
        meeting_title: meeting.title.presence || "Untitled meeting",
        recorded_at: meeting.recorded_at&.iso8601,
        fathom_url: meeting.fathom_url,
        description: item["description"],
        assignee: item.dig("assignee", "name"),
        completed: item["completed"],
        timestamp: item["recording_timestamp"],
        playback_url: item["recording_playback_url"]
      }
    end

    def content_result(chunk)
      {
        meeting_id: chunk.meeting.id,
        meeting_title: chunk.meeting.title.presence || "Untitled meeting",
        recorded_at: chunk.meeting.recorded_at&.iso8601,
        fathom_url: chunk.meeting.fathom_url,
        source: chunk.source,
        excerpt: chunk.content,
        relevance: (1 - chunk.neighbor_distance).round(3)
      }
    end

    def voyage_client
      api_key = ENV["VOYAGE_API_KEY"].presence || Rails.application.credentials.voyage_api_key
      raise "Set VOYAGE_API_KEY (or credentials.voyage_api_key) to use search_meeting_content." if api_key.blank?

      @voyage_client ||= VoyageClient.new(api_key)
    end
  end
end
