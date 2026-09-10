require "net/http"
require "uri"
require "json"

# Confirmed at build time (developers.fathom.ai): auth is a plain API key sent
# as the `X-Api-Key` header (no OAuth2 refresh dance like Hubstaff), and the
# base URL is `https://api.fathom.ai/external/v1`. What isn't fully confirmed
# from the public docs — exact pagination field names on `/meetings`, and the
# precise request/response body shape for `/webhooks` — is called out inline
# below and in FATHOM_INTEGRATION_SPEC.md Section 4; this client is written
# defensively (checks a couple of plausible key names) so it degrades to an
# empty/no-op result rather than raising if a guess is wrong, and callers
# should confirm against a real account before relying on it in production.
class FathomClient
  class AuthenticationError < StandardError; end
  class RequestError < StandardError; end

  BASE_URL = "https://api.fathom.ai/external/v1"

  def initialize(api_key)
    @api_key = api_key
  end

  def verify!
    get("/meetings", "limit" => 1)
    true
  end

  # `since` (a Time) scopes the pull to meetings recorded after the connection's
  # last sync — confirm the exact filter param name Fathom expects; omitted
  # entirely on a first backfill, which pulls everything the API key can see.
  def list_meetings(since: nil)
    meetings = []
    query = { "include_transcript" => "true", "include_summary" => "true", "include_action_items" => "true" }
    query["created_after"] = since.iso8601 if since

    loop do
      response = get("/meetings", query)
      batch = response["items"] || response["meetings"] || []
      meetings.concat(batch)

      next_cursor = response["next_cursor"] || response.dig("pagination", "next_cursor")
      break if next_cursor.blank?

      query["cursor"] = next_cursor
    end

    meetings
  end

  # Confirmed at build time: `triggered_for` is required and must be a
  # non-empty array from this exact enum — it's the recording *scope* (whose
  # meetings trigger delivery), separate from the `include_*` flags below
  # (which control *what's in* the payload). Defaults to every scope, since
  # this phase has no per-meeting-type allowlist yet (FATHOM_INTEGRATION_SPEC.md
  # Section 9/11 — that's future work). Also confirmed: `destination_url` must
  # be `https://` — Fathom rejects a plain-http localhost URL outright, so
  # this will fail with a clear error when registered from local dev without
  # an HTTPS tunnel; the caller treats that as non-fatal (Section 5.1/5.2).
  TRIGGERED_FOR = %w[my_recordings shared_external_recordings my_shared_with_team_recordings shared_team_recordings].freeze

  # Registers a webhook pointed at `destination_url`, requesting the full
  # transcript/summary/action-item content on every delivery. Returns the
  # webhook id (for later deletion) and the signing secret Fathom generates
  # for it, which must be persisted immediately — it's the only time it's returned.
  def create_webhook(destination_url)
    response = post("/webhooks", {
      "destination_url" => destination_url,
      "triggered_for" => TRIGGERED_FOR,
      "include_transcript" => true,
      "include_summary" => true,
      "include_action_items" => true
    })

    { id: response["id"], secret: response["secret"] }
  end

  def delete_webhook(webhook_id)
    delete("/webhooks/#{webhook_id}")
    true
  end

  private

  def get(path, query = {})
    uri = URI("#{BASE_URL}#{path}")
    uri.query = URI.encode_www_form(query) if query.any?

    request = Net::HTTP::Get.new(uri)
    request["X-Api-Key"] = @api_key

    perform(uri, request)
  end

  def post(path, body)
    uri = URI("#{BASE_URL}#{path}")
    request = Net::HTTP::Post.new(uri)
    request["X-Api-Key"] = @api_key
    request["Content-Type"] = "application/json"
    request.body = body.to_json

    perform(uri, request)
  end

  def delete(path)
    uri = URI("#{BASE_URL}#{path}")
    request = Net::HTTP::Delete.new(uri)
    request["X-Api-Key"] = @api_key

    perform(uri, request)
  end

  MAX_RATE_LIMIT_RETRIES = 3

  # Fathom's documented rate limits (60/min standard, 30/min — sometimes 5 —
  # for the transcript/summary-heavy endpoints `list_meetings` uses) are easy
  # to hit on a real backfill, not just a debugging burst — so a 429 here is
  # retried with backoff (honoring `Retry-After` when Fathom sends it) rather
  # than immediately failing the whole sync.
  def perform(uri, request, attempt: 1)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }

    case response
    when Net::HTTPTooManyRequests
      raise RequestError, "Fathom rate-limited this request after #{MAX_RATE_LIMIT_RETRIES} attempts." if attempt >= MAX_RATE_LIMIT_RETRIES

      sleep(retry_after_seconds(response))
      perform(uri, request, attempt: attempt + 1)
    when Net::HTTPUnauthorized, Net::HTTPForbidden
      raise AuthenticationError, "Fathom rejected this API key."
    when Net::HTTPSuccess
      response.body.present? ? JSON.parse(response.body) : {}
    else
      raise RequestError, "Fathom request failed (#{response.code}): #{error_message_from(response.body)}"
    end
  end

  def retry_after_seconds(response)
    (response["Retry-After"] || response["RateLimit-Reset"]).to_i.clamp(1, 30)
  end

  # Fathom's error responses are `{"error": "..."}` — surface that message
  # directly instead of just the status code, so a failure is self-diagnosing
  # (this is exactly how the `triggered_for`/HTTPS-only webhook requirements
  # got discovered — a bare status code alone gave no way to tell why).
  def error_message_from(body)
    JSON.parse(body)["error"]
  rescue JSON::ParserError, TypeError
    body.presence || "no response body"
  end
end
