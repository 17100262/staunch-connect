# Runs the Fathom "Sync Now" backstop (FATHOM_INTEGRATION_SPEC.md Section 5.1)
# in the background — a first backfill can mean paging through a large batch
# of meetings, which shouldn't hold the controller request/browser tab open.
# Uses the same upsert (Fathom::MeetingSync) the webhook path uses, so a
# meeting synced this way is indistinguishable from one that arrived live.
class FathomSyncJob < ApplicationJob
  queue_as :default

  def perform(connection_id)
    connection = Connection.find_by(id: connection_id, source: "fathom")
    return unless connection

    client = FathomClient.new(connection.credential)
    client.verify!
    # Deliberately not `connection.last_used_at` — that's touched by connect,
    # every sync, and every webhook delivery for unrelated reasons, so it's
    # always "now" by the time a backfill would want to use it (this was a
    # real bug: it made every sync after the first fetch nothing, since the
    # cutoff was only seconds old). `Meeting.maximum(:synced_at)` is nil until
    # something has actually been synced once (full backfill), and afterward
    # only advances when a meeting is actually upserted.
    client.list_meetings(since: Meeting.maximum(:synced_at)).each { |payload| Fathom::MeetingSync.call(payload) }
    connection.update!(status: :connected, last_error: nil, last_used_at: Time.current)
  rescue FathomClient::AuthenticationError, FathomClient::RequestError => e
    connection.update!(status: :error, last_error: e.message)
  rescue StandardError => e
    # Surface the failure instead of leaving the connection stuck showing
    # "Syncing…" forever, but still re-raise so ActiveJob's own failure
    # handling/retries see it — this is the one branch that isn't an expected
    # Fathom API error, so it shouldn't fail silently either way.
    connection.update!(status: :error, last_error: "Sync failed: #{e.message}")
    raise
  end
end
