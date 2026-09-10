# AI Assistant — Spec (v2, Consolidated)

**Status:** Shipped — Phase A (Invoicing) and Phase B (Meetings, including semantic search)
**Owner:** [you]
**Last updated:** 2026-09-10
**Supersedes:** `AI_ASSISTANT_SPEC.md` — that document is the build record (original design → gaps found while implementing → what changed and why, with strikethroughs and "as implemented" annotations layered on top of the original text). This document drops the revision history and describes the current, as-built system as a single coherent whole, for anyone who wants to understand or extend it without reading how it got here.
**Relationship to master spec:** This is the buildable slice of Section 9 ("Feature: AI Assistant") in `# Consolidated Work-Data Platform — Prod.md` — that section's long-run vision is a chat interface with retrieval across all six sources (Hubstaff, ClickUp, Slack, GitHub, Fathom, Gmail). Two of those sources have real, persisted, queryable data today: invoicing (`invoices`/`invoice_line_items`/`project_mappings`) and Fathom meetings (`meetings`, via `FATHOM_INTEGRATION_SPEC.md`). Slack, GitHub, and Gmail stay a "Soon" concept until their own sync/linking work lands (master spec Section 14).

---

## 1. What this is

A chat-based assistant, reachable from the sidebar's "AI Assistant" entry, that answers natural-language questions grounded in this app's own data — never inventing a number or fact, and always naming which record(s) an answer came from so it can be checked in one click. Two domains today:

- **Invoicing** — "what was the total for the August invoice," "which task had the most estimated hours."
- **Meetings** — "what did we agree to in the call with X," "which meeting discussed the AWS migration," "what are my open action items this week."

Both domains are served by the same chat UI, the same conversation history, and the same underlying mechanism — only the tool surface differs.

---

## 2. Core design principle: tools, never freeform SQL, RAG only where it earns its keep

The model is never allowed to query the database directly or receive a raw table/column name as an argument. Instead:

- **Structured facts** (invoice totals, line items, meeting metadata, action items) are served by plain Ruby methods ("tools") that run real ActiveRecord queries and return exact values — a sum is always `Invoice#total_amount`/`InvoiceLineItem#amount` math, never an LLM's arithmetic.
- **Unstructured prose** (meeting summaries/transcripts) is handled two ways depending on whether the record is already known:
  - **Already known** (the model has a `meeting.id` from a prior search): hand it the *whole* summary or transcript verbatim and let the model read and answer from it directly — no chunking, no retrieval step. This works because the data is small: the largest synced transcript is ~90K characters (~22.5K tokens), average ~21K characters (~5.3K tokens) — trivially cheap for a single tool result.
  - **Not yet known** (the question is about a topic, not a named meeting): semantic search over pre-embedded chunks (`search_meeting_content`) finds the right meeting by what was actually discussed in it, not by title or attendee name.
- Every discovery tool (`search_meetings`, `search_action_items`, `search_meeting_content` for meetings; the `project`/`month` resolution logic for invoicing) is the *only* way to obtain an identifier — no tool accepts a guessed `id`.

**Why not RAG for everything:** chunking + embedding + retrieving is strictly worse than "just read the whole document" when the document is already known and small — it fragments a document's narrative into disconnected pieces for no benefit. RAG is reserved for exactly the one problem it actually solves here: finding an unnamed meeting by content.

**Why not freeform SQL:** removes a whole class of risk (malformed/overly broad queries, prompt-injection-style attempts to read outside the intended scope, accidental writes) for no real gain — a fixed, growable set of tools covers every question this system needs to answer.

---

## 3. Architecture

```
User types a question (chat UI, Turbo Streams)
        │
        ▼
AiConversation / AiMessage (persisted history)
        │
        ▼
AiAssistant#ask ──▶ Anthropic API (Claude Opus 5, tool-use loop)
        │                    │
        │                    │  model picks a tool name + arguments
        │                    ▼
        │           tools_by_name lookup (AiAssistant::TOOL_PROVIDERS)
        │                    │
        │                    ▼
        │     InvoicingAssistantTools  or  MeetingAssistantTools
        │                    │
        │        ┌───────────┴────────────┐
        │        ▼                        ▼
        │   Postgres: invoices /     Postgres: meetings /
        │   invoice_line_items /     transcript_chunks
        │   project_mappings         (+ a live Voyage AI call
        │                             to embed the query, for
        │                             search_meeting_content)
        │        │                        │
        │        └───────────┬────────────┘
        │                    ▼
        │        exact tool result (JSON) returned to the model
        │                    │
        │       (loop continues while stop_reason == :tool_use,
        │        up to AiAssistant::MAX_TOOL_ITERATIONS)
        │                    ▼
        └──── Model composes the final natural-language reply
                             │
                             ▼
              Persisted as an AiMessage (with tool_calls audit log)
                             │
                             ▼
              Rendered into the chat UI via a Turbo Stream append
```

- **LLM:** Claude Opus 5 via the Anthropic API (`app/services/ai_assistant.rb`), a manual tool-use loop (not the SDK's beta tool runner, for full control over persisting the tool-call audit trail).
- **Tool dispatch is provider-agnostic:** `AiAssistant::TOOL_PROVIDERS = [InvoicingAssistantTools, MeetingAssistantTools].freeze`. A `tools_by_name` map (built once per `ask` call) routes each tool call to whichever provider defines it; the `tools:` param sent to the API is `TOOL_PROVIDERS.flat_map(&:definitions)`. Adding a third domain later means adding a third provider class to this array — nothing else changes.
- **The system prompt is built fresh per call** (`AiAssistant#system_prompt`, an instance method, not a frozen constant), so it can interpolate the current date and the asker's identity (`@conversation.user.email_address`) — needed so "my action items" resolves to a real person instead of nobody.
- **UI:** plain Rails views + Turbo Streams (`app/views/ai_conversations/`, `app/views/ai_messages/create.turbo_stream.erb`) — no SPA framework, matching the rest of this app. A submitted question appends the user/assistant messages in place and auto-scrolls (a small Stimulus controller), rather than a full page reload.
- **No background job on the question-answering path** — even `search_meeting_content`'s live embedding call happens synchronously within the request. The one background job in this system, `EmbedMeetingJob`, is on the *indexing* side (Section 5), not the *answering* side.

---

## 4. Tool surface

### Invoicing — `InvoicingAssistantTools`

| Tool | Arguments | Returns |
|---|---|---|
| `list_invoices` | `project` (optional, fuzzy name), `month_from`/`month_to` (optional, `"YYYY-MM"`) | `{name, month, project, total_amount, total_estimate_hours, line_item_count}[]` |
| `get_invoice` | `project` (optional), `month` (required) | One invoice's full detail, including every line item (title, ticket, rate, hours, billable, amount) |
| `sum_amount` | `project`, `month_from`/`month_to` (all optional) | Total billed amount across matching invoices (billable items only) |
| `top_line_item` | `metric: "estimate_hours"` (only supported value — see Section 6), `project`, `month_from`/`month_to`, `n` (default 1) | Top-N line items by the metric, with invoice/project/month context |
| `average_hourly_rate` | `project`, `month_from`/`month_to` (all optional) | Average `hourly_rate` across matching line items |
| `count_invoices` | `project`, `month_from`/`month_to` (all optional) | Count of matching invoices |

`project` is matched case-insensitively against `project_mappings.clickup_space_name`; anything other than exactly one match returns an ambiguity result rather than a guess. `month`/date ranges are `"YYYY-MM"` strings the model must resolve from natural language ("August" → this year's August unless context says otherwise).

### Meetings — `MeetingAssistantTools`

| Tool | Arguments | Returns |
|---|---|---|
| `search_meetings` | `query` (optional — title/attendee match), `date_from`/`date_to` (optional, `"YYYY-MM-DD"`) | Up to 10 `{id, title, recorded_at, duration_minutes, attendees, processing, fathom_url}`, plus `total_matches`/`truncated` |
| `get_meeting_summary` | `id` (required, from a prior search) | `{..., summary, action_items}` — `summary` is `nil` while `processing?`; each action item is `{description, assignee, completed, timestamp, playback_url}` |
| `get_meeting_transcript` | `id` (required) | `{title, transcript, fathom_url}`, or `{processing: true}` if not ready yet |
| `search_action_items` | `query`/`date_from`/`date_to` (same as `search_meetings`), `assignee` (optional — name or email substring), `completed` (optional boolean) | A flat list of action items across every matching meeting, each tagged with which meeting it came from, capped at 50 meetings scanned / 50 items returned |
| `search_meeting_content` | `query` (required, natural language), `date_from`/`date_to` (optional) | Top 8 `{meeting_id, meeting_title, recorded_at, fathom_url, source, excerpt, relevance}` results, ranked by semantic similarity |

`search_meetings`/`search_action_items`/`search_meeting_content` are the only ways to obtain a meeting `id` — `get_meeting_summary`/`get_meeting_transcript` never accept a guessed one. `search_meetings` and `Meeting.search` (the same method backing the Meetings module's own search box) only match a title or an attendee's name — never summary/transcript body text, which is exactly why `search_meeting_content` exists as a separate, complementary tool.

**Why two search tools instead of one:** they answer different question shapes. "The meeting with Usman" is a title/attendee lookup — cheap, exact, no embedding call needed (`search_meetings`). "Which meeting discussed the AWS migration" has no named anchor at all — it has to search *content* (`search_meeting_content`). The model picks based on whether the question names a specific person/title or a topic.

---

## 5. Semantic search subsystem

**What it's for:** finding a meeting by what was actually discussed in it, when no title or attendee name anchors the search.

**Embedding provider:** Voyage AI, model `voyage-4` (1024-dimension vectors). Chosen over OpenAI because it's Anthropic's own recommended embeddings partner (this app already only talks to Anthropic for its LLM) and, at this app's volume, cost is a non-issue either way — Voyage's current-generation models carry a 200M free-token allowance per account, and this app's entire embeddable corpus is ~1.6M tokens (about 0.8% of that allowance).

**Storage:** `pgvector` (the `vector` Postgres extension) via the `neighbor` gem — no separate vector-store service. A new `transcript_chunks` table:

```
meeting_id     — references meetings
source         — "summary" or "transcript"
chunk_index    — order within that source, for a given meeting
content        — the chunk's text
embedding      — vector(1024)
```

**Chunking (`MeetingChunker`):**
- Summaries split on markdown `## ` section headers (Fathom's own summary template uses them); falls back to one whole-summary chunk if none are found. Summaries are small (avg ~1.5K tokens, max ~3K), so this rarely produces more than a couple of chunks.
- Transcripts are walked line-by-line (`"Speaker: text"` lines), accumulating whole lines into a chunk until ~3,200 characters, then starting a new one — never splitting a line/speaker-turn mid-sentence. Yields ~6-7 chunks for an average meeting, up to ~28 for the longest synced one.

**Indexing pipeline:**
1. `EmbedMeetingJob.perform_later(meeting_id)` is enqueued from `Fathom::MeetingSync`, immediately after a meeting is saved, but only when its `summary` or `transcript` actually changed (`saved_change_to_summary?`/`saved_change_to_transcript?`) — covers both the webhook and manual-backfill sync paths automatically, and skips redundant re-embedding when nothing new arrived.
2. The job chunks the meeting (`MeetingChunker`), embeds every chunk's text in **one** batched Voyage call (`VoyageClient#embed_documents`, `input_type: "document"`) — not one call per chunk — then replaces the meeting's `transcript_chunks`.
3. `bin/rails embeddings:backfill` — a rake task for meetings that predate this feature, run synchronously (not via the job queue) with a 1-second pace between meetings so the pacing actually throttles the real API calls. Run once against all 239 meetings in this app's dev DB: 2,607 chunks (941 summary + 1,666 transcript), zero gaps, ~16.5 minutes.

**Querying:** `search_meeting_content` embeds the user's query with `input_type: "query"` (Voyage's embeddings are asymmetric between `"query"` and `"document"` — using the wrong one measurably hurts retrieval quality) and runs `TranscriptChunk.nearest_neighbors(:embedding, query_embedding, distance: "cosine")`, optionally scoped by a meeting date range, returning the top 8 chunks with a `relevance` score (`1 - cosine_distance`).

**`VoyageClient`** (`app/services/voyage_client.rb`) is a hand-rolled `Net::HTTP` client — same convention as this app's other external-API clients (`ClickupClient`, `HubstaffClient`, `FathomClient`) — including the same retry-with-backoff-on-429 pattern `FathomClient` already uses.

**Verified live**, not just described: asking "which meeting talked about AWS IAM roles" (a topic never in any title) correctly found and cited the right meeting from its content, and correctly named a second, weakly-related meeting as *not* the answer. Asking "has anyone raised pricing/budget concerns" (a paraphrase case — no single literal keyword ties the three real answers together) correctly surfaced three distinct meetings and distinguished genuine concern from routine pricing discussion.

**Known limitation, not fixed:** `Fathom::MeetingSync` discards each transcript segment's timestamp when flattening it into one string. A transcript-grounded answer can name the meeting and link to `fathom_url` (the recording as a whole) but not deep-link to the exact moment — unlike action items, which keep their own `recording_timestamp`/`recording_playback_url`. Revisit only if this turns out to matter in practice; the fix means restructuring `meetings.transcript` storage, which touches the sync code and the Meetings show page too.

---

## 6. Ambiguity and honesty rules

Enforced via `AiAssistant#system_prompt`, applied uniformly across both domains — a wrong or fabricated answer here is worse than no answer, since these could inform what gets billed to a client or what someone believes was agreed to in a meeting.

- **Never invent a number, quote, or fact.** Every claim comes from a tool result, never from the model's own reasoning about what's plausible.
- **Ambiguity gets a clarifying question, never a guess.** A `project`/`month` that doesn't resolve to exactly one match, a meeting search matching more than 10 results, or a name (e.g. "Usman") spanning multiple real people — all surface as a question back to the user, not a silent pick.
- **No matching data is reported plainly**, never filled in with a plausible-sounding invented answer.
- **"Hours" means estimated hours, and the assistant must say so.** Only `estimate_hours` (the ClickUp estimate) exists per line item today — there is no per-task "hours actually logged." Any answer touching hours must make clear it's the estimate, not logged time.
- **A meeting still processing in Fathom** (`Meeting#processing?`) is reported as "still processing" — never treated as if a blank summary/transcript means nothing was discussed.
- **Escalate from summary to transcript, not the reverse** — `get_meeting_transcript` is called only when a summary doesn't cover what was asked, and "not discussed" is only said after checking the transcript too.
- **Cross-meeting questions use `search_action_items`, not a loop.** Calling `get_meeting_summary` once per matched meeting doesn't scale and risks `MAX_TOOL_ITERATIONS`.
- **A low-relevance semantic match is inconclusive, not an answer.** `search_meeting_content`'s `relevance` score exists specifically so the model can distinguish "this is clearly it" from "this is a stretch" — verified working in practice.
- **Every claim is traceable.** A numeric answer names the invoice/project/line item it came from; a meeting-sourced claim names the meeting (title + date) and its Fathom link — so any answer can be checked against the source in one click.

---

## 7. Data model

| Table | Purpose | Status |
|---|---|---|
| `invoices`, `invoice_line_items`, `project_mappings` | Invoicing data the tools query | Pre-existing, reused as-is |
| `meetings` | Meeting metadata, summary, transcript, action items | Pre-existing (`FATHOM_INTEGRATION_SPEC.md`), reused as-is |
| `transcript_chunks` | Embedded chunks for semantic search | New this phase (Section 5) |
| `ai_conversations` | One row per chat session (`user_id`, `title`) | New — persists chat history across reloads |
| `ai_messages` | One row per turn (`role`, `content`, `tool_calls` jsonb) | New — `tool_calls` logs every tool invocation + its result, for audit |

No schema changes were needed to answer invoicing or the three keyword/structured meeting tools — only `search_meeting_content` required new storage.

---

## 8. Multi-tenancy / scoping

This app is single-user with no permission tiers today (master spec Open Question #4) — every tool operates over the full table it queries, with no per-user row-level scoping, matching the existing Invoices and Meetings UIs. If multi-tenancy is ever built, **every tool in Section 4 must be revisited** before this assistant could safely run in that setup — and meeting content deserves more scrutiny than invoice numbers when that happens, since it's inherently more sensitive (master spec Section 12's Fathom privacy/retention callout).

The one piece of "identity" that exists today is informational, not an access boundary: the system prompt names the logged-in user's email so "my action items" resolves to a real person. It does not filter *which* invoices or meetings a user can see — everyone sees everything, same as the rest of the app.

---

## 9. Out of scope / known limitations

- **No cross-source linking.** A meeting can't be tied to a ClickUp task/project, and an invoice line item can't be tied to a meeting — that linking layer doesn't exist for any source yet (master spec Sections 5, 11).
- **No Slack, GitHub, or Gmail data** — those sources aren't synced into this app at all yet.
- **No transcript-moment deep-linking** (Section 5's known limitation).
- **No write access anywhere.** The assistant only reads and reports — it cannot create/edit/delete an invoice, mark an action item done, or push anything back to Fathom.
- **No standalone Action Items Hub UI** (master spec Section 7.1) — the assistant can *answer* action-item questions, but there's no dedicated cross-source tracking screen.
- **No invoice line-item recommendation logic** (master spec Section 8's 4-way bill decision / variance flagging) — those don't exist yet either.
- **No multi-turn report generation** — one conversational answer per question, no scheduled/emailed digests.

---

## 10. Operational notes

- **Voyage account tier:** a fresh Voyage account defaults to a throttled 3 RPM/10K TPM until a payment method is added (an anti-abuse gate, not a cost decision — the 200M free tokens apply either way). Add a payment method before running a large backfill in any new environment.
- **pgvector must be installed on whatever Postgres this app runs against** — `brew install pgvector` locally (already done for this dev environment); production hosting for the extension is undetermined, since no `config/deploy.yml` exists yet (Kamal is an unconfigured default gem in this app). Flag this when deployment is actually set up.
- **Credentials:** `anthropic_api_key` and `voyage_api_key`, both via Rails encrypted credentials (`bin/rails credentials:edit`) or the matching `ANTHROPIC_API_KEY`/`VOYAGE_API_KEY` env vars.
- **Backfilling embeddings for new/re-synced meetings happens automatically** via the `Fathom::MeetingSync` hook — `bin/rails embeddings:backfill` is only needed for meetings that predate this feature, or after a bulk data change.

---

## 11. Open questions

1. **Which Claude model is actually optimal here** — Opus 5 works, but the tool surface is narrow enough that a cheaper model might do just as well; worth an eval before treating Opus 5 as the permanent choice.
2. **Conversation retention** — keep `ai_conversations`/`ai_messages` forever, or add a retention window, especially now that some conversations may reference sensitive meeting content.
3. **Chunk size tuning** — `MeetingChunker`'s ~3,200-character transcript window and header-based summary split are reasonable starting points, not tuned against a retrieval eval. Revisit if `search_meeting_content` starts missing things in practice.
4. **Action item confidence tiering** — once a second source's action items (Slack/Gmail-inferred, per master spec Section 7.1) reach this assistant, should replies distinguish "Fathom said this directly" from "an LLM inferred this"? Not urgent while Fathom is the only source.
5. **Should the assistant be reachable pre-scoped to a specific invoice or meeting** (e.g. an "ask about this" affordance on those pages), removing the need to restate which one you mean in the standalone chat.

---

## 12. Acceptance criteria

1. From the sidebar, a logged-in user reaches a working chat screen; conversations persist across reloads.
2. Invoicing questions (totals, top line items, counts, averages) return correct figures traceable to a specific invoice/line item, with the estimated-vs-logged-hours caveat stated where relevant.
3. An ambiguous project, month, or meeting-name reference prompts a clarifying question rather than a silent guess.
4. A question about a topic never mentioned in any meeting title (e.g. "AWS IAM roles," "budget concerns") is correctly answered via `search_meeting_content`, citing the right meeting(s) and dismissing weak matches rather than asserting them.
5. A meeting still processing in Fathom is reported as such, never treated as "nothing was discussed."
6. A cross-meeting question ("my action items this week") uses `search_action_items` in one call, filtered to the asker's identity — not a loop, and not everyone's items.
7. Every reply drawing on invoice or meeting data names its source (invoice/line item, or meeting title + Fathom link).
8. The assistant declines gracefully, without hallucinating, when asked about a source it doesn't have (Slack, GitHub, Gmail, or any cross-source link that doesn't exist).
9. `bin/rails embeddings:backfill` completes with zero gaps against every meeting that has a summary or transcript.
