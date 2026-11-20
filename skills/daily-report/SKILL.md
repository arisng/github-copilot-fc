---
name: daily-report
description: "Generate a one-page daily report for one git user, grounded in a single calendar day: git proof plus repo-scoped Copilot session evidence, rendered as `reports/daily/{git user}/yymmdd.md` with `created`/`updated` frontmatter, a personal glossary at `glossary.md`, and one turns-only HTML transcript per cited session under `sessions/{session-slug}.html`. USE THIS SKILL whenever the user asks what was done in a time range or wants their daily report, in English or Vietnamese: 'daily report', 'daily standup', 'daily update', 'what did I work on', 'yesterday's work', 'what did I do today', 'generate a report from 9h to 13h today', 'tạo báo cáo hôm nay'. Also for backfilling a date range (batch mode). NOT for: weekly or monthly stakeholder summaries, pull-request description writing."
user-invocable: true
disable-model-invocation: true
metadata:
  version: 1.0.0
  author: arisng
---

# Daily Report Generator

Builds **one** daily report file per git user per calendar day, grounded strictly
in what that user actually did: git proof and repo-scoped Copilot session
evidence for one day become the report. The report covers **the runner only** —
Step 0 identity is the attribution boundary. Finished outcomes map to
**Completed Today** (Why → Result → Refs), open work maps to **Under Review** /
**Active Work** / **Blockers & Risks** / **Next Up**, special vocabulary maps to
**Glossary**. The output is a **one-page executive report**: signal over noise —
outcomes and decisions only, never a change log of files.

This skill owns every script it runs, under `scripts/`. It never calls into
another skill's scripts.

## Arguments

- **date** — the report's calendar day (`yyyy-MM-dd`), default today (machine
  local time). Grounding covers exactly this one day; anything wider is refused.
- **window** — optional same-day range (e.g. `9h-13h`, `13:00-18:00`). It scopes
  the grounding query only; the report body never names it.
- **batch** — a date range request ("backfill reports for 2026-11-01 to
  2026-11-07") routes to Batch mode below.
- Ambiguous input (which date?) → lock it with `ask_user` first.

## Config

- **`repo_names`** — the repositories this skill may report on. A LIST; sessions
  and commits outside it never enter the report. Default: the repository of the
  current checkout (`owner/name` from `git remote get-url origin`). Override per
  machine with `DAILY_REPORT_REPOS` (comma-separated).
- **Multi-machine rule** — this skill runs on more than one machine. Never assume
  one machine's paths or environment exist on another. Resolve every path at run
  time (`git rev-parse --show-toplevel`, `$env:` variables, the session store).
  The repository name is the only identity the machines share.

## Procedure

### 1. Parse the day (and window) and derive the timezone

- The day is one calendar date. An optional window must stay inside it.
- **The UTC offset is derived at runtime** from the generating machine
  (`(Get-Date).ToString('zzz')`) and stamped into the frontmatter — never
  hardcode an offset.

### 2. Ground — two mandatory sources, then link verification

**Step 0 — identify the runner.** A report describes one person's work only.

- GitHub login: `gh api user -q .login`.
- Git identity: `git config user.name` and `git config user.email`.
- Repository: `git remote get-url origin` → `owner/name`, checked against
  `repo_names`. Stop and ask when it does not match.
- Derive `{git user}`: sanitize `git config user.name` — replace any character
  outside `[A-Za-z0-9._-]` with `-`. The same token names the user folder and
  the glossary owner.

1. **Git proof (mandatory — once per repository in `repo_names`).**
   Resolve each repository's local checkout at run time — the current checkout
   when it matches, otherwise ask the conductor (never assume another machine's
   paths) — and run
   `scripts/Get-GitProof.ps1 -Date "<yyyy-MM-dd>" [-Start "<local HH:mm>" -End "<local HH:mm>"] -RepoRoot <checkout>`
   once per checkout. Emits JSON: the runner's commits in the day with files,
   line counts, branch containment, pushed-or-local state; host checkpoint
   commits excluded; `git status` for uncommitted work; and a `workingTree`
   list of files created or modified inside the window that carry no commit yet —
   a new artifact that was never committed is still proof. **Merge the proof
   rows across repositories. Every Completed candidate must map to at least one
   proof row (a commit or an in-window working-tree file), one pull request, or
   an explicit completion statement;** with no proof, drop the item or state the
   gap. A repository with no local checkout is skipped and named as a grounding
   gap.
2. **Session evidence (mandatory — once per repository in `repo_names`).**
   `scripts/Get-SessionEvidence.ps1 -Date "<yyyy-MM-dd>" -RepoRoot <checkout>`
   once per resolved checkout.
   Emits JSON from the Copilot session store, scoped to `sessions.repository`
   matching that checkout — the script refuses unfiltered queries. For the
   cloud store, export the same day and repo scope through the harness
   session-store query and merge with `-CloudJson <file>`; out-of-scope rows are
   refused. Each session carries `windowTurns` — every turn inside the window
   with truncated text. **Scan all of them**: the first and last messages are
   orientation only, and action invocations, verdicts, and file writes often sit
   in middle turns; never substitute conversation memory for the queried turns.
   Zero rows is a real result: the report must state that grounding gap
   instead of reading like a day off.
3. **Link verification (only).** `gh` verifies references the two sources
   produced — issue and pull request numbers must exist on GitHub
   (`gh issue view <n>`). `gh` is **not** a grounding source.

Commits by other authors that arrive through a pull are not the runner's work —
never list them as Done. Commit hashes are grounding only; the report never
prints them.

### 3. Render

Read `templates/report.md` — the contract. Section order is
completion-first: Completed → Under Review → Active Work → Blockers → Next Up.

**Read the canonical glossary before rendering** (`reports/daily/<git user>/glossary.md`)
so `NEW` and `known` are correct: `NEW` = absent from canonical, `known` = present.
This comparison is the only de-duplication the Glossary has.

**Never reported** (in any section):

- Routine repository maintenance — branch syncs, pulls, fetches, status checks.
- Report production itself — the report never lists its own making.

- **🏆 Completed Today** — an outcome that finished inside the queried day (or
  window). At most 4 items, each at most 4 lines:
  - **Why** — one sentence; the purpose, never "because it was assigned".
  - **Result** — one sentence; the verifiable state change, with the action verbs.
  - **Refs** — ONE line with 2 to 4 pointers: a bare session id, a hyperlinked
    issue or pull request, a check result written as a short label with its
    outcome (`quality gate → PASS` — never a full shell command), a file path.
    Never commit hashes, turn numbers, or window tags.
- **👀 Under Review** — work waiting for feedback or approval at day end.
  Item | Awaiting | Where. At most 3 rows.
- **🚀 Active Work** — still open at day end. Task | Why | Current State.
  At most 3 rows.
- **⚠️ Blockers & Risks** — what is stuck and who holds it. At most 3 rows.
- **📋 Next Up** — top priorities for the next run. At most 4 items.
- **Glossary** — the runner's personal-growth record: the day's terms for this
  git user only. Harvest from grounding (issue titles and headings, artifact
  section names, session terms); a heavy term of the day missing is a defect.
  Not extracted from the workflow blueprint; when a term is defined there, the
  blueprint is one meaning source. Render `Term | Status | Meaning` with `NEW`
  first, at most 8 rows; every `known` row's meaning matches canonical verbatim.
  Never drop a NEW term for a known one — cut a repeated known row instead.

Other rules:

- **Classify by signals** — Completed only when a proof row (a commit or an
  in-window working-tree file), a pull request, or an explicit completion
  statement backs it. Group sessions that share a branch and topic into one item.
- **Executive budget** — frontmatter plus body fit one page: at most 56 lines and
  600 words. Over budget → cut the lowest-signal rows first, never Why/Result
  meaning (`templates/report.md`, "Cut rows, never meaning").
- **Signal over noise** — outcomes and decisions only; name an artifact only
  through the refs line.
- **Timeless body** — no clock times, timestamps, or dates in the text. Time
  lives only in the `created`/`updated` frontmatter stamps.
- **Simplified Technical English** — active voice, one idea per sentence, at most
  25 words per sentence, no semicolons, no phrasal verbs, noun piles of at most
  three words, and a list whenever a sequence has three or more steps. Field
  labels stay literal; the rules shape the sentences written inside them.

### 4. Write the output

**Folder and naming (enforced):** `reports/daily/<git user>/yymmdd.md`, where
`yymmdd` is the report's date (e.g. `261110.md`). The report always lives in the
**invoking checkout's** `reports/daily/`, even when grounding spans repositories.
The user folder also holds
that user's single `glossary.md`. A path outside the runner's own folder is
refused — two users on one day produce two folders, never one merged file.

**Session transcript exports (enforced):** right after the report file is
written, run `scripts/Export-SessionTranscripts.ps1 -ReportPath <path>`. It
reads every session the body mentions (``session `xxxxxxxx` `` — the slug is
that id, lowercased; `grill session` mentions are never exported) and writes
one self-contained HTML file per session to `sessions/<session-slug>.html`
beside the report. The session data comes from **this machine's** Copilot state
(`$env:COPILOT_HOME`, else `~/.copilot`): `events.jsonl` first, then the
session store. A session this machine does not hold gets an explicit
"not available" notice page instead of a silent skip. The JSON receipt
reports `total` / `exported` / `notice` / `kept` — quote it in the report-back.
Existing exports are never rewritten (pass `-Refresh` to re-export). The
exported `.html` files are git-ignored local artifacts, never committed.

**Frontmatter (enforced):** exactly two stamps, local time with the runtime
offset:

```yaml
---
created: 2026-11-10 13:57 +07:00
updated: 2026-11-11 09:17 +07:00
---
```

No `covers` field and no `Covers:` line — the window does its work at query time
and stays out of the report.

**Rerun rule — one file per date per user.** A rerun updates the file in place:
preserve `created`, refresh `updated`, merge the new outcomes, re-apply the
one-page budget. Never create a second file. A legacy file (the older flat
`Daily Report - ...md` names, or `glossary-{user}.md`) belongs to the runner —
rename it into this folder/naming before updating.

### 5. Glossary upkeep — semantics only

- Purpose: the git user's **personal glossary** — it grows day by day with that
  person's vocabulary. One per user, never shared.
- Harvest the day's terms, judge `NEW`/`known` from the canonical read, decide
  the op per term (`insert` new, `refresh` a richer meaning, `keep` the stored
  one). **Mechanics belong to the script:**
  `scripts/Merge-Glossary.ps1 -RepoRoot <root> -GitUser <git user> -TermsJson '<json>'`.
  The script parses, validates, sorts, escapes, writes atomically, and emits a
  JSON receipt `{added, refreshed, kept, total, changed}` — **quote that receipt
  in the report-back**. The pinned format is `templates/glossary.md`.

### 6. Validate, then report back

- `scripts/Test-DailyReport.ps1 -RepoRoot <root> -GitUser <git user> -Date <yyyy-MM-dd>`
  must **PASS** before reporting back. It enforces path/naming, the frontmatter
  schema, the timeless body, structure and caps, refs format, the session
  transcript exports (every mentioned session must have its
  `sessions/<slug>.html`), the budget, and report-to-canonical glossary
  consistency (failures are line-specific).
- Report back: the file path, counts (N Completed, M Active), created/updated
  stamps, the glossary receipt, the transcript-export receipt
  (`exported`/`notice`/`kept`), and any grounding gap.

## Batch mode (backfill)

For a date range request, use `scripts/Invoke-DailyReportBatch.ps1
-StartDate <yyyy-MM-dd> -EndDate <yyyy-MM-dd>`. It is strictly a **loop over the
single-day path** — no separate rendering logic:

1. The script enumerates the days, applies the existence policy, and collects
   per-day evidence (Get-GitProof + Get-SessionEvidence). Policy: **skip** days
   whose report exists (default — cheap, never clobbers) or **regenerate** with
   `-Regenerate`. Isolation: a failing day is reported and the loop continues;
   the batch writes no report files, so it can never leave a half-written file.
2. For each day with evidence, render the single-day report (this procedure,
   which includes its session-transcript export), then `Merge-Glossary`, then
   `Test-DailyReport`.
3. Validate the range afterwards with `Invoke-DailyReportBatch.ps1 ... -Validate`.

## Scripts (this skill owns all of them)

| Script | Responsibility |
| --- | --- |
| `scripts/Get-GitProof.ps1` | Single-day, author-filtered, checkpoint-excluding git evidence as JSON. |
| `scripts/Get-SessionEvidence.ps1` | Single-day Copilot session evidence, scoped to the current repository; optional `-CloudJson` merge. |
| `scripts/Export-SessionTranscripts.ps1` | Exports every session a rendered report mentions to `sessions/<session-slug>.html` (events store first, session-store fallback, honest notice page when absent on this machine); `-ListOnly` feeds the validator. Drives `export-copilot-transcript.py`. |
| `scripts/Merge-Glossary.ps1` | All canonical-glossary mechanics: parse, validate, upsert, sort, atomic write, JSON receipt; `-Validate` shared with the test script. |
| `scripts/Invoke-DailyReportBatch.ps1` | Backfill loop: date enumeration, skip/regenerate policy, per-day evidence, isolation. |
| `scripts/Test-DailyReport.ps1` | Read-only validator for report + glossary against the pinned formats. |

Relationship: `batch → (per day: Get-GitProof + Get-SessionEvidence [+
link verification]) → render → Export-SessionTranscripts → Merge-Glossary →
Test-DailyReport`. The agent
does the semantic work (writing, NEW/known judgment); the scripts own every
mechanical invariant. Pester tests for every script live under `tests/`.

## Examples

**Example 1 — window request**

- Input: `generate a report from 8h to 13h today`
- Output: `reports/daily/<git user>/261111.md` with the window scoping the
  grounding query only: Completed Today holds outcomes finished in that range,
  the body carries no times.

**Example 2 — no time given**

- Input: `generate a report for today`
- Window: start of day to current machine time; output is the same per-day file.

**Example 3 — a Completed Today item that passes the contract**

- Input: `report for yesterday afternoon`
- Output (shape of one item):

```markdown
### 1. Verified local and origin develop sync
- **Why:** Untested sync leaves conflicting history for the next session.
- **Result:** Fetched and rebased — develop matches origin/develop, 0 ahead, 0 conflicts.
- **Refs:** session `16f5c5b5` · sync check → PASS (0 ahead).
```

## Guardrails

Mechanical guardrails are enforced by `Test-DailyReport.ps1` and
`Merge-Glossary.ps1` (with unit tests): day scope, repo scope, attribution,
path and naming, frontmatter schema, timeless body, structure and budget, rerun
idempotency, empty-source honesty, batch isolation, session-transcript export
presence for every session the report mentions, and the glossary schema,
ownership, idempotency, and report-to-canonical consistency. A violation fails
loudly with a specific message; it is never silently skipped.

Prose guardrails that remain the agent's discipline:

- **Trace every claim** — a Completed item without a proof row, pull request, or
  completion statement cannot be verified; drop it or state the gap. One invented
  line makes the reader distrust the whole report.
- **Attribute to the runner only** — Step 0 identity is the boundary; work by
  anyone else is never the runner's Done item.
- **Redact secrets** — reports travel; tokens, cookies, and connection strings in
  them become permanent leaks.
- **Reference only real objects** — a bare `#N` auto-links on GitHub, so `#N`
  must be a real issue or pull request, and inline code uses backticks.
- **Follow the template** — section order, Why-first item shape, and honest
  states keep reports comparable from day to day.
