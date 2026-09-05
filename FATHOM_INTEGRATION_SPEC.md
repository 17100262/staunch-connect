# Fathom Integration — Spec (Meetings Module)

**Status:** Draft v1
**Owner:** [you]
**Last updated:** 2026-09-05
**Relationship to master spec:** This is the first buildable slice of Section 5.6 ("Fathom — meeting notes & transcripts") in `# Consolidated Work-Data Platform — Prod.md`, and introduces the `meetings` table already anticipated in Section 11's data model. The master spec pairs Fathom with Gmail and the cross-source AI assistant in Phase 3 (Section 14); this spec pulls just the sync-and-display piece forward and narrows it to what was actually requested: pull every meeting's transcript and summary from Fathom, show them in a new **Meetings** module, and link each one back to the original recording on Fathom's site. Linking meetings to ClickUp tasks (master spec Section 5.6 "linking to tasks"), semantic retrieval for the AI assistant (Section 9), and surfacing Fathom's native action items in the Action Items Hub (Section 7.1) all stay out of scope until their own foundations exist — see Section 9 below.

---

## 1. Problem & Goal

Meeting recordings, summaries, and transcripts currently only live inside Fathom itself — there's no way to see them alongside everything else in this app, and finding "what was discussed in that meeting" means going back into Fathom and searching manually.

**Goal:** Pull every meeting's metadata, AI-generated summary, and full transcript from Fathom into this app, and show them in a new **Meetings** module — a list of past meetings and a detail page per meeting — with a direct link back to that meeting's page on Fathom's own site for anyone who needs the original recording, comments, or Fathom's own editing tools.

**Explicitly not this phase's goal:** matching a meeting to a ClickUp task, answering natural-language questions about meeting content (that's the AI assistant, Section 9 of the master spec), or building the Action Items Hub entries Fathom's summaries already contain (Section 7.1). This phase is sync + read-only display only.

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

**Chosen approach:** a `meetings` table, upserted from the Fathom API keyed on Fathom's own recording ID (`fathom_recording_id`), so re-syncing never creates duplicates. For this phase, syncing is a manual **"Sync Now"** action — the same pattern already wired up for Hubstaff/ClickUp in `ConnectionsController#sync` — rather than a scheduled job or webhook. That keeps this phase infra-light (no new background-job setup needed, consistent with how Phase 0 avoided introducing Solid Queue per the master spec's Section 15.8), while still being a real, working sync path. Webhook- or schedule-driven sync (master spec Section 4.2's recommendation for Fathom) is a natural next step once this manual path is proven — see Section 10.

---

## 4. Auth & API — confirm at build time

Unlike Hubstaff and ClickUp (both already integrated and documented in the master spec's Sections 5.1–5.2 with confirmed quirks), Fathom's API surface hasn't been verified against live docs yet for this app. Do **not** assume the details below without checking Fathom's current API reference first — the same "confirm at build time" discipline the master spec already applied to Hubstaff's token exchange and pagination:

- **Auth mechanism:** Fathom's Team API is expected to use a simple API key (not an OAuth2 refresh-token dance like Hubstaff) — confirm the exact header/scheme before writing `FathomClient`.
- **Webhook support:** master spec Section 4.2 flags "confirm at build time — many meeting tools fire a 'recording processed' event." If Fathom does offer this, it changes Section 10's "what's next" recommendation; confirm before committing to polling-only as more than a Phase-1 stopgap.
- **Pagination:** assume Fathom paginates its meetings-list endpoint the same way every other integrated source in this app does (Hubstaff's `page_start_id` cursor, ClickUp's `page=N`) until confirmed otherwise — loop until the API signals no more pages, don't assume a single page covers all history on first sync.
- **Payload shape:** confirm exactly which fields the API returns per recording (title, start time, duration, attendees, summary, transcript, action items, share URL) before finalizing the `meetings` migration in Section 8 — the column list below is this phase's best guess based on the master spec's Section 5.6 description, not a confirmed API contract.

---

## 5. Connector module integration

Fathom is already listed as a "Coming Soon" source in the connector module (`app/views/connections/index.html.erb:9`), alongside Slack, GitHub, and Gmail. This phase moves it from that static `soon_sources` list into a real, connectable source, following the exact pattern Hubstaff and ClickUp already use:

- Add `"fathom"` to `Connection::SOURCES` (`app/models/connection.rb:2`).
- One credential field (API key) on the same connect/disconnect form already rendered per-source in `connections/index.html.erb` — no new UI pattern needed, just Fathom joining the `@connections` loop instead of `soon_sources`.
- `ConnectionsController#client_for` (`app/controllers/connections_controller.rb:63`) gains a `"fathom"` branch returning a new `FathomClient`.
- `FathomClient` (new, `app/services/fathom_client.rb`) is a plain Ruby service object matching `HubstaffClient`/`ClickupClient`'s shape: `verify!` (used on connect, to confirm the key works before saving), its own `AuthenticationError`/`RequestError`, and a `list_meetings(since: nil)` method handling pagination per Section 4.
- **Extending `sync`:** today, `ConnectionsController#sync` (line 38) just re-verifies the token. For Fathom, "sync" needs to mean something more — pull new/updated meetings and upsert them into the `meetings` table (Section 8). This is a real behavior change to that action, scoped to `connection.source == "fathom"`, not a new endpoint — same "Sync Now" button, extended meaning per source.
- No per-source scope controls yet (master spec Section 10.3's Fathom workspace/meeting-type allowlist) — flagged as an open question (Section 11) given how privacy-sensitive meeting content can be, but not built this phase, matching how Phase 0 deferred the same thing for Hubstaff/ClickUp (master spec Section 15.4).

---

## 6. The Meetings module

A new top-level module, read-only from this app's side (meetings originate in Fathom; nothing here writes back).

- **Index page** (`meetings#index`): every synced meeting, most recent first — title, date/time, attendee names, and a status badge if a meeting is still processing (Section 7). Clicking a row opens its detail page.
- **Show page** (`meetings#show`):
  - Title, date, duration, attendees.
  - **Summary** section (Fathom's AI-generated summary).
  - **Transcript** section (full text) — no chunking, search, or highlighting this phase (Section 9).
  - A **"View in Fathom"** link/button using the meeting's `fathom_url`, opening in a new tab — this is the explicit requirement that the original recording stays one click away.
- No create/edit/delete actions in this app — meetings are a synced mirror of Fathom, not app-owned records (`resources :meetings, only: %i[index show]`).

---

## 7. Ambiguity, gaps, and honesty

- **A meeting still processing in Fathom** (transcript/summary not yet generated) should sync with whatever partial data is available and display a clear "Still processing in Fathom" state for the missing pieces, rather than a blank page or an error — never hide the meeting entirely just because it's incomplete.
- **A meeting with no summary** (e.g., very short, or Fathom didn't generate one) shows "No summary generated" explicitly, not an empty-looking section that reads as a bug.
- **A meeting missing its Fathom URL** (shouldn't happen, but if the API response omits it) — don't render a dead/broken link; omit the button and note it's unavailable, since a silently broken external link is worse than an absent one.
- **Sync failures:** if a sync run partially fails (e.g., rate-limited mid-pagination), keep whatever meetings were already upserted rather than rolling back the whole batch — partial progress is better than none, consistent with the "last synced at" honesty principle the master spec already applies to every connector (Section 10.1).

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

No changes needed to `connections` beyond adding `"fathom"` to the existing `SOURCES` list (Section 5) — it already has the generic `credential`/`status`/`last_error`/`last_used_at` columns every source reuses.

---

## 9. Out of scope this phase

- **Linking meetings to ClickUp tasks** (master spec Section 5.6) — depends on the linking layer (master spec Section 4/14) that doesn't exist yet for any source; a meeting stays a standalone record this phase.
- **Semantic search / RAG over transcripts**, and the AI assistant answering questions about meeting content (master spec Section 9) — no chunking (`transcript_chunks`), no embeddings, no vector store this phase. The `transcript`/`summary` columns store plain text only.
- **Fathom action items surfaced in the Action Items Hub** (master spec Section 7.1) — captured in `action_items` (Section 8) so the data isn't lost, but no Hub UI consumes it yet.
- **Per-meeting-type scope controls** (excluding 1:1s or other sensitive recordings, master spec Section 10.3) — every meeting the API key can see gets synced this phase; see Open Questions.
- **Webhook- or schedule-driven sync** — this phase is manual "Sync Now" only (Section 3); automatic sync is a follow-on once the manual path is validated.
- **Deep-linking to a specific transcript moment** (master spec Section 9's "deep-link to the transcript moment if the API supports it") — the Fathom link this phase goes to the recording's top-level page, not a timestamped moment.
- **In-app transcript search** — see Open Question 4.

---

## 10. What's next, once this phase is validated

- Move sync from manual-only to scheduled polling and/or webhook-driven, per master spec Section 4.2's recommendation — pending the webhook confirmation in Section 4.
- Chunk transcripts and add them to the AI assistant's retrieval layer (master spec Section 9), once a source with real unstructured text (Slack, email, or this) makes RAG worth the infrastructure (per `AI_ASSISTANT_SPEC.md` Section 3's reasoning for why Phase A skipped it).
- Link meetings to tasks via explicit ClickUp references mentioned in the transcript/summary, plus semantic matching (master spec Section 5.6), once the broader linking layer exists.
- Surface Fathom's `action_items` in the Action Items Hub (master spec Section 7.1) as a trusted, non-suggested source.

---

## 11. Open questions

1. **Fathom auth mechanism and webhook support** — needs confirming against Fathom's current API docs before `FathomClient` is written (Section 4); this also determines whether Section 10's "what's next" starts from polling or webhooks.
2. **Scope — sync every recording, or an allowlist/exclude by meeting type?** Master spec Section 10.3 explicitly flags Fathom for this (e.g. excluding 1:1s or other sensitive meetings) given meeting content can include HR or client-sensitive discussion. Recommend deciding this before turning sync on broadly, same caution the master spec applies to Slack/Gmail.
3. **Retention** — keep transcripts indefinitely, or define a retention window? Ties into the master spec's Section 12 data-retention requirement, and matters more here than for invoicing data given transcript content can be sensitive.
4. **In-app transcript search** — is a simple Postgres text search across meeting titles/transcripts worth adding before full semantic search (Section 6.2 of the master spec, "Cross-source search") exists, or should that wait entirely?

---

## 12. Acceptance criteria

1. Fathom appears in the connector module as a real, connectable source (not "Coming Soon"), accepting an API key and showing Connected/Not connected/Error status like Hubstaff and ClickUp.
2. An invalid Fathom API key shows an error state on connect, rather than silently saving a broken credential.
3. Clicking "Sync Now" on a connected Fathom source pulls in every meeting the API key can see and creates one `meetings` row per recording.
4. Running "Sync Now" again does not create duplicate rows for meetings already synced (upsert on `fathom_recording_id`), and updates any meeting whose summary/transcript has since finished processing.
5. The Meetings module's index page lists every synced meeting, most recent first, with title, date, and attendees visible without opening the meeting.
6. Opening a meeting shows its summary and full transcript, and a "View in Fathom" link that opens that exact recording on Fathom's site in a new tab.
7. A meeting still processing in Fathom (missing summary or transcript) displays a clear "still processing" state for the missing piece(s) instead of a blank section or an error.
8. Disconnecting the Fathom connection stops future syncs but does not delete already-synced meetings from the Meetings module.
