# Fathom Integration — Spec (Meetings Module)

**Status:** Draft v1
**Owner:** [you]
**Last updated:** 2026-09-10
**Relationship to master spec:** This is the first buildable slice of Section 5.6 ("Fathom — meeting notes & transcripts") in `# Consolidated Work-Data Platform — Prod.md`, and introduces the `meetings` table already anticipated in Section 11's data model. The master spec pairs Fathom with Gmail and the cross-source AI assistant in Phase 3 (Section 14); this spec pulls just the sync-and-display piece forward and narrows it to what was actually requested: pull every meeting's transcript and summary from Fathom, show them in a new **Meetings** module, and link each one back to the original recording on Fathom's site. Linking meetings to ClickUp tasks (master spec Section 5.6 "linking to tasks") and surfacing Fathom's native action items in the Action Items Hub (Section 7.1) stay out of scope until their own foundations exist — see Section 9 below. Semantic retrieval for the AI assistant is no longer purely hypothetical: `AI_ASSISTANT_SPEC.md` Section 12 ("Phase B — Meetings") now builds a keyword-search tool surface directly on top of the `meetings` table this spec ships, per that section's own reasoning for why embeddings aren't the right next step yet either.

---

## 1. Problem & Goal

Meeting recordings, summaries, and transcripts currently only live inside Fathom itself — there's no way to see them alongside everything else in this app, and finding "what was discussed in that meeting" means going back into Fathom and searching manually.

**Goal:** Pull every meeting's metadata, AI-generated summary, and full transcript from Fathom into this app, and show them in a new **Meetings** module — a list of past meetings and a detail page per meeting — with a direct link back to that meeting's page on Fathom's own site for anyone who needs the original recording, comments, or Fathom's own editing tools.

**Explicitly not this phase's goal:** matching a meeting to a ClickUp task, or building the Action Items Hub entries Fathom's summaries already contain (Section 7.1). This phase is sync + read-only display only — natural-language Q&A over meeting content followed as its own phase, `AI_ASSISTANT_SPEC.md` Section 12, once this one had real synced data to answer from.

---

## 2. Example scenarios this phase must handle

- Open the Meetings module and see every synced meeting, most recent first, with title, date, and attendees at a glance.
- Open a specific meeting and read its summary and full transcript without leaving the app.
- Click a "View in Fathom" link on a meeting and land on that exact recording's page on Fathom's site.
- Sync pulls in a meeting that happened since the last sync, without duplicating meetings already synced.
- A meeting Fathom is still processing (recorded minutes ago, transcript not ready yet) shows a clear "processing" state instead of a blank or broken page.
- A very short meeting with no meaningful summary shows "No summary generated" rather than an empty section that looks like a bug.

---

## 3. Why sync-and-store instead of fetching from Fathom live

Same reasoning the master spec already applies elsewhere (Section 4): the Meetings module needs to list potentially hundreds of meetings, sorted and browsable, which means a local indexed copy rather than a live API call per page view. This also matches the existing app's own precedent — `invoices`/`invoice_line_items` are persisted rows, not live ClickUp/Hubstaff calls, once a page needs to *list and revisit* records rather than compute a one-off total.

**Chosen approach:** a `meetings` table, upserted from Fathom keyed on Fathom's own recording ID (`fathom_recording_id`), so re-syncing (from either path below) never creates duplicates. Fathom does support webhooks (confirmed — see Section 4), so this phase uses the same **two-path pattern the master spec already recommends generally** (Section 4.3): a webhook as the primary, near-real-time sync path, plus the existing manual **"Sync Now"** action (already wired up for Hubstaff/ClickUp in `ConnectionsController#sync`) as a human-triggered backstop for anything a missed/failed webhook delivery didn't catch — webhook delivery is never 100% reliable (master spec Section 4.1), and a meeting only synced when someone happens to click "Sync Now" isn't good enough once webhooks are available. An **automatic, scheduled** reconciliation sync (master spec Section 4.3's "nightly full sync" safety net) is deliberately deferred — see Section 9.

**Revised during implementation — manual sync does use a background job after all:** the original plan above assumed "Sync Now" could stay a synchronous controller action, since Solid Queue wasn't otherwise needed this phase. In practice, a first backfill against a real account paginates through however many meetings the API key can see (239, in testing) — long enough to make the controller request itself a bad place to run it. `FathomSyncJob` (Solid Queue, already bundled per Section 15.8) now does the actual `list_meetings` + upsert loop; `ConnectionsController#sync` just flips the connection to a new `syncing` status and enqueues the job, returning immediately. This is still the same *human-triggered* backstop described above — nothing here is a scheduled/automatic job — it's just no longer holding the request open while it runs. See Section 5.1.

---

## 4. Auth & API — confirm at build time

Unlike Hubstaff and ClickUp (both already integrated and documented in the master spec's Sections 5.1–5.2 with confirmed quirks), Fathom's API surface hasn't been verified against live docs yet for this app. Do **not** assume the details below without checking Fathom's current API reference first — the same "confirm at build time" discipline the master spec already applied to Hubstaff's token exchange and pagination:

- **Auth mechanism — confirmed:** a plain API key sent as the `X-Api-Key` header, against `https://api.fathom.ai/external/v1`. No OAuth2 refresh dance like Hubstaff.
- **Webhooks — confirmed available and confirmed working end-to-end** against a live account during implementation:
  - **Creating one is an API call**, `POST /webhooks`, not just a dashboard setting — this app registers it automatically on connect (Section 5.1/5.2).
  - **`triggered_for` is required** — a non-empty array from the enum `my_recordings` / `shared_external_recordings` / `my_shared_with_team_recordings` / `shared_team_recordings` (this is the recording *scope*; separate from the `include_*` payload-content flags). This app requests all four by default, matching this phase's "sync everything the key can see" scope (Section 9/11).
  - **`destination_url` must be `https://`** — Fathom rejects a plain-http URL outright (confirmed: a `http://localhost:3000/...` URL fails with `"Invalid URL. Must be a valid HTTPS URL."`). This means registering the webhook from a local dev server without an HTTPS tunnel (ngrok or similar) will always fail — handled as a **non-fatal** failure on connect (the API key still connects; meetings sync via manual "Sync Now" until a real HTTPS endpoint is available, e.g. once deployed).
  - **Signature scheme** — confirmed via docs: `webhook-id`/`webhook-timestamp`/`webhook-signature` headers, `whsec_`-prefixed base64 secret, signed content `"#{id}.#{timestamp}.#{raw_body}"`, HMAC-SHA256, base64-encoded, constant-time compared (the Standard Webhooks/Svix convention) — implemented and tested in `FathomWebhookVerifier`.
  - **Event name:** `new-meeting-content-ready`, confirmed via docs. Whether it's the only lifecycle event, and whether payloads are always full snapshots, remains unconfirmed against a real delivery — see Section 7.
- **Pagination:** confirmed — `GET /meetings` takes a `limit` param and returns `next_cursor` (an opaque token) in the response; pass it back as `cursor` for the next page. Implemented in `FathomClient#list_meetings`.
- **Payload shape — confirmed, and `Fathom::MeetingSync` fixed to match:** a live `GET /meetings` response was inspected during implementation and returns (among others) `recording_id` (integer), `title`, `url`, `share_url`, `scheduled_start_time`, `recording_start_time`/`recording_end_time` (no separate duration field — computed from these two), `calendar_invitees` (array of `{name, email, ...}`), `transcript` (array of `{text, speaker: {display_name}, timestamp}` segments, not a plain string), `default_summary` (an object — `{template_name, markdown_formatted}`, not a plain string), `action_items` — all richer and differently named than this phase's original guess. Two real bugs this caused, both fixed:
  - `fathom_url` originally preferred `url` (the internal `fathom.video/calls/...` link) over `share_url` (the actual public share page) — flipped to prefer `share_url`.
  - Summary extraction checked for a `"markdown"` key that doesn't exist — the real key is `markdown_formatted` — so every summary synced as blank until this was corrected. `default_summary`'s markdown is now also rendered as real HTML (headers/bold/links) in the Meetings show page via `redcarpet`, sanitized against an explicit tag/attribute allowlist, rather than displayed as raw markdown text — see Section 6.
- **Rate limits — confirmed real, not just a documented ceiling:** a full backfill during implementation testing hit Fathom's 429 for real. `FathomClient` now retries with backoff (honoring `Retry-After`, up to 3 attempts) before raising — see Section 7.

---

## 5. Connector module integration

Fathom is already listed as a "Coming Soon" source in the connector module (`app/views/connections/index.html.erb:9`), alongside Slack, GitHub, and Gmail. This phase moves it from that static `soon_sources` list into a real, connectable source, combining an API key (for manual sync + backfill) with a webhook (for real-time sync).

### 5.1 API key & manual "Sync Now" (backstop path)

- Add `"fathom"` to `Connection::SOURCES` (`app/models/connection.rb:2`).
- One credential field (API key) on the same connect/disconnect form already rendered per-source in `connections/index.html.erb` — no new UI pattern needed, just Fathom joining the `@connections` loop instead of `soon_sources`.
- `ConnectionsController#client_for` (`app/controllers/connections_controller.rb:63`) gains a `"fathom"` branch returning a new `FathomClient`.
- `FathomClient` (new, `app/services/fathom_client.rb`) is a plain Ruby service object matching `HubstaffClient`/`ClickupClient`'s shape: `verify!` (used on connect, to confirm the key works before saving), its own `AuthenticationError`/`RequestError`, and a `list_meetings(since: nil)` method handling pagination per Section 4.
- **Extending `sync`:** today, `ConnectionsController#sync` (line 38) just re-verifies the token. For Fathom, "sync" needs to mean something more — pull new/updated meetings and upsert them into the `meetings` table (Section 8). This is a real behavior change to that action, scoped to `connection.source == "fathom"`, not a new endpoint — same "Sync Now" button, extended meaning per source. Since webhooks are now the primary path (5.2), this button's main job becomes **backfill on first connect** (pull everything that predates the webhook being configured) and **catch-up** for anything a missed webhook delivery didn't cover — the "refresh now" role the master spec describes generally in Section 4.
- **Runs as a background job, not inline in the request** (revised during implementation — see Section 3): `ConnectionsController#sync` flips the connection to a new `syncing` status and calls `FathomSyncJob.perform_later(connection.id)`, returning immediately; the job itself calls `FathomClient#list_meetings` and upserts each result, then sets the connection back to `connected` (or `error`, with the message, if it fails — including any *unexpected* exception, not just a known Fathom API error, so the connection is never stuck showing "Syncing…" forever). The connector UI shows a blue "Syncing" badge and disables the button meanwhile.
- **The incremental cutoff is *not* `connection.last_used_at`** — that field is touched by connect, every sync, and every webhook delivery, so by the time a second sync runs it's always "a few seconds ago," which would silently exclude all real history (a real bug caught during implementation: a backfill immediately after connecting fetched zero meetings). `FathomSyncJob` instead uses `Meeting.maximum(:synced_at)` — `nil` until something has actually been synced once (full backfill), and only advances as meetings are actually upserted, independent of unrelated connection churn.
- The upsert logic itself (match on `fathom_recording_id`, write the columns in Section 8) is shared between this path and the webhook path (5.2) via one object — `Fathom::MeetingSync.call(payload)` — so there is exactly one place that decides how a Fathom payload becomes a `meetings` row, regardless of which path delivered it.
- No per-source scope controls yet (master spec Section 10.3's Fathom workspace/meeting-type allowlist) — flagged as an open question (Section 11) given how privacy-sensitive meeting content can be, but not built this phase, matching how Phase 0 deferred the same thing for Hubstaff/ClickUp (master spec Section 15.4).

### 5.2 Webhook endpoint (primary, real-time path)

- **New route, outside the authenticated app:** `POST /webhooks/fathom` — Fathom's servers call this directly, so it cannot sit behind the app's normal session login. It uses the same exemption already used for `SessionsController#create` (`allow_unauthenticated_access`, from the `Authentication` concern in `app/controllers/application_controller.rb`) rather than a new auth mechanism.
- **New controller**, e.g. `Webhooks::FathomController#create` — deliberately outside the `connections`/`meetings` resource namespaces, since it's not a user-facing action.
- **Signature verification is mandatory, not optional**, since this is the one endpoint in the app reachable without logging in: the request must be verified against a webhook signing secret before its payload is trusted (exact header/algorithm per Section 4's open confirmation item). An unverifiable or missing signature returns 401 and does nothing — never process an unverified payload just because it looks well-formed.
- **Storing the signing secret:** a new `webhook_secret` column on `connections` (encrypted at rest, same as `credential`/`access_token`), set once when configuring the webhook on Fathom's side and pasted into the connector form alongside the API key. Only meaningful for `source == "fathom"`, same as `access_token` is only meaningful for Hubstaff today.
- **On a verified delivery:** parse the payload for the recording ID and available fields, then call the same `Fathom::MeetingSync.call(payload)` used by manual sync (5.1) to upsert into `meetings` — a webhook-driven update and a manual-sync-driven update are indistinguishable to the rest of the app once they land in that table.
- **Registration is non-fatal — confirmed necessary during implementation, not just a hypothetical edge case:** Fathom's `POST /webhooks` rejects a non-`https://` `destination_url` outright (Section 4), which means registering from a local dev server without an HTTPS tunnel *always* fails. `ConnectionsController#create` treats this as recoverable: a valid API key still connects (status `connected`) even when webhook registration fails, with the failure surfaced once in the flash notice ("Webhook registration failed... meetings will only sync via Sync Now until this is fixed") rather than aborting the whole connect. The connector card itself shows an ongoing amber "No webhook registered — use Sync Now to pull meetings" indicator whenever `webhook_id` is blank, versus a green "Webhook registered — new meetings sync automatically" once it isn't — so the state stays visible, not just a one-time flash message.
- **Idempotency:** webhook providers redeliver on timeout/retry, and Fathom may also fire more than one event per recording's lifecycle (Section 4). The upsert on `fathom_recording_id` already makes redelivery safe; a repeated or out-of-order event simply overwrites the row with that event's payload — confirm at build time whether Fathom's events are always full-state snapshots (safe to overwrite) or could be partial/delta payloads (which would need merging logic instead).
- **Respond fast:** acknowledge with a 2xx as soon as the payload is verified and the upsert has run — the upsert itself is a single fast DB write, so no background job is needed to keep this endpoint responsive.

---

## 6. The Meetings module

A new top-level module, read-only from this app's side (meetings originate in Fathom; nothing here writes back).

- **Index page** (`meetings#index`): every synced meeting, most recent first, as a real `<table>` (not a div/grid approximation) — title, date, attendees, and a status note if a meeting is still processing (Section 7). Clicking "View" opens its detail page.
  - **Search — added during implementation, beyond this section's original scope:** a `q` param matches title or any attendee's name, via `Meeting.search` — a DB-level query (`title ILIKE` OR'd with an `EXISTS (SELECT ... FROM jsonb_array_elements(attendees) ...)` check against each attendee's name) rather than loading every row into Ruby to filter, so it stays cheap as the table grows. Three states: the original "connect Fathom" onboarding card (no meetings synced at all), a plain "No meetings match" message (a search with zero results — the search box stays visible so it can be adjusted), or the table. `AI_ASSISTANT_SPEC.md` Section 12's `search_meetings` tool reuses this exact method, rather than re-implementing matching logic twice.
- **Show page** (`meetings#show`):
  - Title, date, duration, attendees.
  - **Summary** section — Fathom's AI-generated summary, rendered as real HTML (`redcarpet`, with `filter_html` + a post-render `sanitize` allowlist) rather than raw markdown text, since the real payload turned out to contain actual markdown (headers, bold takeaways, links to timestamped moments) rather than plain prose (Section 4).
  - **Transcript** section (full text, speaker-attributed per line — e.g. "Alex: ...") — no chunking, in-page search, or highlighting this phase (Section 9).
  - A **"View in Fathom"** link/button using the meeting's `fathom_url` (now `share_url`-preferring, Section 4), opening in a new tab — this is the explicit requirement that the original recording stays one click away.
- No create/edit/delete actions in this app — meetings are a synced mirror of Fathom, not app-owned records (`resources :meetings, only: %i[index show]`).

---

## 7. Ambiguity, gaps, and honesty

- **A meeting still processing in Fathom** (transcript/summary not yet generated) should sync with whatever partial data is available and display a clear "Still processing in Fathom" state for the missing pieces, rather than a blank page or an error — never hide the meeting entirely just because it's incomplete.
- **A meeting with no summary** (e.g., very short, or Fathom didn't generate one) shows "No summary generated" explicitly, not an empty-looking section that reads as a bug.
- **A meeting missing its Fathom URL** (shouldn't happen, but if the API response omits it) — don't render a dead/broken link; omit the button and note it's unavailable, since a silently broken external link is worse than an absent one.
- **Sync failures:** if a sync run partially fails (e.g., rate-limited mid-pagination), keep whatever meetings were already upserted rather than rolling back the whole batch — partial progress is better than none, consistent with the "last synced at" honesty principle the master spec already applies to every connector (Section 10.1).
- **An unverified webhook request** (bad/missing signature) must be rejected outright (Section 5.2) — this is the one publicly reachable endpoint in the app, so "fail closed" applies here more than anywhere else in the system.
- **A missed or failed webhook delivery** shouldn't silently mean a meeting never appears — this is exactly what the manual "Sync Now" backstop (5.1) exists for; the Meetings module should never depend on webhook delivery being perfect.

---

## 8. Data model needed this phase

One new table, matching the `meetings` entity already anticipated in the master spec's Section 11 data model — minus the `transcript_chunks` child table, which only matters once embeddings/RAG retrieval is built (Section 9 below, and master spec Section 9's retrieval architecture):

- `meetings`
  - `fathom_recording_id` (string, not null, unique) — Fathom's own ID; the upsert key that makes re-syncing idempotent.
  - `title` (string)
  - `fathom_url` (string, not null) — link back to the original recording, this phase's explicit requirement.
  - `recorded_at` (datetime) — meeting start time, used for index-page ordering.
  - `duration_minutes` (integer, nullable)
  - `attendees` (jsonb, default `[]`) — array of attendee names/emails as Fathom returns them.
  - `summary` (text, nullable) — Fathom's AI-generated summary.
  - `transcript` (text, nullable) — full transcript text.
  - `action_items` (jsonb, default `[]`) — Fathom's own extracted action items, captured now since they arrive in the same payload at no extra cost, but not surfaced in any UI this phase (master spec Section 7.1's Action Items Hub is a later feature; this just avoids throwing the data away).
  - `raw_payload` (jsonb, nullable) — the full API response for that recording, same auditability principle already applied to `ai_messages.tool_calls` (`AI_ASSISTANT_SPEC.md` Section 8) — lets a future feature (linking, RAG chunking) use fields this phase didn't anticipate, without re-fetching from Fathom.
  - `synced_at` (datetime) — when this row was last upserted from Fathom.
  - `created_at` / `updated_at`

Two columns added to the existing `connections` table:

- `webhook_secret` (text, encrypted, nullable) — Fathom's webhook signing secret, only populated for `source == "fathom"` (Section 5.2), same "generic column, source-specific meaning" pattern `access_token` already follows for Hubstaff.
- `webhook_id` (string, nullable) — the registered webhook's Fathom-side id, needed to deregister it (`DELETE /webhooks/{id}`) on disconnect; also doubles as the connector card's "is a webhook actually registered" flag (Section 5.2) since it's blank whenever registration failed or hasn't run yet.

Beyond that, no other changes needed to `connections` — adding `"fathom"` to the existing `SOURCES` list (Section 5.1) reuses the generic `credential`/`status`/`last_error`/`last_used_at` columns every source already has.

---

## 9. Out of scope this phase

- **Linking meetings to ClickUp tasks** (master spec Section 5.6) — depends on the linking layer (master spec Section 4/14) that doesn't exist yet for any source; a meeting stays a standalone record this phase.
- **Semantic search / RAG over transcripts** — no chunking (`transcript_chunks`), no embeddings, no vector store this phase; the `transcript`/`summary` columns store plain text only. (The AI assistant answering questions about meeting content is *not* out of scope anymore — `AI_ASSISTANT_SPEC.md` Section 12 covers that, using keyword search over these same columns rather than embeddings, for the same reasons this spec never needed them either.)
- **Fathom action items surfaced in the Action Items Hub** (master spec Section 7.1) — captured in `action_items` (Section 8) so the data isn't lost, but no Hub UI consumes it yet.
- **Per-meeting-type scope controls** (excluding 1:1s or other sensitive recordings, master spec Section 10.3) — every meeting the API key/webhook can see gets synced this phase; see Open Questions.
- **Automatic, scheduled reconciliation sync** (master spec Section 4.3's "nightly full sync" safety net) — this phase's backstop against a missed webhook is the human-triggered "Sync Now" button (5.1), not a recurring background job; see Section 10.
- **Deep-linking to a specific transcript moment** (master spec Section 9's "deep-link to the transcript moment if the API supports it") — the Fathom link this phase goes to the recording's top-level page, not a timestamped moment. (Individual bullet points *within* a rendered summary do link to a timestamp, since Fathom's own markdown embeds those — Section 6 — but that's Fathom's doing, not a deep-link this app constructs itself.)

---

## 10. What's next, once this phase is validated

- Replace the human-triggered "Sync Now" backstop (now a background job per Section 3/5.1, but still human-triggered) with an automatic *scheduled* reconciliation job (master spec Section 4.3) — the webhook stays primary either way.
- Chunk transcripts and add them to a real embeddings-based retrieval layer (master spec Section 9), once keyword search (`AI_ASSISTANT_SPEC.md` Section 12) proves insufficient for real usage — see that section's own Open Question 12.10.1.
- Link meetings to tasks via explicit ClickUp references mentioned in the transcript/summary, plus semantic matching (master spec Section 5.6), once the broader linking layer exists.
- Surface Fathom's `action_items` in the Action Items Hub (master spec Section 7.1) as a trusted, non-suggested source. (The AI assistant can already answer *ad hoc* questions about them per `AI_ASSISTANT_SPEC.md` Section 12 — this is specifically about a dedicated, cross-source tracking UI, which still doesn't exist.)

---

## 11. Open questions

1. ~~**Exact webhook contract**~~ — **resolved**: confirmed against real docs and a live account (Section 4) — event `new-meeting-content-ready`, `triggered_for` enum, Svix-style signature scheme, all implemented and tested. Still genuinely open: whether a recording ever fires *more than one* lifecycle event (Section 7's "full snapshot vs. delta" question) — unconfirmed, since only one real delivery has been observed so far.
2. **Scope — sync every recording, or an allowlist/exclude by meeting type?** Master spec Section 10.3 explicitly flags Fathom for this (e.g. excluding 1:1s or other sensitive meetings) given meeting content can include HR or client-sensitive discussion. Recommend deciding this before turning sync on broadly, same caution the master spec applies to Slack/Gmail — doubly relevant now that sync is webhook-driven and effectively automatic once configured. Still open.
3. **Retention** — keep transcripts indefinitely, or define a retention window? Ties into the master spec's Section 12 data-retention requirement, and matters more here than for invoicing data given transcript content can be sensitive. Still open.
4. ~~**In-app transcript search**~~ — **resolved, shipped ahead of schedule**: `Meeting.search` (title + attendee name) is live on the Meetings index page (Section 6), and reused by the AI assistant (`AI_ASSISTANT_SPEC.md` Section 12). Not full-text search over transcript *bodies* yet, though — worth revisiting if title/attendee matching proves too narrow in practice.
5. **Automatic reconciliation timing** — is the manual "Sync Now" backstop (5.1) good enough indefinitely, or does a scheduled reconciliation job (Section 10) need to happen sooner, given how much a silently-missed webhook could matter for meeting content specifically? Still open.

---

## 12. Acceptance criteria

1. Fathom appears in the connector module as a real, connectable source (not "Coming Soon"), accepting an API key and a webhook secret and showing Connected/Not connected/Error status like Hubstaff and ClickUp.
2. An invalid Fathom API key shows an error state on connect, rather than silently saving a broken credential.
3. Clicking "Sync Now" on a connected Fathom source pulls in every meeting the API key can see and creates one `meetings` row per recording.
4. Running "Sync Now" again does not create duplicate rows for meetings already synced (upsert on `fathom_recording_id`), and updates any meeting whose summary/transcript has since finished processing.
5. Configuring Fathom's webhook to point at this app's `/webhooks/fathom` endpoint results in a new meeting appearing in the Meetings module shortly after it's recorded in Fathom, without anyone clicking "Sync Now."
6. A webhook request with an invalid or missing signature is rejected (401) and does not create or modify any `meetings` row.
7. A redelivered or duplicate webhook event for the same recording does not create a duplicate meeting row.
8. The Meetings module's index page lists every synced meeting (whether it arrived via webhook or manual sync), most recent first, with title, date, and attendees visible without opening the meeting.
9. Opening a meeting shows its summary and full transcript, and a "View in Fathom" link that opens that exact recording on Fathom's site in a new tab.
10. A meeting still processing in Fathom (missing summary or transcript) displays a clear "still processing" state for the missing piece(s) instead of a blank section or an error.
11. Disconnecting the Fathom connection stops future syncs but does not delete already-synced meetings from the Meetings module.
12. Clicking "Sync Now" returns control immediately (a "Fathom sync started in the background" notice) rather than holding the page while every meeting is fetched; the connector card shows a distinct "Syncing" status until the background job finishes.
13. Running "Sync Now" a second time still finds every meeting since the first sync — not zero, even though the connection's own `last_used_at` was updated moments ago by the first sync.
14. Searching the Meetings index by a meeting's title, or by any attendee's name (full or partial, case-insensitive), returns only matching meetings; a search with no matches shows a plain "no meetings match" message without hiding the search box.
15. A meeting's summary renders as formatted HTML (headings, bold takeaways, clickable timestamp links) rather than raw markdown syntax, and any HTML embedded in the source summary text is stripped rather than executed.
