# AI Assistant — Spec (Phase A: Invoicing)

**Status:** Phase A and Phase B shipped
**Owner:** [you]
**Last updated:** 2026-09-10
**Relationship to master spec:** This is the first buildable slice of Section 9 ("Feature: AI Assistant") in `# Consolidated Work-Data Platform — Prod.md`. That section describes the long-run vision — a chat interface with retrieval across all six sources (Hubstaff, ClickUp, Slack, GitHub, Fathom, Gmail). Phase A (below) narrows that down to what was buildable *first*: invoicing was the only feature with persisted, structured data in the app at the time (`invoices`, `invoice_line_items`, `project_mappings` — see Section 15.9 of the master spec). **Phase B (Section 12)** extends the assistant to Fathom meeting data, now that `FATHOM_INTEGRATION_SPEC.md` has shipped a real `meetings` table with synced summaries/transcripts — the second domain with persisted data the assistant can safely answer from. Slack, GitHub, and Gmail remain a "Soon" concept until their own sync/linking work lands, per the master spec's phasing (Section 14).

**As actually implemented, Phase B grew two pieces beyond Section 12's original design** (both driven by gaps found while implementing, not scope creep for its own sake):
- **`search_action_items`** — a 4th tool, added because "what are my action items from this week's meetings" would otherwise force one `get_meeting_summary` call per matched meeting. It scans across meetings in one call, filtered by `assignee` (name or email) and `completed`. Paired with an identity line in the system prompt (`AiAssistant#system_prompt`, naming the logged-in user's email) so "my action items" actually resolves to someone.
- **`search_meeting_content` — real semantic search, not deferred.** Section 12.3 originally deferred embeddings for lack of a felt need; implementing Section 12 surfaced a concrete one — `search_meetings`/`Meeting.search` only match a title or attendee name, so "which meeting discussed X" was unanswerable for any X not literally in a title. Fixed with Voyage AI embeddings (`voyage-4`, confirmed effectively free at this app's volume via live-fetched pricing — 200M free tokens/account against ~1.6M tokens to embed all 239 meetings) stored in a new `transcript_chunks` table (pgvector via the `neighbor` gem), populated by `EmbedMeetingJob` on every sync (`Fathom::MeetingSync`) and backfilled via `bin/rails embeddings:backfill`. Verified end-to-end against real synced data — e.g. correctly found a meeting discussing AWS IAM permissions and budget/pricing concerns across several meetings, in neither case because the topic appeared in a title.

---

## 1. Problem & Goal

Right now, answering a question like "what was the total for the August invoice?" or "which task had the most hours?" means opening the invoice, scanning line items, and doing the arithmetic by hand — for every invoice, every time. The data already exists (it's all in Postgres), it just has no natural-language interface.

**Goal:** Add a chat-style assistant, scoped to the invoicing data that already exists, that can answer ad hoc questions about invoices and their line items in plain English — accurately, using real numbers pulled from the database, not approximated from an LLM's own reasoning.

**Explicitly not this phase's goal:** answering questions about Slack, GitHub, Fathom, Gmail, or ClickUp/Hubstaff data that isn't already persisted as an `Invoice`/`InvoiceLineItem`. Those all depend on sync/linking work that hadn't been built yet at the time (master spec Sections 4–5, 14) — Fathom's has since landed (`FATHOM_INTEGRATION_SPEC.md`) and is covered by Phase B (Section 12); Slack/GitHub/Gmail are still unaddressed.

---

## 2. Example queries this phase must handle

Taken from the request that scoped this feature, plus a few more in the same spirit — all answerable from the current schema:

- "What was the total amount for the invoice in August?"
- "What was the highest task in terms of hours?" (see the important caveat in Section 6 — "hours" here can only mean *estimated* hours, not hours actually logged, given what's currently stored)
- "How many invoices do we have for [project]?"
- "What's the average hourly rate across [project]'s invoices?"
- "Which line items are marked non-billable on the August invoice?"
- "How much have we billed [project] in total this year?"
- "Which invoice had the biggest variance between billable and non-billable amounts?"

---

## 3. Why "LLM → DB query" instead of RAG/embeddings

The master spec already calls this out as a principle (Section 9): *"Structured queries (hours, estimates, totals, action item counts/status) should hit the database directly rather than going through the LLM/embeddings, for accuracy — reserve retrieval+LLM for the unstructured 'what was discussed / why' questions."*

Every example query in Section 2 is a structured aggregate (sum, max, count, average) over a handful of well-defined tables. There's no unstructured text to search yet (no Slack threads, no email bodies, no transcripts) — so embeddings/RAG would add real infrastructure (a vector store, chunking, embedding jobs) to solve a problem this phase doesn't have. RAG becomes worth it once Phase B/C add sources with actual prose to search (Slack messages, meeting transcripts, email bodies).

**Chosen approach:** the LLM's job is narrow — turn a natural-language question into a call to one of a small, fixed set of predefined query functions ("tools"), never into freeform SQL. The Ruby side executes the tool against ActiveRecord and returns exact numbers; the LLM only formats the result back into a sentence and, where useful, adds a one-line interpretation. This is the same "tool calling" pattern as the Claude API's tool use / `tool_runner` — the model proposes a tool name + arguments, the app runs it, the result goes back to the model to compose the final reply.

**Why not let the LLM write SQL directly:** it removes a whole class of risk (a malformed or overly broad query hitting the DB, prompt-injection-style attempts to read data outside invoicing, accidental writes) for no real gain at this data size — a handful of fixed tools cover every question in Section 2 and are trivial to extend.

---

## 4. Tool definitions (the assistant's fixed query surface)

Each tool below is a plain Ruby method, backed by the existing `Invoice` / `InvoiceLineItem` / `ProjectMapping` models — no new query logic beyond what these tools need; if a question doesn't map to one of these, the assistant says so rather than guessing (Section 6).

| Tool | Arguments | Returns | Backed by |
|---|---|---|---|
| `list_invoices` | `project` (optional, fuzzy-matched name), `month_from`/`month_to` (optional, `"YYYY-MM"`) | Array of `{name, month, project, total_amount, total_estimate_hours, line_item_count}` | `Invoice.joins(:project_mapping)`, filtered |
| `get_invoice` | `project` (optional), `month` (required, `"YYYY-MM"`) | One invoice's full detail: name, month, project, total amount, total estimate hours, and its line items (title, ticket, rate, hours, billable, amount) | `Invoice.find_by(project_mapping:, month:)` |
| `sum_amount` | `project` (optional), `month_from`/`month_to` (optional) | Total billed amount across matching invoices (billable line items only, matching `InvoiceLineItem#amount`) | Sums `invoice_line_items.amount` across matching invoices |
| `top_line_item` | `metric: "estimate_hours"` (only supported value this phase — see Section 6), `project` (optional), `month_from`/`month_to` (optional), `n` (default 1) | The top-N line items by the metric, each with its invoice/project/month for context | `InvoiceLineItem.joins(invoice: :project_mapping).order(estimate_hours: :desc).limit(n)` |
| `average_hourly_rate` | `project` (optional), `month_from`/`month_to` (optional) | Average `hourly_rate` across matching line items | `InvoiceLineItem` scoped, `.average(:hourly_rate)` |
| `count_invoices` | `project` (optional), `month_from`/`month_to` (optional) | Count of matching invoices | `Invoice` scoped `.count` |

All tools are read-only. None accept raw SQL, a table name, or a column name as an argument — every filterable dimension (`project`, `month`, `month_from`/`month_to`) is a fixed, named parameter the tool itself validates and applies.

**Resolving `project`:** matched (case-insensitively) against `project_mappings.clickup_space_name`. If a `project` argument doesn't match exactly one mapping (zero matches, or more than one — e.g. "the web project" matching two similarly-named spaces), the tool returns an ambiguity result rather than guessing, and the assistant asks the user to clarify (Section 6).

**Resolving `month`/date ranges:** the LLM is responsible for turning "August," "last month," "this year," "Q1" etc. into `"YYYY-MM"` values (or a `month_from`/`month_to` pair) before calling a tool, using the current date as context. "The invoice in August" with no year stated resolves to August of the current year; if that invoice doesn't exist, say so rather than silently returning nothing (Section 6).

---

## 5. Multi-tenancy / scoping

Per the master spec (Section 15.2), this app is currently single-user with no permission tiers — every logged-in user can already see every invoice. So this phase's tools don't need per-user row-level scoping; they operate over the full `invoices`/`invoice_line_items` table, same as the existing Invoices UI. If the master spec's multi-user question (Open Question #4) is ever resolved toward real multi-tenancy, every tool in Section 4 must be revisited to scope by organization/workspace before this assistant could safely run in that setup.

---

## 6. Ambiguity, gaps, and honesty — the assistant must never guess a number

This matters more here than in a typical chatbot: these answers could inform what gets billed to a client, so a wrong or fabricated number is worse than no answer.

- **"Hours" is ambiguous today, and the assistant must say so.** The current schema (per master spec Section 15.7, "deliberately deferred") only stores `estimate_hours` per line item — the ClickUp estimate. There is **no per-task "hours actually logged"** column yet; actual Hubstaff hours are only ever fetched in aggregate, at invoice-draft time, and not persisted per task. So "which task had the most hours" can only be answered as *"highest estimated hours"* — the assistant's reply must say explicitly that it's estimated hours, not logged hours, so no one mistakes one for the other. This limitation goes away once Phase 1's per-task Hubstaff↔ClickUp linking (master spec Section 8) ships; `top_line_item`'s `metric` argument is deliberately named/shaped so `"logged_hours"` can be added later without changing the tool's interface.
- **Ambiguous project or month:** if a `project` or `month` reference doesn't resolve to exactly one match (Section 4), the assistant asks a clarifying follow-up instead of picking one.
- **No matching data:** if a tool returns zero results (e.g. no invoice exists for the requested project/month), say so plainly — never let the LLM fill the gap with a plausible-sounding invented number.
- **Every numeric answer must be traceable:** the reply should name which invoice(s)/line item(s) the number came from (e.g. "$4,200, from the August invoice for Project X"), so the answer can be spot-checked against the invoice UI in one click.

---

## 7. Architecture

```
User types a question (chat UI)
        │
        ▼
Rails controller ──▶ Anthropic API (tool use)
                          │
                          │  model picks a tool + arguments
                          ▼
                   Ruby tool dispatcher (Section 4)
                          │
                          │  runs the actual ActiveRecord query
                          ▼
                   Postgres (invoices, invoice_line_items, project_mappings)
                          │
                          │  exact result returned to the model
                          ▼
                   Model composes the final natural-language reply
                          │
                          ▼
                   Rendered back into the chat UI (Turbo Stream)
```

- **LLM:** Claude via the Anthropic API's tool-use loop (`tool_runner` or an equivalent manual loop) — no other model needed for this phase.
- **UI:** a chat screen under the existing sidebar "AI Assistant" entry (`app/views/layouts/_sidebar.html.erb:17` already reserves this nav slot with a "Soon" badge) — plain Rails views + Turbo Streams for appending messages, consistent with the rest of the app's no-SPA-framework approach (master spec Section 15.8).
- **No background jobs needed:** each question is answered synchronously within the request/response cycle — tool calls are simple, fast ActiveRecord aggregates, not long-running jobs.

---

## 8. Data model needed this phase

Reuses `invoices`, `invoice_line_items`, and `project_mappings` as-is — **no schema changes needed for the tools themselves.**

Two new tables to persist chat history (so a conversation survives a page reload and can be revisited later):

- `ai_conversations` — `user_id`, `created_at`/`updated_at`. One per chat session; a "New conversation" action starts another.
- `ai_messages` — `ai_conversation_id`, `role` (`user`/`assistant`), `content` (text), `tool_calls` (jsonb, nullable — records which tool(s) were invoked and with what arguments, for debugging/audit), `created_at`.

Storing `tool_calls` alongside each assistant message means any answer can be audited later ("which invoice/line-items actually produced this number") without re-asking the question — the same auditability principle the master spec applies to invoice overrides and connector events (Sections 8, 10.5).

---

## 9. Out of scope this phase

- Anything not backed by `invoices`/`invoice_line_items`/`project_mappings` — no Slack, GitHub, Fathom, Gmail, or live ClickUp/Hubstaff API questions yet from *this* phase (Fathom/meetings is now covered by Phase B, Section 12; Slack/GitHub/Gmail remain Phase C+, once those sources are synced per master spec Section 14).
- The assistant proposing invoice line-item decisions (master spec Section 8's "AI Assistant can propose a default recommendation per line item") — that depends on the 4-way bill decision and variance flagging, which aren't built yet either.
- Any write access — this assistant only ever reads and reports; it cannot create, edit, or delete an invoice or line item on your behalf.
- Multi-turn "generate a whole report" style asks beyond a single conversational answer — no scheduled/emailed digests this phase.

---

## 10. Open questions

1. **Which Claude model** to use for this — the smallest/cheapest model that reliably picks the right tool and formats numbers correctly is preferable to a large one, given how narrow the tool surface is; worth a quick eval against the Section 2 example queries before committing.
2. **Conversation retention:** keep `ai_conversations`/`ai_messages` forever, or add a retention window? Low urgency at current data volume, but worth deciding alongside the master spec's broader data-retention question (Section 12).
3. **Should the assistant be reachable from inside an invoice's own page** (e.g. "ask about this invoice" pre-scoped to that invoice/month), in addition to the standalone chat screen — would remove the need to restate "the August invoice" every time while looking right at it.

---

## 11. Acceptance criteria

1. From the sidebar's "AI Assistant" entry, a logged-in user reaches a chat screen (no longer shows a "Soon" badge).
2. Asking "What was the total amount for the invoice in August?" (with exactly one invoice existing for that month) returns the correct dollar figure and names the invoice/project it came from.
3. Asking the same question when **two** projects both have an August invoice prompts a clarifying question naming both projects, rather than picking one silently.
4. Asking "What was the highest task in terms of hours?" returns the line item with the highest `estimate_hours`, names its task/ticket and invoice, and states that this is estimated (not logged) hours.
5. Asking about a month/project with no invoice returns a plain "no invoice found for X" answer, never a fabricated number.
6. Asking something outside this phase's scope (e.g. "what did the client say about this in Slack?") gets a clear "I can't answer that yet — I only have invoicing data right now" response, not a hallucinated answer.
7. Reloading the chat page after asking a question still shows the prior conversation (persisted via `ai_conversations`/`ai_messages`).
8. Every assistant reply containing a number can be traced back to the specific invoice(s)/line item(s) it was computed from (via the stored `tool_calls`, or visibly in the reply text itself).

---

## 12. Phase B — Meetings

*Extends the same chat assistant with a second tool provider, `MeetingAssistantTools`, covering the `meetings` table shipped by `FATHOM_INTEGRATION_SPEC.md`. Everything in Sections 1–11 above (the invoicing tools, the chat UI, `ai_conversations`/`ai_messages`) stays exactly as built — this section only adds to the tool surface the model can call.*

### 12.1 Problem & goal

Meetings are now synced with real summaries, transcripts, and action items (`FATHOM_INTEGRATION_SPEC.md`), browsable one at a time in the Meetings module — but "what did we agree to in the call with [client]?" or "what came out of last week's sync with [attendee]?" still means opening the Meetings list and scanning titles/dates by hand.

**Goal:** let the same assistant answer natural-language questions about meeting content — grounded in the actual synced summary/transcript/action-item text, never invented — and always point back to which meeting(s) an answer came from (title + link to Fathom), the same traceability principle Section 6 already applies to invoice numbers.

**Explicitly not this phase's goal:** linking a meeting to a ClickUp task/project (`FATHOM_INTEGRATION_SPEC.md` Section 9 — the linking layer doesn't exist for any source yet), or surfacing meeting action items in a standalone Action Items Hub (master spec Section 7.1 — still unbuilt; the assistant can *answer questions* about them without that Hub existing).

**As implemented, semantic/embedding-based retrieval turned out to be in scope after all** — see 12.3's "as implemented" note below for why the original deferral didn't survive contact with the rest of this section's own example queries.

### 12.2 Example queries this phase must handle

- "What was discussed in the meeting with [attendee]?"
- "What did we agree to in the last call with [attendee/client]?"
- "What are my action items from this week's meetings?"
- "Did we talk about [topic] in any recent meeting?"
- "Summarize the meeting from [date]."
- "Has Fathom finished processing the meeting from this morning?"

### 12.3 Why keyword search over `meetings`, not embeddings — yet

Section 3 already deferred RAG/embeddings for lack of any real unstructured text to search. That's no longer true — transcripts are real prose now — but embeddings are still not the right *next* step, for the same reason Phase 0 kept invoicing simple before building the full reconciliation engine (master spec Section 15): it's real infrastructure (a vector store, a chunking/embedding job, re-embedding on re-sync) to solve a problem this phase's data volume doesn't have yet. `Meeting.search` (built for the Meetings module's own search box) already does a reasonable job matching a query against title and attendee name at the database level; extending the assistant to use the *same* method, plus a plain-text scan of summaries for topic keywords, covers every example query in 12.2 without new infrastructure. Embeddings become worth it once semantic ("about X" without X being a literal word in the transcript) matching across a large meeting history is a real, felt gap — see Open Question 12.10.1.

**Chosen approach, mirroring Section 3's tool-calling pattern exactly:** a small, fixed tool surface — `search_meetings` to find candidate meetings, `get_meeting_summary` for the normal case, `get_meeting_transcript` as an explicit escalation when the summary doesn't have enough detail. The model decides when to escalate; it never receives a raw transcript unless it asked for one.

**As implemented — this section's conclusion changed, and here's exactly why:** `Meeting.search` only ever matches a `title` or an attendee's `"name"` — never the summary/transcript body (confirmed by reading `app/models/meeting.rb` directly, not assumed). That means "did we talk about [topic] in any recent meeting?" — one of this very section's own example queries (12.2) — was **structurally unanswerable** by the keyword-only design above, for any topic that doesn't happen to be in a title. That's not a "keyword search stops being good enough" scenario (Open Question 12.10.1 as originally written) — it's a hole from day one. Two more things changed the calculus versus when this section was first drafted:
- **Real pricing, fetched live rather than assumed:** Voyage AI's current-gen embedding models (`voyage-4`) give 200M free tokens/account; this app's entire 239-meeting backfill is ~1.6M tokens — about 0.8% of the free allowance. The "real infrastructure to solve a problem this phase's data volume doesn't have" framing above was right about the infrastructure cost, but the token cost turned out to be a non-issue at this volume, not a reason to wait.
- **pgvector is a Postgres extension, not a separate service** — `enable_extension "vector"` plus the `neighbor` gem gets ActiveRecord-native nearest-neighbor search with no new infrastructure service to run/operate, which is a meaningfully smaller lift than "a vector store" implied when this section was first written.

Built as a 5th tool, `search_meeting_content` (Section 12.4) — semantic search over chunked summaries/transcripts, verified end-to-end against real synced meetings (e.g. correctly found the meeting discussing AWS IAM permissions, and separately found three distinct meetings raising pricing/budget concerns — in neither case because the topic was in a title).

### 12.4 Tool definitions

| Tool | Arguments | Returns | Backed by |
|---|---|---|---|
| `search_meetings` | `query` (optional — matches title or attendee name), `date_from`/`date_to` (optional, `"YYYY-MM-DD"`) | Array of `{id, title, recorded_at, duration_minutes, attendees, processing, fathom_url}` for up to 10 matches, plus a count if more matched | `Meeting.search(query)` (the same method the Meetings index page's search box uses), further scoped by `recorded_at` |
| `get_meeting_summary` | `id` (required — a `meetings.id` from a prior `search_meetings` call) | `{title, recorded_at, attendees, summary, action_items, processing, fathom_url}` | `Meeting.find` |
| `get_meeting_transcript` | `id` (required) | `{title, transcript, fathom_url}` — the full transcript text | `Meeting.find` |

All three are read-only. `search_meetings` is deliberately the only discovery path — the model can't call `get_meeting_summary`/`get_meeting_transcript` with a guessed id, only one it already saw returned from a search, the same "never accept a free-floating identifier" discipline Section 4 applies to `project`/`month`.

**Capping `search_meetings` at 10 results:** if a query is vague enough to match more, the assistant should ask a clarifying question (which meeting, or narrow by date) rather than summarizing ten meetings at once — same ambiguity-handling principle as Section 6, applied to a list instead of a single ambiguous match.

**Why summary first, transcript second:** a full transcript can be many thousands of tokens; most questions ("what was decided," "what were the action items") are already answered by Fathom's own summary. Reserving the transcript for an explicit second call keeps the common case cheap and fast, and only pays the larger token cost when the model has already determined the summary doesn't cover what was asked. **As implemented, this was checked against real data rather than assumed:** the longest synced transcript is ~90K chars (~22.5K tokens), average ~21K chars (~5.3K tokens) — comfortably cheap for Opus 5's context window even on an escalation call, resolving Open Question 12.10.2 below.

**As implemented — two more tools, added for gaps found while building this:**

| Tool | Arguments | Returns | Backed by |
|---|---|---|---|
| `search_action_items` | `query`/`date_from`/`date_to` (same as `search_meetings`), `assignee` (optional — matches an action item's assignee name *or* email, case-insensitive substring), `completed` (optional boolean — open vs. done) | `{total_meetings_scanned, total_action_items, action_items: [...]}`, each item `{meeting_id, meeting_title, recorded_at, fathom_url, description, assignee, completed, timestamp, playback_url}` | Scans matching meetings' `action_items` jsonb directly, capped at 50 meetings/50 items |
| `search_meeting_content` | `query` (required — natural language), `date_from`/`date_to` (optional) | Top 8 `{meeting_id, meeting_title, recorded_at, fathom_url, source ("summary"/"transcript"), excerpt, relevance}` results, ranked by cosine similarity | `TranscriptChunk.nearest_neighbors(:embedding, query_embedding, distance: "cosine")` (`neighbor` gem over pgvector) |

- **Why `search_action_items` exists:** "what are my action items from this week's meetings" (Section 12.2's own example) would otherwise force one `get_meeting_summary` call per matched meeting — doesn't scale, and risks `AiAssistant::MAX_TOOL_ITERATIONS` on a busy week. One call, scanning across meetings, fixes both. `assignee` is what lets "my action items" resolve to anything at all — paired with a new identity line in `AiAssistant#system_prompt` naming the logged-in user's email, since nothing previously told the model who was asking.
- **Why `search_meeting_content` exists:** see 12.3's "as implemented" note — `search_meetings` can't find a meeting by what was discussed in it, only by title/attendee. This tool embeds the query (`VoyageClient#embed_query`, `input_type: "query"`) and searches pre-embedded chunks (`VoyageClient#embed_documents`, `input_type: "document"`, populated by `EmbedMeetingJob` — see Section 12.8). Voyage's embeddings are asymmetric between these two `input_type`s, so using the right one on each side isn't just documentation, it materially affects retrieval quality.
- **Chunking (`MeetingChunker`):** summaries split on markdown `## ` section headers (falling back to one chunk if none found — most are small enough, ~1.5K tokens average, that this rarely produces more than a couple); transcripts walked line-by-line, accumulating whole `"Speaker: text"` lines into a chunk until ~3,200 characters, never splitting a line mid-sentence. Verified against the largest real transcript: 28 transcript chunks + 4 summary chunks.
- **A weak semantic match must be treated as inconclusive, not an answer** — `relevance` (`1 - cosine_distance`) is returned specifically so the model (and `AiAssistant#system_prompt`) can tell "the best match I found is a stretch" from "this is clearly the meeting," rather than confidently asserting a low-relevance chunk is the answer.

### 12.5 Multi-tenancy / scoping

Same as Section 5 — this app is single-user with no permission tiers, so these tools operate over the full `meetings` table with no per-user scoping. Revisit alongside Section 5 if the master spec's multi-user question (Open Question #4) is ever resolved toward real multi-tenancy — and note that meeting content is more sensitive by nature than invoice numbers (master spec Section 12's privacy/retention callout for Fathom specifically), so a future multi-user pass here deserves *more* scrutiny than Section 5's, not the same amount.

### 12.6 Ambiguity, gaps, and honesty

- **No task/project linking exists yet** (Section 12.1) — a question like "what did we discuss about Project X" can only be answered via `search_meetings`' keyword/attendee match against titles and summaries, not a real link to that project. If nothing plausible turns up, say so rather than guessing a meeting is related because its topic sounds similar.
- **A meeting still processing in Fathom** (`Meeting#processing?` — no summary or transcript yet) must be reported as "still processing," never answered from a blank/absent field as if there were nothing to discuss.
- **More than 10 matches on a vague query:** ask which meeting, or narrow by date, rather than summarizing all of them (Section 12.4).
- **The summary alone doesn't answer the question:** call `get_meeting_transcript` before saying "not discussed" — only report an absence after checking the transcript too, not just the summary.
- **Every content claim must be traceable:** same principle as Section 6's numeric traceability — name the meeting (title + date) and its Fathom link for anything drawn from a summary/transcript, so it can be checked against the original recording in one click.
- **As implemented — two more honesty rules, for the two new tools:** a `search_meeting_content` match with low `relevance` must be reported as inconclusive rather than asserted as the answer (verified: asking about AWS IAM permissions, the assistant correctly named a second, weakly-related meeting as "touches on AWS only in passing... not the answer" rather than treating it as a second hit). And for cross-meeting questions, use `search_action_items` rather than looping `get_meeting_summary` per meeting — looping doesn't just waste calls, it risks silently hitting `MAX_TOOL_ITERATIONS` before covering every matched meeting.
- **Known, deliberate limitation, not fixed this pass:** `Fathom::MeetingSync` discards each transcript segment's timestamp when flattening it into one string (keeps only speaker+text). So a transcript-grounded answer can name the meeting and link to `fathom_url` (the recording as a whole), but can't deep-link to the exact moment discussed — unlike action items, which keep their own `recording_timestamp`/`recording_playback_url`. Revisit only if this turns out to matter in practice; fixing it means restructuring `meetings.transcript` storage, touching the sync code and the Meetings show page too, not just the assistant.

### 12.7 Architecture

Same shape as Section 7, with the tool dispatcher now spanning two provider classes instead of one:

```
User types a question (chat UI)
        │
        ▼
Rails controller ──▶ Anthropic API (tool use)
                          │
                          │  model picks a tool + arguments
                          ▼
           Ruby tool dispatcher — InvoicingAssistantTools
                          │         + MeetingAssistantTools
                          │  runs the actual ActiveRecord query
                          ▼
        Postgres (invoices/invoice_line_items/project_mappings,
                   or meetings, depending on the tool called)
                          │
                          │  exact result returned to the model
                          ▼
                   Model composes the final natural-language reply
                          │
                          ▼
                   Rendered back into the chat UI (Turbo Stream)
```

- **`AiAssistant` becomes tool-provider-agnostic:** today it hardcodes `InvoicingAssistantTools` in two places (`app/services/ai_assistant.rb` — the `tools:` param sent to the API, and the dispatcher in `tool_results_for`). This phase changes both to merge `InvoicingAssistantTools.definitions + MeetingAssistantTools.definitions`, and to route a tool call to whichever provider actually defines that tool name — a small refactor, not a rewrite; every invoicing tool keeps working exactly as before.
- **No background jobs, no new infra — for the 3 keyword/structured tools.** `search_meetings`/`get_meeting_summary`/`get_meeting_transcript`/`search_action_items` are all fast, single-table reads answered synchronously within the request, same as invoicing.

**As implemented:**
- `AiAssistant::TOOL_PROVIDERS = [InvoicingAssistantTools, MeetingAssistantTools].freeze` — a name→provider lookup (`tools_by_name`, memoized per `ask` call) replaces the old single-provider dispatch, falling back to an "unknown tool" error for anything unrecognized rather than silently misrouting.
- `SYSTEM_PROMPT` changed from a frozen class constant to a `system_prompt` instance method — needed to interpolate the conversation's user (for the "my action items" identity rule above) fresh per call, which also incidentally fixed a latent bug: the constant's `Date.current` interpolation only evaluated once at class-load time, so "today" could silently go stale between deploys in production.
- **`search_meeting_content` is the one tool that isn't a fast synchronous read on its own — it makes a live Voyage API call per question** (to embed the query) before the pgvector search. Still answered synchronously within the request (no background job for the *query* side); the background job (`EmbedMeetingJob`) is only on the *indexing* side, described in 12.8.

### 12.8 Data model needed this phase

For `search_meetings`/`get_meeting_summary`/`get_meeting_transcript`/`search_action_items`: none — reuses the `meetings` table exactly as `FATHOM_INTEGRATION_SPEC.md` created it. `ai_conversations`/`ai_messages` are unchanged; a meeting-answering turn's `tool_calls` log just contains these tool names instead of (or alongside) invoicing ones, same shape as today.

**As implemented — `search_meeting_content` needed real infrastructure, described here rather than treated as a footnote:**
- **`transcript_chunks` table** (`meeting_id`, `source` — `"summary"`/`"transcript"`, `chunk_index`, `content`, `embedding` — a `vector(1024)` column). `pgvector` enabled via `enable_extension "vector"` (installed locally as `brew install pgvector` for this app to actually run — not present in this dev Postgres before this phase; production hosting for the extension is still undetermined, since no `config/deploy.yml` exists yet).
- **`Meeting has_many :transcript_chunks, dependent: :destroy`.**
- **`VoyageClient`** (`app/services/voyage_client.rb`) — a hand-rolled `Net::HTTP` client, same convention as `ClickupClient`/`HubstaffClient`/`FathomClient`, calling Voyage AI's embeddings endpoint (`voyage-4`, 1024 dimensions). Retries 429s with backoff exactly like `FathomClient` already does — needed in practice: this account's Voyage API key was rate-limited to 3 requests/minute (an unverified-account default; Voyage's own error message says so directly) until a payment method was added, at which point it jumped to the standard 2,000 RPM tier — the 200M free tokens apply either way, this was purely an anti-abuse gate, not a cost decision.
- **`EmbedMeetingJob`** — embeds a meeting's chunks (one batched Voyage call per meeting, not one per chunk) and replaces its `transcript_chunks`. Enqueued from `Fathom::MeetingSync` right after `meeting.save!`, only when `saved_change_to_summary?`/`saved_change_to_transcript?` — so both the webhook and backfill sync paths pick it up automatically, and a resync with unchanged content doesn't re-embed for nothing.
- **`bin/rails embeddings:backfill`** — a rake task (not `perform_later`, deliberately synchronous with a 1-second pace between meetings) for embedding meetings that predate this feature. Run once against all 239 meetings already in this dev DB: 2,607 chunks created (941 summary + 1,666 transcript), zero gaps, in about 16.5 minutes.

### 12.9 Out of scope this phase

- Linking meetings to ClickUp tasks/projects, or answering with confidence that a meeting is "about" a project without an explicit textual match (Section 12.1/12.6).
- ~~Semantic/embedding-based retrieval (Section 12.3) — matching stays keyword/attendee-based via `Meeting.search`.~~ **As implemented: built, not deferred — see 12.3/12.4/12.8.**
- Deep-linking a transcript-grounded answer to the exact moment discussed (only the meeting as a whole, via `fathom_url`) — see the "known, deliberate limitation" note in Section 12.6.
- A standalone Action Items Hub (master spec Section 7.1) — the assistant can answer "what are my action items from meeting X" (or across several meetings, via `search_action_items`), but there's still no dedicated UI listing/tracking them across sources.
- Cross-referencing a meeting with an invoice or Slack/GitHub/Gmail content — those sources still don't exist in this app.
- Any write access, same as Section 9 — the assistant cannot edit a meeting, mark an action item done, or push anything back to Fathom.

### 12.10 Open questions

1. ~~**When does keyword search stop being good enough?**~~ **Resolved — didn't wait for it to become a felt gap.** Reading this section's own example queries against the real `Meeting.search` implementation showed the gap was structural, not usage-dependent (Section 12.3's "as implemented" note) — built `search_meeting_content` instead of waiting to observe the pain.
2. ~~**Transcript size**~~ **Resolved, checked against real data:** longest ~90K chars (~22.5K tokens), average ~21K chars (~5.3K tokens) — trivially cheap either as a whole `get_meeting_transcript` call or chunked for embedding.
3. **Action item confidence tiering:** master spec Section 7.1 treats Fathom action items as high-confidence (pull directly) vs. Slack/Gmail-inferred ones (flag as "suggested"). Once another source's action items reach this assistant, should replies distinguish "Fathom said this directly" from "an LLM inferred this from a message" — not urgent while Fathom is the only source, but worth deciding before Phase C adds another one.
4. **Chunk size tuning:** `MeetingChunker`'s ~3,200-character transcript window and markdown-header-based summary split were reasonable starting points, not tuned against a retrieval eval — worth revisiting if `search_meeting_content` misses things in practice (e.g. a topic split awkwardly across a chunk boundary).
5. **Voyage account tier for future environments:** this dev account needed a payment method added before the standard 2,000 RPM tier applied (started at an unverified-account default of 3 RPM/10K TPM) — the 200M free tokens apply regardless, but a fresh staging/production Voyage account will hit the same gate on its first backfill unless a payment method is added ahead of time.
6. **Production hosting for pgvector:** no `config/deploy.yml` exists yet (Kamal is an unconfigured default gem) — whatever Postgres ends up hosting production needs the `vector` extension available. Not a blocker now; flag it when deployment is actually set up.

### 12.11 Acceptance criteria

1. Asking "What was discussed in the meeting with [attendee]?" (one clear match) finds it via `search_meetings`, answers from its summary, and names the meeting + links to it.
2. Asking a question a summary doesn't cover triggers a `get_meeting_transcript` call and answers from the actual transcript content, not just the summary.
3. Asking about a meeting/topic with no matching meeting returns a plain "no matching meeting found" answer, never a fabricated one.
4. A vague query matching more than 10 meetings prompts a clarifying question (which meeting, or narrow by date) instead of summarizing all of them.
5. Asking about a meeting still processing in Fathom says so explicitly, rather than treating a blank summary/transcript as "nothing was discussed."
6. Every reply that draws on meeting content names the meeting and includes a way back to it (its Fathom link).
7. Every invoicing question from Sections 1–11 still works exactly as before — the merged tool surface is additive, not a regression.

**As implemented — verified live against this dev DB's 239 real synced meetings (not just described):**

8. Asking "Which meeting talked about AWS IAM roles?" (a topic never in any meeting's title) uses `search_meeting_content` and correctly finds/cites the right meeting — confirmed working, including correctly naming a second, weakly-related meeting as *not* the answer rather than treating it as a match.
9. Asking "Has anyone raised pricing/budget concerns in any meeting?" (the paraphrase/synonym case, not a literal keyword match) correctly surfaces multiple distinct real meetings and distinguishes an actual concern from routine pricing discussion.
10. Asking "What are my open action items from the meeting with Usman?" — with 19 meetings matching "Usman" — correctly asks for clarification, uses `search_action_items` filtered to the logged-in user's identity (from `AiAssistant#system_prompt`) rather than every attendee's items, and (unprompted) flags that "Usman" spans two different people in the matched meetings.
11. Every invoicing question from Sections 1–11 still works unchanged after the `TOOL_PROVIDERS` dispatch refactor — re-verified, not just assumed additive.
12. `bin/rails embeddings:backfill` against all 239 existing meetings completes with zero gaps (every meeting with a summary or transcript has `transcript_chunks`).
