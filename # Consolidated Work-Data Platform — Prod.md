# Consolidated Work-Data Platform — Product Spec
### (Hubstaff · ClickUp · Slack · GitHub · Fathom · Gmail, linked around each task — invoicing and action items are features on top)

**Status:** Draft v1
**Owner:** [you]
**Last updated:** 2026-09-04

---

## 1. Problem & Goal

Right now, time worked (Hubstaff), planned/estimated work (ClickUp), team communication about that work (Slack), engineering activity (GitHub), and client/stakeholder requests (Gmail) all live in separate tools, with no shared spine connecting them. Every task's full story — what was scoped, what was discussed, what was built, what was asked for by email, what was actually billed — has to be manually reassembled by hand.

**Goal:** Build a **consolidated, linked data layer** that unifies all six sources around a common `task_id`, so that every task has one place showing its estimate, logged time, related Slack discussion, GitHub activity, meeting notes/transcripts, and email correspondence. This linked layer is the core product.

Everything else is a feature built **on top of** that consolidated layer, including:
- **Invoice reconciliation** (compare logged vs. estimated hours and decide what to bill) — the first feature to build, but not the only one.
- **Task 360° view** (single page showing everything tied to a task, across all sources).
- **Cross-source search** (find anything — a message, a PR, an email, a meeting mention, a time entry — regardless of which tool it lives in).
- **Action items hub** (every action item, from any source, in one place — with status you control).
- **AI assistant** (ask natural-language questions across all the linked data).
- **Connector & settings management** (a place to connect/disconnect each source, manage tokens, and control what's in scope — since the system is only as trustworthy as its access management).

The reconciliation/invoicing workflow described in Section 8 is one consumer of this data layer, not the product itself — the data layer should be designed so other features (reporting, search, task views, the AI assistant) can be added later without re-architecting the sync/linking logic.

---

## 2. Primary User

You (or a small ops/finance team) acting as the person who reviews time logs, reconciles them against scope, and generates client invoices for a services/agency-style business.

---

## 3. System Overview

```
 Hubstaff ─┐
 ClickUp ──┤
 Slack ────┼──▶ Sync Layer ────▶┌────────────────────────────┐
 GitHub ───┤       (ETL)        │   Consolidated Data Layer   │
 Gmail ────┤                    │  (linked by task_id/project)│
 Fathom ───┘                    └──────────────┬─────────────┘
                                                 │
   ┌───────────────┬───────────┬────────────────┼───────────────┬───────────────┬──────────────┐
   ▼               ▼           ▼                ▼               ▼               ▼              ▼
Task 360°     Cross-source  Action Items   Reconciliation   AI Assistant   Connector &    (future: reporting,
  View          Search        Hub          + Invoicing        (RAG)       Settings Mgmt   alerts, etc.)
```

Two layers, deliberately separated:

**A. The foundation (build first, gets reused by everything):**
1. **Sync Layer** — scheduled + on-demand connectors pulling data from each of the six sources into a normalized store.
2. **Linking Layer** — the logic that resolves a Hubstaff time entry, a Slack thread, a GitHub PR, a Fathom meeting, and an email to the *same* ClickUp `task_id` (see Section 5 for how each source links). This is the hardest and most valuable part of the system — it's what makes "consolidated" actually true rather than just "six things synced into one database."
3. **Data Store** — normalized schema holding tasks, time entries, messages, commits/PRs, meetings/transcripts, and emails, all foreign-keyed to `task_id`/`project_id`.

**B. Features built on the foundation (add incrementally, each is optional/independent):**
4. **Task 360° view** — one page per task showing its estimate, logged hours, related Slack threads, GitHub activity, meeting mentions, and emails.
5. **Cross-source search** — find anything regardless of which tool it originated in.
6. **Action items hub** — every action item detected across all sources, with a status you set (Section 7.3).
7. **Reconciliation Engine + Invoice Builder** — compares Hubstaff hours vs. ClickUp estimates and turns decisions into invoices (Section 8).
8. **AI Assistant** — a chat interface with retrieval access across all linked data to answer ad hoc questions (Section 9).
9. **Connector & Settings Management** — where connections, tokens, and per-source scope live (Section 10); technically part of the foundation's plumbing, but it's the one piece of the foundation you actually interact with directly, so it's listed as a feature too.

Because features B4–B9 all read from (or manage) the same data/linking layer, none of them require their own bespoke sync code — they're just different views/consumers of the same consolidated data.

---

## 4. Sync Strategy

The linking layer, search, reconciliation table, and AI assistant all depend on having a **local, indexed copy** of the data — you can't run cross-source joins or semantic search by calling five or six APIs live on every page load. So a synced local store isn't optional here; the real decision is *how* to keep it fresh. Three approaches, used in combination rather than picking just one:

| Approach | How it works | Best for |
|---|---|---|
| **Event-driven (webhooks)** | The source pushes a notification the moment something changes; you update just that record | Sources with webhook support, where freshness matters (ClickUp, Slack, GitHub, and Fathom if it offers one) |
| **Scheduled batch sync** | A job runs on a timer (e.g. nightly, hourly) and pulls/writes to the local store | Sources with no webhook support (Hubstaff), or as a safety-net reconciliation pass for everything |
| **Live/on-demand** | Call the API fresh at the moment of use, no local copy involved | Not a general strategy here — reserved for an explicit "refresh now" action layered on top of the synced store, for the one moment guaranteed freshness matters most (see 4.3) |

### 4.1 Pros and cons

**Scheduled batch sync**
- ✅ Simple to build and reason about; predictable API load; easy to retry failures
- ✅ Works for sources with no webhook support (Hubstaff)
- ❌ Data can be stale between syncs
- ❌ Wasteful if nothing changed since the last run

**Event-driven (webhooks)**
- ✅ Near-instant freshness; cheap, since you only process what changed
- ✅ Scales well as data volume grows
- ❌ More complex to build: needs a public endpoint, signature verification, retry/dedup handling, and a backfill mechanism for dropped events (webhook delivery isn't 100% reliable)
- ❌ Not available for every source (notably Hubstaff time/activity data)

**Live on-demand**
- ✅ Always accurate at the moment of the call
- ❌ Doesn't support cross-source search, linking, or the AI assistant on its own — you can't retrieve across sources you haven't stored
- ❌ Slow and rate-limit-risky if used as the default access pattern
- ❌ No resilience if a source's API is briefly down

### 4.2 Per-source recommendation

| Source | Webhooks available? | Recommendation |
|---|---|---|
| **ClickUp** | Yes, solid support | Event-driven — near-instant task/estimate/status updates |
| **Slack** | Yes (Events API) | Event-driven — messages indexed as they're posted |
| **GitHub** | Yes | Event-driven — PR/commit/comment events pushed instantly |
| **Fathom** | Confirm at build time; many meeting tools fire a "recording processed" event | Event-driven if available, else poll every few hours (meetings are low-frequency) |
| **Gmail** | Push via Cloud Pub/Sub exists but adds real setup complexity | Scheduled polling (e.g. every 15–30 min) is the pragmatic default |
| **Hubstaff** | No webhook for time/activity data | Scheduled polling — nightly full sync, since there's no event option |

### 4.3 The practical pattern

1. **Webhooks as the baseline** for ClickUp, Slack, GitHub, and Fathom (if supported) — keeps the core linking layer fresh with minimal lag.
2. **Nightly full sync for every source**, including the webhook-driven ones — a safety net that reconciles the local store against the source of truth and catches anything a dropped webhook missed. This matters more than it sounds; webhook delivery is not fully reliable.
3. **Scheduled polling for Hubstaff and Gmail** specifically, since they lack good event support — cadence tuned to how urgent freshness is for you (15–60 min).
4. **An explicit "refresh now" action on the invoice reconciliation screen** — the one workflow where stale Hubstaff data could mean billing the wrong amount, so it's worth letting you force a live pull right before finalizing an invoice, layered on top of the synced store rather than replacing it.

---

## 5. Integrations

### 5.1 Hubstaff (time logs)

- **APIs involved:** Hubstaff has *two separate APIs* with separate auth and IDs — the **Time Tracking API v2** (`api.hubstaff.com`) for time entries/activities/users/projects, and the separate **Hubstaff Tasks API** (`tasks.hubstaff.com/api`). If you use Hubstaff's built-in tasks feature at all, both need to be synced and their IDs cross-mapped; otherwise Tasks API can be skipped.
- **Important API limitation to design around:** Hubstaff does **not** expose a clean "session" endpoint. You get either:
  - **Daily Activities** (pre-aggregated per user/project/task/day) — cheaper, fewer requests, best for reconciliation totals.
  - **Raw Activities** (10-minute blocks) — needed only if you want exact start/stop timestamps or screenshot-level detail.
  - **Recommendation:** sync **daily aggregated activities** for the reconciliation engine (this is all you need for "hours logged per task"), and only pull raw activity blocks on demand if you need to audit a specific day.
- **Data to pull:** organizations → projects → users → tasks → daily activity (hours per user/project/task/day).
- **Auth:** OAuth2 or personal access token; token needs manager/owner role to see org-wide data. Rate limit: 1,000 requests/hour/app — daily aggregation keeps you well under this.
- **Sync cadence:** nightly full sync + on-demand "refresh" button before generating an invoice (to catch same-day entries).
- **Confirmed at build time — auth is not a plain Bearer token:** what Hubstaff calls a "Personal Access Token" is actually an OAuth2 **refresh token**, not something you can send directly as `Authorization: Bearer <token>`. It must first be exchanged via `POST https://account.hubstaff.com/access_tokens` (`grant_type=refresh_token`) for a short-lived access token (~24h) before any API call. That exchange **rotates the refresh token on every call** — the previous one stops working, so the new one must be persisted immediately — and the exchange endpoint itself is capped at **5 requests/hour**, separate from the general 1,000/hour API limit. In practice this means the access token (and its expiry) must be cached and only refreshed once expired, not re-exchanged per request.
- **Confirmed at build time — `activities/daily` params and pagination:** the endpoint takes `date[start]`, `date[stop]`, and `project_ids[]` query params (not guessable from the docs site, which is JS-gated). It **paginates at 100 rows/page** via a `pagination.next_page_start_id` cursor in the response, passed back as `page_start_id` for the next page — there is no total-count field, and a query that doesn't paginate through to the end silently truncates with no error. This was caught in testing: an unpaginated call undercounted a real project-month by 57% (190h shown vs. 445h actual) before the pagination loop was added. Each row is one **user × project × task × day**; sum the `tracked` field (seconds) for a project/month total — `manual` + `input_tracked` are that row's breakdown of `tracked` (manually entered vs. captured by the live tracker).
- **Open/unconfirmed:** Hubstaff aggregates "daily" activity in the **organization's own timezone**, while a naive integration sends plain UTC-based month boundaries for `date[start]`/`date[stop]`. Not yet confirmed as a real-world discrepancy, but worth checking against a live Hubstaff report if reconciliation totals look off by a day's worth of activity at a month boundary.

### 5.2 ClickUp (tasks, estimates, details)

- **Data to pull:** Spaces → Folders → Lists → Tasks, including: time estimate, custom fields, assignees, status, due dates, description, tags, linked docs, and *tracked time inside ClickUp* (ClickUp also has its own time tracking — worth deciding whether Hubstaff or ClickUp is the source of truth for "actual hours," see Open Question #1).
- **Auth:** ClickUp OAuth2 (or personal API token for a single-workspace MVP).
- **Mapping key:** each ClickUp task gets a canonical `task_id` in your data store — this is the anchor that Hubstaff time entries, Slack threads, GitHub PRs, and emails all get linked to.
- **Sync cadence:** near-real-time via ClickUp webhooks (task created/updated/time tracked) rather than polling, since ClickUp supports webhooks well.
- **Confirmed at build time — task fields and pagination:** `GET /list/{id}/task` excludes closed tasks unless `include_closed=true` is passed (status filters alone don't override this), and paginates at 100/page via `page=N` with no total-count field — loop until a page returns fewer than 100. Confirmed task fields: `custom_id` (nullable — fall back to `id` as the "ticket number" when absent), `name` (title), `time_estimate` (nullable, integer **milliseconds** — ClickUp's own OpenAPI spec incorrectly documents this as a string).
- **Confirmed at build time — space/folder/list hierarchy:** `GET /team` lists workspaces (this account has exactly one, matching the single-workspace MVP assumption above — now verified, not just assumed); `GET /team/{id}/space` lists spaces ("projects" in this spec's language); `GET /space/{id}/folder` conveniently returns each folder's `lists` (id/name) nested inline, so no extra per-folder call is needed; `GET /space/{id}/list` separately gives the folderless lists directly in a space.

### 5.3 Slack (contextual discussion)

- **Data to pull:** messages/threads that reference a task — via (a) explicit ClickUp/GitHub links pasted in Slack, (b) task ID or task name mentioned in text, (c) a dedicated channel-per-project convention if you have one.
- **"Intelligently refer" — how this actually works:** this is a semantic search/RAG problem, not a keyword match. Approach:
  1. Ingest and embed messages/threads (respecting channel permissions).
  2. When viewing a task (or building an invoice line item), the assistant retrieves the top-N semantically relevant threads by embedding similarity + explicit link matches, not just literal task-name string matches.
  3. Surface these as "related discussion" on the task detail view, with a link back to Slack.
- **Auth:** Slack app with `channels:history`, `search:read` (if using Slack's own search) or a stored/embedded index, scoped to channels you explicitly grant access to — do **not** default to indexing every private channel.
- **Privacy note:** decide up front which channels are in scope; indexing all of Slack by default is a real privacy/scope risk worth flagging to any team members before turning this on.

### 5.4 GitHub (engineering activity)

- **Data to pull:** commits, PRs, PR descriptions, linked issues, review comments — filtered by repo(s) you configure.
- **Linking to ClickUp:** GitHub doesn't know about ClickUp natively. Two reliable link mechanisms:
  1. **Convention-based:** commit messages / PR titles include the ClickUp task ID (e.g. `CU-abc123: fix login bug`) — cheap, reliable if enforced.
  2. **ClickUp's own GitHub integration:** ClickUp has a native GitHub app that auto-links PRs/commits to tasks — if you're already using it, pull the link data from ClickUp's API instead of re-deriving it, since it's already validated.
  - Recommendation: use ClickUp's native GitHub integration as the source of truth for task↔PR links, and use your own GitHub sync only to pull the *content* (diff size, PR description, review comments) for display and the AI assistant.
- **Auth:** GitHub App or PAT scoped to the specific org/repos, read-only.

### 5.5 Gmail (team/client requests)

- **Data to pull:** threads matching configured filters (e.g., specific labels, specific sender domains, or a shared inbox) — not your entire personal inbox by default.
- **Linking to tasks:** similar semantic approach as Slack — match by explicit task links/IDs mentioned in the email, plus semantic similarity for the AI assistant's retrieval.
- **Auth:** Gmail OAuth2, read-only scope (`gmail.readonly`) at minimum; **never** request send/modify scope unless you explicitly want the assistant to draft replies later — start read-only.
- **Privacy note:** even read-only email indexing should be opt-in and scoped (e.g. only a shared "clients@" inbox, not personal mail), since email content is sensitive.

### 5.6 Fathom (meeting notes & transcripts)

- **Data to pull:** meeting recordings' metadata (title, date, attendees, duration), AI-generated summaries, full transcripts, and any action items Fathom itself detects (Fathom already does action-item extraction natively — worth pulling that as a starting signal rather than re-deriving it from scratch, see Section 7.3).
- **Auth:** Fathom's API/MCP connector, read-only. Scope to specific team/workspace if Fathom supports meeting-level sharing permissions, same principle as Slack/Gmail — don't default to indexing every recording across the org if some are sensitive (1:1s, HR, etc.).
- **Linking to tasks:** same pattern as Slack/Gmail — explicit ClickUp task links/IDs mentioned during the meeting or in the summary, plus semantic matching (meeting is "about" a task/project even without an explicit link) for retrieval by the AI assistant and the Task 360° view.
- **Sync cadence:** event-driven if Fathom supports webhooks on "recording processed" — otherwise poll on a schedule (e.g. every few hours) since meetings aren't a high-frequency data source.
- **Note:** transcripts can be long — chunk them (e.g. by topic segment or speaker turn) before embedding, rather than embedding a whole 45-minute transcript as one block, so retrieval surfaces the relevant moment instead of the whole meeting.

---

## 6. Feature: Task 360° View & Cross-Source Search

These two are the most direct expression of "consolidated and linked" — worth building right after the sync/linking layer, even before invoicing gets polished, because they're the fastest way to prove the linking logic actually works.

### 6.1 Task 360° View
A single page per ClickUp task showing, in one place:
- ClickUp details: estimate, status, assignees, description, custom fields.
- Hubstaff: hours logged, by whom, by day.
- Slack: related threads (explicit links + semantic matches), most recent first.
- GitHub: linked PRs/commits, with status (open/merged) and review state.
- Fathom: related meeting mentions, with a jump-to-transcript-moment link and the meeting summary.
- Gmail: related email threads, if any.
- Open action items tied to this task (from any source — see Section 7), with their current status.
- A running "estimate vs. logged" indicator, so this doubles as a lightweight preview of what Section 8's reconciliation view will show at invoice time.

### 6.2 Cross-Source Search
A single search bar that queries across all linked data — e.g. searching a client name or feature name returns matching ClickUp tasks, Slack messages, GitHub PRs, meeting transcripts, and emails together, grouped by the `task_id`/`project_id` they're linked to (or ungrouped, for items with no confident link — see below).
- Structured filters (source, project, date range, person) on top of the text/semantic search.
- Anything the linking layer couldn't confidently match to a task should still be searchable and visible — surface it as "unlinked" rather than dropping it, so nothing silently disappears from the picture.

---

## 7. Feature: Action Items Hub

A single place to see every action item — regardless of which source it came from — and manage its status, instead of action items being scattered across ClickUp tasks, Slack messages, meeting notes, and emails with no single tracker.

### 7.1 Where action items come from
- **ClickUp:** subtasks/checklist items, or tasks below a certain size that function as action items.
- **Fathom:** action items Fathom's own AI already extracts from meetings — pull these directly rather than re-detecting them (highest-confidence source, since Fathom is purpose-built for this).
- **Slack:** messages that read as action items (e.g. "can you send X by Friday", someone assigned a to-do in a thread) — detected via an LLM pass over synced messages, since Slack has no native action-item concept.
- **Gmail:** requests/asks embedded in email threads — same LLM-detection approach as Slack.
- **GitHub:** PR review comments requesting changes, or issues explicitly opened as follow-ups.

Action items detected via LLM inference (Slack/Gmail/GitHub) should be flagged as **suggested** until you confirm them — don't silently promote an inferred action item to a tracked, assignable item without a human glancing at it once. ClickUp and Fathom items, which already carry explicit intent, can be trusted directly.

### 7.2 The Hub itself
- A flat, filterable list/board of all action items: source, linked task (if any), assignee, due date (if known), and status.
- Filters: by source, by project/task, by assignee, by status, by date range.
- Each item links back to its origin (the ClickUp checklist item, the Slack message, the Fathom transcript moment, the email, the PR comment).

### 7.3 Status you control
- Custom statuses, not just done/not-done — e.g. **Open → In Progress → Blocked → Done → Won't Do**, or your own set.
- Status changes here don't need to write back to the source system (e.g. marking a Fathom-sourced action item "Done" doesn't need to modify anything in Fathom) — this hub is your own layer of tracking on top of everything, not a two-way sync. (Two-way sync back to ClickUp specifically could be a later enhancement if useful — see Open Questions.)
- History/audit trail of status changes, same principle as invoice line-item overrides (Section 8).

---

## 8. Feature: Invoice Reconciliation

Invoicing is one consumer of the consolidated data — the same task-linked records that power the 360° view above feed directly into this flow. Proposed flow:

1. **Select scope** — pick a client/project and a date range.
2. **Pull comparison table**, one row per ClickUp task in scope:
   | Task | ClickUp Estimate | Hubstaff Hours Logged | Variance | Status | Related context |
   |---|---|---|---|---|---|
   - "Related context" = a count/link to relevant Slack threads, GitHub PRs, and emails (via the linking described above) — e.g. "3 Slack threads, 2 PRs" — click to expand.
3. **Flag variances automatically** — e.g. anything >20% over estimate, or hours logged with no matching ClickUp task, gets highlighted for review.
4. **Decision per line item** — for each task you can:
   - **Bill as logged** (use Hubstaff hours)
   - **Bill as estimated** (cap at ClickUp estimate, write off overage)
   - **Bill custom amount** (manual override, with a required note — this note is what justifies the decision later)
   - **Exclude** (don't bill this task at all — e.g. internal/non-billable work)
   - The AI assistant can propose a default recommendation per line item ("over by 4h, but GitHub shows 3 PRs and Slack shows a scope-change discussion on [date] — suggests billing as logged"), which you accept or override. It should never auto-decide without your sign-off.
5. **Generate invoice** — line items become the invoice, exportable as PDF/CSV or pushed to an accounting tool (QuickBooks/Xero — TBD, see Open Questions).
6. **Audit trail** — every override is stored with your note and timestamp, so future-you (or a client) can see why a line item was billed the way it was (same pattern as the Action Items Hub's status history, Section 7.3).

---

## 9. Feature: AI Assistant

A chat interface, scoped per-workspace, that can answer questions like:
- "How many hours did we log on Project X last month vs. estimate?"
- "What was decided in Slack about the scope change on task CU-123?"
- "Summarize the GitHub activity tied to this task."
- "Did the client email us about this feature before we built it?"
- "What did we agree to in the last client meeting?"
- "What action items are still open for Project X, and who owns them?"
- "Draft the variance explanation for this invoice."

**Implementation approach:**
- Retrieval-augmented generation over the normalized data store: Hubstaff activity, ClickUp task details, Slack messages, GitHub PR content, Fathom transcripts/summaries, Gmail threads, and action items — each chunked, embedded, and tagged with `task_id`/`project_id`/source/timestamp.
- Structured queries (hours, estimates, totals, action item counts/status) should hit the database directly rather than going through the LLM/embeddings, for accuracy — reserve retrieval+LLM for the unstructured "what was discussed / why" questions.
- Every answer that cites Slack/GitHub/Gmail/Fathom content should link back to the original source (for Fathom, deep-link to the transcript moment if the API supports it).

---

## 10. Feature: Connector & Settings Management

Every other feature depends on these six connections staying healthy, correctly scoped, and safely stored — so this needs to be a first-class screen, not an afterthought buried in a config file. Think of it as the control panel for everything described in Sections 4 and 5.

### 10.1 Connections dashboard
One screen listing all six sources, each showing:
- **Status:** Connected / Not connected / Needs reconnect (expired or revoked token) / Sync error.
- **Last synced at**, and whether the last sync succeeded — ties directly to the "visible last-synced-at status" requirement already called out in Section 12 (Non-Functional Requirements).
- A **Connect** button (starts the OAuth flow) or **Reconnect** button (for an expired token) per source.
- A **Disconnect** action that revokes the stored token and stops future syncs for that source (with a confirmation, since this affects every feature that reads from it — see the Explicit-permission pattern already used elsewhere in this system for destructive actions).

### 10.2 Token & credential handling
- Tokens/refresh tokens stored **encrypted at rest**; never displayed again in the UI once saved (show "Connected as [account/workspace name]" instead of the token itself).
- OAuth2 everywhere it's supported (ClickUp, Slack, GitHub App, Gmail, Fathom); Hubstaff falls back to a personal access token if OAuth2 isn't practical for a single-workspace setup — flag clearly in the UI which auth method is in use per source.
- Automatic token refresh where the provider supports it; if a refresh fails (revoked access, expired grant), surface it immediately as "Needs reconnect" rather than letting syncs silently fail.
- A single admin/owner-level permission gate on this whole screen (ties to Open Question #4 on team size — if this stays single-user, this is moot; if it becomes multi-user, connector credentials should not be editable by everyone).

### 10.3 Per-source scope controls
This is where the privacy/scope decisions flagged throughout Section 5 actually get configured, instead of being a one-time setup decision:
- **Slack:** allowlist of channels to index (add/remove channels without needing a full reconnect).
- **Gmail:** which labels/inboxes are in scope (e.g. a shared "clients@" inbox, specific labels) — not the full personal mailbox by default.
- **Fathom:** which workspace/team recordings are in scope; option to exclude specific meeting types (e.g. 1:1s) if Fathom's metadata supports that distinction.
- **GitHub:** which org(s)/repo(s) are synced.
- **ClickUp / Hubstaff:** which workspace(s)/organization(s) are synced (usually less of a privacy concern than the others, but still worth scoping if you work with multiple clients through the same accounts).
- Changing scope (e.g. adding a Slack channel) should trigger a backfill sync for the newly added scope, not just apply going forward.

### 10.4 Sync controls
- Manual **"Sync now"** per source, in addition to the automatic cadence from Section 4 — useful for troubleshooting or forcing freshness ad hoc, separate from the invoice-specific refresh action described in 4.3.
- Visibility into (and light control over) sync cadence per source where it's not purely event-driven — e.g. adjust the Hubstaff/Gmail polling interval within reasonable bounds, rather than it being a hardcoded value only visible in code.

### 10.5 Audit log
- A log of connection-level events: connected, disconnected, reconnected, scope changed, sync failures — separate from the invoice/action-item audit trails in Sections 8 and 7.3, but following the same principle: changes that affect what data the system can see should be traceable to who made them and when.

---

## 11. Data Model (high level)

- `organizations` / `clients`
- `projects` (mapped across Hubstaff project ↔ ClickUp space/folder/list)
- `tasks` (canonical, keyed by ClickUp task ID; stores estimate, status, assignees)
- `time_entries` (from Hubstaff, linked to `task_id`, daily-aggregated)
- `messages` (Slack, linked to `task_id` where matched, plus raw embedding for semantic search)
- `commits_prs` (GitHub, linked to `task_id` via ClickUp's GitHub integration data)
- `meetings` (Fathom, with `transcript_chunks` as a child table for embedded segments, linked to `task_id` where matched)
- `emails` (Gmail, linked to `task_id` where matched)
- `action_items` (source, source_ref, linked `task_id`, assignee, due_date, status, status_history, confirmed flag for LLM-inferred items)
- `invoices` / `invoice_line_items` (decision, override note, final amount, source snapshot at time of billing)
- `connections` (one row per source: auth method, encrypted token reference, status, last_synced_at, connected_by, connected_at)
- `connection_scopes` (per-connection allowlist entries — e.g. Slack channel IDs, Gmail labels, Fathom workspace/meeting filters, GitHub repos)
- `connection_events` (audit log: connected/disconnected/reconnected/scope_changed/sync_failed, who, when — backs Section 10.5)

---

## 12. Non-Functional Requirements

- **Auth:** OAuth2 for every integration; store tokens encrypted; per-integration scoped permissions (least privilege, especially Gmail/Slack/Fathom); see Section 10 for the full connector management feature.
- **Sync reliability:** each connector needs retry/backoff and a visible "last synced at" status; a failed sync should not silently produce a wrong invoice.
- **Auditability:** invoice decisions, action-item status changes, and connector/scope changes must all be traceable (who/when/why) — this matters as much as the automation itself.
- **Access control:** if more than one person uses this, decide who can override invoice line items or action-item status, and who can manage connector credentials/scope, vs. who can only view.
- **Data retention/privacy:** especially for Slack, Gmail, and Fathom (meeting transcripts can contain sensitive discussion) — define retention limits and which channels/inboxes/meetings are in scope before turning on indexing (configured via Section 10.3).

---

## 13. Open Questions (need your input before build)

1. **Source of truth for "actual hours":** ClickUp also tracks time. Is Hubstaff always authoritative, or does it vary by project?
2. **Invoicing output:** do you want a generated PDF only, or a push integration into an accounting tool (QuickBooks, Xero, FreshBooks)?
3. **Slack/Gmail/Fathom scope:** all channels/inboxes/meetings, or a defined allowlist? (Strongly recommend allowlist to start, especially for meetings that may include 1:1s or sensitive discussion.)
4. **Team size:** is this single-user (just you) or multi-user with roles/permissions?
5. **Hosting:** internal tool for your own use (simpler auth, single-tenant) vs. something you'd offer to other agencies (multi-tenant, much bigger scope)?
6. **Feature priority beyond invoicing:** does the Task 360° view, cross-source search, or the action items hub matter to you sooner than invoicing, or is invoicing still the most urgent pain point?
7. **Action item write-back:** should marking an item "Done" in the Action Items Hub ever push a status update back to ClickUp (two-way sync), or should the hub stay a read/track-only layer on top of the source systems?

---

## 14. Suggested Phasing

- **Phase 0 (Foundation):** Sync + linking layer for Hubstaff and ClickUp only — get the `task_id` linking logic working and validated before layering on anything else. Include a minimal connections dashboard (Section 10.1–10.2) here too — you need somewhere to plug in credentials before any sync can run at all, so this isn't really optional even in Phase 0, just kept bare-bones (connect/disconnect/status, no scope controls yet).
- **Phase 1:** Task 360° view for Hubstaff + ClickUp data (proves the linking layer works end-to-end), plus the invoice reconciliation flow (Section 8) — since that's the immediate business pain point.
- **Phase 2:** Add GitHub + Slack sync/linking, extend the Task 360° view and reconciliation flow with that context, add cross-source search, add the Action Items Hub (ClickUp + Slack + GitHub sources first). Extend the connections dashboard with per-source scope controls (Section 10.3) now that privacy-sensitive sources like Slack are in play.
- **Phase 3:** Add Fathom and Gmail integration, extend the Action Items Hub with those sources, add the AI assistant across all sources.
- **Phase 4:** Accounting tool export, multi-user roles, audit reporting, alerts/reporting features, optional two-way action-item sync.

Note the reordering vs. a naive build order: the sync/linking foundation comes before *any* feature, including invoicing — because once it's solid, invoicing, the 360° view, search, the action items hub, and the AI assistant all become relatively thin layers on top of it, rather than each needing its own integration work.

---

## 15. Phase 0 — Detailed Spec

*(Revised to match the concrete scope and flow below — supersedes the earlier draft of this section.)*

### 15.1 Objective

Ship the smallest working slice of the product: log in, connect Hubstaff and ClickUp with your own credentials, pick a project and its lists, and see a draft invoice screen listing those tasks alongside a top-line comparison of estimated vs. logged hours. No reconciliation decisions, no per-task hour matching, no other sources yet — just get real data from both tools sitting side by side in one screen, reliably.

**Definition of done:** you can log in, add Hubstaff and ClickUp credentials through the connector module, select a ClickUp project and one or more lists, and load an invoice draft page showing every task in those lists (title, ticket number, estimated hours) with an accurate total at the top for estimated hours vs. Hubstaff hours logged that month.

### 15.2 In scope

1. **Authentication & authorization** — users must log in to use the app; nothing here is publicly accessible. Keep this minimal: email/password login (Rails 8's built-in authentication generator, no Devise needed), one role for now (every logged-in user can manage connectors and create invoices — no permission tiers yet, that's Open Question #4/Section 10.2's multi-user question for later).
2. **Connector module** — a settings screen where you add credentials for Hubstaff and ClickUp (see 15.4) and see connection status. This is the bare-bones version of Section 10, not the full feature (no per-source scope allowlists yet — nothing privacy-sensitive is being synced in Phase 0).
3. **Hubstaff integration** — fetch activity logs (hours) via the Time Tracking API. See 15.5 for why this is a polling/on-demand fetch rather than a webhook.
4. **ClickUp integration** — fetch tasks for a chosen project's chosen list(s): task title, task ID/custom ID, and time estimate.
5. **Invoice draft flow** (15.3) — the concrete screen described below.

### 15.3 The flow, as specified

1. **Connector setup:** add Hubstaff credentials and ClickUp credentials once, in the connector module.
2. **Go to the Invoice module → select a project.**
3. **Select the list(s)** within that project to pull tasks from.
4. **Invoice draft page loads**, showing:
   - **Line items:** one row per task in the selected list(s) — **task title**, **ticket number**, **estimated hours**.
   - **Summary panel at the top:**
     - **Sum of estimated hours** across the selected tasks.
     - **Total hours logged in Hubstaff for that month** (for the project this invoice covers — see 15.6 on how the app knows which Hubstaff project that is).
   - No per-task actual-hours column and no bill/exclude decision controls yet — this page is a side-by-side sanity check between what was estimated and what was actually logged in aggregate, not the full reconciliation workflow from Section 8. That richer per-task comparison depends on Hubstaff-time-to-ClickUp-task linking, which is intentionally deferred (see 15.7).
5. A **month selector** on this page determines both which month's Hubstaff hours are totaled and (implicitly) the invoicing period — default to the current month, but let it be changed.

### 15.4 Connector module — credential handling

- One form per source (Hubstaff, ClickUp) to enter the required credential(s):
  - **ClickUp:** personal API token to start (simplest path for a single-workspace setup); OAuth2 can replace this later without changing the rest of the app, since the token is just stored and used the same way either way.
  - **Hubstaff:** personal access token (or OAuth2 if you'd rather set that up now — either works for Phase 0's read-only needs).
- Tokens stored **encrypted at rest** (Rails 8's built-in `encrypts` on the credential column — no extra gem needed).
- Connection status shown per source: Connected / Not connected / Error (e.g. invalid token, 401 on last fetch).
- A **Disconnect** action that deletes the stored credential.
- No scope controls yet (no channel/inbox allowlists — not applicable to Hubstaff/ClickUp, which don't carry the same privacy sensitivity as Slack/Gmail).

### 15.5 Hubstaff: polling vs. webhook

You mentioned fetching activity logs "or receive through webhook" — worth flagging directly: **Hubstaff's Time Tracking API does not offer webhooks for activity/time data.** There's no event Hubstaff will push you when time is logged. So for Hubstaff specifically, the only real options are:
- **Fetch on-demand**, when the invoice draft page loads (simplest for Phase 0 — always current, no background job needed yet).
- **Scheduled polling** (nightly or hourly) into a local cache, which the invoice page then reads from — better once you want faster page loads or plan to add more views on top of the same data.

**Recommendation for Phase 0:** fetch on-demand at invoice-draft-load time. It's the least infrastructure for the smallest scope, and it guarantees the "hours logged this month" figure is always live rather than possibly-stale — which matters more here than raw speed, since this number is exactly what someone would use to decide what to bill. Add scheduled polling in Phase 1+ once there's a reason to cache (e.g. the Task 360° view or dashboard needing fast repeated reads).

ClickUp, by contrast, does support webhooks — but Phase 0 doesn't need them yet either, since the invoice draft flow just needs a fresh fetch when you select a project/list, not standing real-time sync. A simple **on-demand fetch of tasks when a list is selected** is enough for this phase; webhook-driven background sync is a Phase 1+ upgrade once the Task 360° view and search need a persistently up-to-date local copy.

### 15.6 Which Hubstaff project does "hours logged this month" mean?

The summary panel needs a specific Hubstaff project to total hours against, but the user only selects a *ClickUp* project. Phase 0 needs a simple mapping to resolve this:
- A one-time **project mapping** step in the connector module (or on first use of the invoice module): pick which Hubstaff project corresponds to each ClickUp project you plan to invoice from. Store this as a simple `clickup_project_id ↔ hubstaff_project_id` pair.
- This is the same "project-level mapping" fallback discussed for the full reconciliation feature (Section 8) — Phase 0 just needs it immediately, since the summary panel can't compute a meaningful Hubstaff total without knowing which Hubstaff project to sum.
- If you're using Hubstaff's native ClickUp integration (Hubstaff imports ClickUp Spaces/Folders as Hubstaff projects automatically), this mapping may already exist implicitly — worth checking before building a manual mapping UI, since it could make this a non-issue. Confirm this before starting, same as flagged previously.

### 15.7 What's deliberately deferred

- **Task-level hour matching** (i.e., a "logged hours" column next to each task's estimate, not just an aggregate total) — this needs Hubstaff time entries linked to individual ClickUp tasks, which depends on the native-integration question above and is real additional work either way. Phase 0 ships the aggregate comparison only; per-task matching is Phase 1's Invoice Reconciliation feature (Section 8).
- **Bill/exclude/override decisions per line item**, invoice generation/export, audit trail — all Phase 1 (Section 8), not Phase 0.
- Multi-user roles, per-source scope controls, any other data source (Slack/GitHub/Fathom/Gmail).

### 15.8 Tech stack

- **Rails 8.1**, **Ruby 3.4**, Postgres.
- Rails 8's built-in authentication generator for login — no Devise needed for this simple a setup.
- Plain Rails views/Turbo for the connector module and invoice draft page — no separate frontend framework needed yet.
- No background job infrastructure required yet if going with on-demand fetch per 15.5 — Solid Queue can be introduced in Phase 1 once scheduled sync or webhooks are added.

### 15.9 Data model needed this phase

- `users` (email/password auth)
- `connections` (source, encrypted credential, status, last_used_at)
- `project_mappings` (clickup_project_id, hubstaff_project_id) — see 15.6
- No persistent `tasks` or `time_entries` tables strictly required yet if everything is fetched on-demand and rendered directly (per 15.5) rather than cached — simplest possible Phase 0. Add these tables in Phase 1 once caching/background sync is introduced.

**As actually implemented:**
- `connections` also has `access_token` and `access_token_expires_at` (both encrypted) — needed to cache Hubstaff's short-lived access token per the OAuth exchange described in §5.1, so it isn't re-exchanged on every request against that endpoint's 5/hour cap.
- `project_mappings` uses `clickup_space_id`/`clickup_space_name` (a ClickUp *Space*, i.e. "project" in this spec's language) rather than `clickup_project_id` — ClickUp has no "project" object of its own; Space is the closest equivalent and is what the connector UI lets you pick.
- The invoice draft flow (§15.3) is implemented as a stateless, GET-param-driven wizard (pick space → map to a Hubstaff project if not already mapped → pick list(s) → draft page), not session-backed — every step is a plain URL, so it's bookmarkable and needs no server-side wizard state. A mapping has no edit UI yet; "remapping" just deletes the `project_mapping` row and re-runs the mapping step.

### 15.10 Acceptance criteria

1. A user can log in and cannot access the connector module or invoice module while logged out.
2. Entering valid Hubstaff and ClickUp credentials in the connector module shows "Connected" for both; an invalid credential shows an error state rather than failing silently.
3. Selecting a ClickUp project and one or more lists loads the correct set of tasks with title, ticket number, and estimated hours for each.
4. The summary panel's "sum of estimated hours" matches manually adding up the estimates shown in the line items.
5. The summary panel's "hours logged in Hubstaff this month" matches what Hubstaff's own UI shows for the mapped project and selected month.
6. Changing the month selector updates the Hubstaff total accordingly without needing to reselect the project/lists.
7. Disconnecting a source in the connector module blocks the invoice flow from working until reconnected, with a clear message rather than a broken page.

---

## 16. Design System

Not part of the original spec, but adopted mid-build from a Claude Design mockup and now the visual baseline for every screen — future screens should match it rather than introduce new styling conventions.

- **Tokens:** Tailwind v4, configured CSS-first in `app/assets/tailwind/application.css` via `@theme` — a custom `brand` color scale (blue, `brand-400` as the primary action color) layered on Tailwind's stock `slate` scale for text/borders/surfaces, plus Google-Fonts-hosted **Inter** (`font-sans`, body/UI text) and **DM Sans** (`font-display`, headings/brand wordmark).
- **Icons:** Phosphor Icons (regular/bold/fill weights), loaded via CDN `<link>` tags in `app/views/layouts/_head.html.erb`.
- **App shell:** an authenticated layout (`app/views/layouts/application.html.erb`) rendering a persistent sidebar (`_sidebar.html.erb` — brand header, grouped nav with "Soon" badges for unbuilt sections) and topbar (`_topbar.html.erb` — per-page title/subtitle via `content_for`), versus a separate centered `guest.html.erb` layout for login/password screens.
- **Component conventions:** white cards on a `slate-50` app background (`bg-white border-slate-200 rounded-2xl shadow-sm`), `brand-400`/`brand-500` solid buttons, `slate-50`/`slate-200` input fields with a brand-colored focus ring — established first on the connector Settings and invoicing screens, reused from there.