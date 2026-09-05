# AI Assistant — Spec (Phase A: Invoicing)

**Status:** Draft v1
**Owner:** [you]
**Last updated:** 2026-09-05
**Relationship to master spec:** This is the first buildable slice of Section 9 ("Feature: AI Assistant") in `# Consolidated Work-Data Platform — Prod.md`. That section describes the long-run vision — a chat interface with retrieval across all six sources (Hubstaff, ClickUp, Slack, GitHub, Fathom, Gmail). This spec narrows that down to what's actually buildable *today*: invoicing is the only feature with persisted, structured data in the app right now (`invoices`, `invoice_line_items`, `project_mappings` — see Section 15.9 of the master spec), so it's the first domain the assistant answers questions about. Every other source stays a "Soon" concept until its own sync/linking work lands, per the master spec's phasing (Section 14).

---

## 1. Problem & Goal

Right now, answering a question like "what was the total for the August invoice?" or "which task had the most hours?" means opening the invoice, scanning line items, and doing the arithmetic by hand — for every invoice, every time. The data already exists (it's all in Postgres), it just has no natural-language interface.

**Goal:** Add a chat-style assistant, scoped to the invoicing data that already exists, that can answer ad hoc questions about invoices and their line items in plain English — accurately, using real numbers pulled from the database, not approximated from an LLM's own reasoning.

**Explicitly not this phase's goal:** answering questions about Slack, GitHub, Fathom, Gmail, or ClickUp/Hubstaff data that isn't already persisted as an `Invoice`/`InvoiceLineItem`. Those all depend on sync/linking work that hasn't been built yet (master spec Sections 4–5, 14).

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

- Anything not backed by `invoices`/`invoice_line_items`/`project_mappings` — no Slack, GitHub, Fathom, Gmail, or live ClickUp/Hubstaff API questions yet (that's Phase B/C, once those sources are synced per master spec Section 14).
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
