---
name: daily-report
description: "Generate a one-page daily report for one git user, grounded in a single calendar day: git proof plus repo-scoped Copilot session evidence, rendered as `reports/daily/{git user}/yymmdd.md` with `created`/`updated` frontmatter, a personal glossary at `glossary.md`, and one turns-only HTML transcript per grounded session (cited or coverage-listed) under `sessions/{session-slug}.html`. USE THIS SKILL whenever the user asks what was done in a time range or wants their daily report, in English or Vietnamese: 'daily report', 'daily standup', 'daily update', 'what did I work on', 'yesterday's work', 'what did I do today', 'generate a report from 9h to 13h today', 'tạo báo cáo hôm nay'. Also for backfilling a date range (batch mode). NOT for: weekly or monthly stakeholder summaries, pull-request description writing. Two modes: single-repo (default) or multi-repo tower, dictated by the manifest `reports/daily/daily-report.manifest.json`."
user-invocable: true
disable-model-invocation: true
metadata:
  version: 1.2.0
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

The skill runs in one of **two modes**, dictated by a per-machine manifest:
**single-repo** (the default — ground and write in the invoking checkout) or
**multi-repo tower** — a home-repo watches every repo path the manifest lists,
grounds them into one report, and persists the report, glossary, and
transcripts under its own `reports/daily/`. No manifest, no tower.

## Arguments

- **date** — the report's calendar day (`yyyy-MM-dd`), default today (machine
  local time). Grounding covers exactly this one day; anything wider is refused.
- **window** — optional same-day range (e.g. `9h-13h`, `13:00-18:00`). It scopes
  the grounding query only; the report body never names it.
- **batch** — a date range request ("backfill reports for 2026-11-01 to
  2026-11-07") routes to Batch mode below.
- Ambiguous input (which date?) → lock it with `ask_user` first.

## Config

- **`repo_names`** — the repositories this skill may report on in **single**
  mode. A LIST; sessions and commits outside it never enter the report.
  Default: the repository of the current checkout (`owner/name` from
  `git remote get-url origin`). Override per machine with
  `DAILY_REPORT_REPOS` (comma-separated). In **multi** mode the manifest's
  `repos` list is the scope and this list does not apply.
- **Multi-machine rule** — this skill runs on more than one machine. Never assume
  one machine's paths or environment exist on another. The manifest is the one
  file that legitimately stores machine-specific absolute paths; every other
  path still resolves at run time (`git rev-parse --show-toplevel`, `$env:`
  variables, the session store). The repository name is the only other
  identity the machines share.

## Manifest — the mode switch

**Location.** `reports/daily/daily-report.manifest.json` at the root of the
invoking checkout. The checkout that holds a manifest is the **home-repo (the
tower)**. A checkout without a manifest runs single mode — the default and
the backward-compatible answer.

**Per machine.** The manifest holds absolute full paths, so it describes one
machine. Git-ignore it in the tower (`reports/daily/daily-report.manifest.json`)
by default; commit it only when every machine shares identical paths. Paths
exist only where the manifest says they do.

**Shape.** Copy `templates/manifest.example.json` into place:

```json
{
  "schema": 1,
  "mode": "multi",
  "repos": [
    "C:/Workplace/home-repo",
    "C:/Workplace/DProcess/dprocess-dotnet-starter-kit"
  ]
}
```

- `mode` dictates the active mode: `single` or `multi`.
- `repos` is read only in `multi` mode: the full absolute paths of the
  watched checkouts. List the tower's own path to include the tower's work;
  leave it out to watch only the other repos.
- `schema` is `1`. Anything the validator does not accept fails loudly.

**Resolve by script, never by hand.**
`scripts/Get-ReportManifest.ps1 -RepoRoot <toplevel> -Optional` emits
`{present, manifestPath, mode, homeRepoRoot, repos}` and, per repo, its
`name` (`owner/name` from origin), `exists`, and `isHomeRepo`:

- `-Optional` on an absent manifest returns `{present:false, mode:"single"}`
  — the single-mode default.
- A manifest that exists but fails validation (bad JSON, unsupported schema,
  unknown mode, relative path, duplicate path, a path that is not a git
  checkout) aborts loudly.
- A watched path missing on this machine comes back `exists:false`; the run
  continues and the report names it as a grounding gap — never dropped
  silently.

**Mode effects:**

- **single** — unchanged behavior: ground the invoking checkout against
  `repo_names`, write to its `reports/daily/`.
- **multi** — ground every `exists:true` manifest repo once, merge the proof
  and session rows across them, and write the one report, its glossary, and
  its transcripts to the **tower's** `reports/daily/<git user>/`. The tower
  is the report home for all watched repos.

## Procedure

### 1. Parse the day (and window) and derive the timezone

- The day is one calendar date. An optional window must stay inside it.
- **The UTC offset is derived at runtime** from the generating machine
  (`(Get-Date).ToString('zzz')`) and stamped into the frontmatter — never
  hardcode an offset.

### 2. Ground — two mandatory sources, a coverage cross-check, then link verification

**Step 0 — identify the runner.** A report describes one person's work only.

- GitHub login: `gh api user -q .login`.
- Git identity: `git config user.name` and `git config user.email`.
- Mode (resolved by script): run
  `scripts/Get-ReportManifest.ps1 -RepoRoot <toplevel> -Optional`. The
  manifest in the invoking checkout dictates `single` or `multi`; no
  manifest means `single`. In `multi` the invoking checkout is the tower
  and the report home for every watched repo.
- Repository: `git remote get-url origin` → `owner/name`, checked against
  the active scope (the manifest `repos` in multi mode, `repo_names` in
  single mode). Stop and ask when it does not match.
- Derive `{git user}`: sanitize `git config user.name` — replace any character
  outside `[A-Za-z0-9._-]` with `-`. The same token names the user folder and
  the glossary owner.

**Repository set (the grounding scope):** in `multi` mode every manifest
repo with `exists:true`; in `single` mode the current checkout, checked
against `repo_names`. A manifest repo with `exists:false` stays out of the
grounding loop and is named as a grounding gap.

1. **Git proof (mandatory — once per repository in scope).**
   The manifest supplies each checkout's full path in multi mode; in single
   mode ground the current checkout (ask the conductor before using any
   other path — never assume another machine's paths). Run
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
2. **Session evidence (mandatory — once per repository in scope).**
   `scripts/Get-SessionEvidence.ps1 -Date "<yyyy-MM-dd>" -RepoRoot <checkout>`
   once per resolved checkout.
   Emits JSON from the Copilot session store, scoped by `sessions.repository`
   matching that checkout — or by its cwd sitting under the checkout when the
   store recorded no repository key — the script refuses unfiltered queries. For the
   cloud store, export the same day and repo scope through the harness
   session-store query and merge with `-CloudJson <file>`; out-of-scope rows are
   refused. Confirm the export's newest row reaches the target day before
   merging — a stale cloud store merges nothing and is named as a grounding
   gap. Each session carries `windowTurns` — every turn inside the window
   with truncated text. **Scan all of them**: the first and last messages are
   orientation only, and action invocations, verdicts, and file writes often sit
   in middle turns; never substitute conversation memory for the queried turns.
   Zero rows is a real result: the report must state that grounding gap
   instead of reading like a day off.
3. **Session coverage (mandatory — multi and single).** After every
   repository's session evidence is collected, run
   `scripts/Get-SessionCoverage.ps1 -Date "<yyyy-MM-dd>" -RepoRoot <root>
   -EvidenceJson <every per-repo evidence file from this run>` and write its
   receipt to the report's `sessions/<yymmdd>.coverage.json` (pass `-OutJson
   <path>`). The receipt classifies every session the store held that day:
   `inScope` must match what evidence returned (`verified: true`, `missed`
   empty), while `outOfScope` and `unattributed` sessions are grounding gaps
   the report-back must name. The mandated validation run in step 6 passes
   this receipt, and it fails on a missing, unverified, or gapped one.
4. **Link verification (only).** `gh` verifies references the two sources
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
`yymmdd` is the report's date (e.g. `261110.md`). The report always lives in
the **report home's** `reports/daily/`: the invoking checkout — which in
multi mode is the **tower**, because the manifest that switched the mode
lives there. Grounding may span repositories; the folder never moves. The
user folder also holds
that user's single `glossary.md`. A path outside the runner's own folder is
refused — two users on one day produce two folders, never one merged file.

**Session transcript exports (enforced):** right after the report file is
written, run `scripts/Export-SessionTranscripts.ps1 -ReportPath <path>
-CoverageJson <receipt>`. It
reads every session the body mentions (``session `xxxxxxxx` `` — the slug is
that id, lowercased; `grill session` mentions are never exported) plus every
`inScope` session in the coverage receipt — cited or not, each grounded
session leaves one artifact — and writes
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

- `scripts/Test-DailyReport.ps1 -RepoRoot <root> -GitUser <git user> -Date <yyyy-MM-dd>
  -CoverageJson <receipt>` must **PASS** before reporting back. It enforces
  path/naming, the frontmatter
  schema, the timeless body, structure and caps, refs format, the session
  transcript exports (every mentioned session must have its
  `sessions/<slug>.html`), the budget, report-to-canonical glossary
  consistency, and — with the coverage receipt — grounding completeness (a
  receipt that is missing, unverified, or lists missed in-scope sessions
  fails, as does an in-scope session without a transcript export). Failures
  are line-specific.
- Report back: the active mode (`single` or `multi`, plus the tower path in
  multi), the file path, counts (N Completed, M Active), created/updated
  stamps, the glossary receipt, the transcript-export receipt
  (`exported`/`notice`/`kept`), the coverage receipt's
  `inScope`/`outOfScope`/`unattributed`/`complete` counts, and any grounding
  gap.

## Batch mode (backfill)

For a date range request, use `scripts/Invoke-DailyReportBatch.ps1
-StartDate <yyyy-MM-dd> -EndDate <yyyy-MM-dd>`. It is strictly a **loop over the
single-day path** — no separate rendering logic:

1. The script enumerates the days, applies the existence policy, and collects
   per-day evidence (Get-GitProof + Get-SessionEvidence once per repository
   in scope — it resolves the manifest itself with Get-ReportManifest, so
   multi mode collects from every existing watched repo and a missing one is
   left to the report's grounding gap). The report path stays `-RepoRoot`,
   which is the tower in multi mode. Policy: **skip** days
   whose report exists (default — cheap, never clobbers) or **regenerate** with
   `-Regenerate`. Isolation: a failing day is reported and the loop continues;
   the batch writes no report files, so it can never leave a half-written file.
   A session-evidence refusal (a remote the script cannot scope, a store error)
   records a grounding gap on that day's entry instead of failing the day: git
   proof still collects, and the summary's `gapped` count names the days.
   Pass `-EvidenceDir <dir>` in backfills: the per-day coverage step verifies
   against those per-repo evidence files.
2. For each day with evidence, render the single-day report (this procedure,
   which includes session coverage, its session-transcript export), then
   `Merge-Glossary`, then `Test-DailyReport`.
3. Validate the range afterwards with `Invoke-DailyReportBatch.ps1 ... -Validate`.

## Scripts (this skill owns all of them)

| Script | Responsibility |
| --- | --- |
| `scripts/Get-ReportManifest.ps1` | Resolves the per-machine manifest: active mode, tower (home repo), and watched repo full paths with origin name and existence; `-Optional` makes an absent manifest a single-mode answer. |
| `scripts/Get-GitProof.ps1` | Single-day, author-filtered, checkpoint-excluding git evidence as JSON. |
| `scripts/Get-SessionEvidence.ps1` | Single-day Copilot session evidence, scoped to the current repository by repository key or cwd (exact match only, no unfiltered queries); optional `-CloudJson` merge. |
| `scripts/Get-SessionCoverage.ps1` | Per-day cross-check of the store against the watched set: classifies every session (inScope / outOfScope / unattributed) and, with `-EvidenceJson`, diffs in-scope ids against what evidence returned; emits the coverage receipt for export and validation. |
| `scripts/Export-SessionTranscripts.ps1` | Exports every session a rendered report mentions — plus every `inScope` coverage-receipt session with `-CoverageJson` — to `sessions/<session-slug>.html` (events store first, session-store fallback, honest notice page when absent on this machine); `-ListOnly` feeds the validator. Drives `export-copilot-transcript.py`. |
| `scripts/Merge-Glossary.ps1` | All canonical-glossary mechanics: parse, validate, upsert, sort, atomic write, JSON receipt; `-Validate` shared with the test script. |
| `scripts/Invoke-DailyReportBatch.ps1` | Backfill loop: date enumeration, skip/regenerate policy, per-day evidence, isolation. |
| `scripts/Test-DailyReport.ps1` | Read-only validator for report + glossary against the pinned formats; `-EvidenceJson` adds empty-source honesty, `-CoverageJson` adds grounding-completeness enforcement. |

Relationship: `Get-ReportManifest → batch → (per day: Get-GitProof +
Get-SessionEvidence per repository in scope, then Get-SessionCoverage
[+ link verification]) →
render → Export-SessionTranscripts -CoverageJson → Merge-Glossary →
Test-DailyReport -CoverageJson`. The agent
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

**Example 4 — multi-repo tower**

- Input: `generate today's report from my home-repo`
- Manifest: `mode: "multi"` with three watched paths, one of them missing on
  this machine.
- Output: `reports/daily/<git user>/261120.md` in the tower, grounded across
  the two reachable repos with the third named as a grounding gap; the
  glossary and every exported transcript land beside the report in the
  tower.

## Guardrails

Mechanical guardrails are enforced by `Test-DailyReport.ps1`,
`Get-ReportManifest.ps1`, and
`Merge-Glossary.ps1` (with unit tests): day scope, repo scope, mode and
manifest schema, attribution,
path and naming, frontmatter schema, timeless body, structure and budget, rerun
idempotency, empty-source honesty, batch isolation, session-transcript export
presence for every session the report mentions, session-grounding coverage
(receipt verified against evidence, no missed in-scope session, one transcript
per in-scope session), and the glossary schema,
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
