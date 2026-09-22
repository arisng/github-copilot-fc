---
name: standup
description: >
  Generate daily standup reports from Copilot session history and git data.
  Each execution is scoped to the current git user — only their sessions,
  commits, and entries are included. Standup files accumulate contributions
  from multiple developers (multi-author merge) and live in `.standup/`.
  Auto-detects the date range to cover based on existing files and the
  current date.
  Triggers: "standup", "/standup", "daily standup", "daily update",
  "what did I work on", "yesterday's work", and similar phrases asking for
  a condensed summary of recent development sessions.
metadata:
    version: 0.6.1
machina:
    machine: machine/standup-machine.json
    scenario: default
---

# Standup

> **⚠️ Machina driving rule — enforced.** This skill is governed by a state machine (`machine/standup-machine.json`). Agents MUST load and drive the machine via the `machina-driving` skill. Do NOT follow the prose steps in this file directly — the prose is reference documentation, not the execution path. The machine definition is the single source of truth for the workflow.

## Machina State ↔ Step Mapping

| Machine state | What the driver does (reference) |
|---|---|
| `idle` | Entry point — wait for trigger |
| `detecting-dates` | Run Date Range Auto-Detection algorithm |
| `collecting-data` | Execute `Get-StandupData.ps1` per date |
| `composing-entries` | Compose per-user sections from session data |
| `cross-checking-git` | Verify done status against git commits |
| `checking-dedup` | Check existing file for duplicate entries |
| `writing-fresh` | Write new standup file from template |
| `appending-author` | Append author section to existing file |
| `next-date-or-complete` | Loop or finish |
| `nothing-to-generate` | Final state — no dates need standup files |
| `complete` | Final state — all dates processed successfully |
| `error` | Non-final error state — run aborted due to I/O failure (driver will report STUCK; agent should call `abort`) |

> **Bundled resources:** `scripts/Get-StandupData.ps1` — session data collector.

## Error Handling

The state machine includes error transitions for I/O failures at critical points:
- `DATA_COLLECTION_FAILED` (collecting-data → error)
- `GIT_CHECK_FAILED` (cross-checking-git → error)
- `DEDUP_CHECK_FAILED` (checking-dedup → error)
- `WRITE_FAILED` (writing-fresh → error)
- `APPEND_FAILED` (appending-author → error)

When an error occurs, the machine transitions to the `error` state (non-final). The driving agent will see **zero enabled events** (STUCK) and should call `abort --reason "..."` to terminate the run with `result: ABORTED`.

**Retry behavior:** Re-running the skill after an error is safe. The date auto-detection algorithm scans existing `.standup/` files and skips dates that already have entries for the current author (via the dedup check). This means:
- Dates that completed successfully before the error are preserved on disk.
- Only the failed date (and subsequent dates) will be reprocessed.
- No duplicate entries are created.

## Repo Scoping

The skill auto-detects the repository from the current working directory:

| Scenario | Behavior |
|----------|----------|
| CWD is a git repo | Auto-detect repo from `git remote get-url origin`, filter sessions to that repo, use `git config user.name` for author |
| CWD is a git repo + `-Repository` flag | Use the specified repo instead of auto-detection |
| CWD is NOT a git repo | Skip all git operations (no `git log`, `git branch`, `git config`), query all sessions from Copilot DB with no repo filter, author defaults to `$env:USERNAME` |

When not in a git repo, the script output includes `"isRepo": false`. The cross-check-with-git step should be skipped entirely in this case — session data is the only source of truth.

## Date Range Auto-Detection

Determine which dates need standup files before collecting data. The algorithm has two phases: a **backward catch-up scan** (existing files missing this author) and a **forward range** (new dates not yet on disk).

Get the current git user name from `git config user.name` — this is the author whose entries we need. If not in a git repo, use `$env:USERNAME`.

1. **Backward catch-up scan** — Scan **all** existing `.standup/` files matching `standup-YYYY-MM-DD.md`. For each file before today:
   - Read it and check whether it contains `Author: @<current-user>` (matching the current git user name).
   - If **no** entries found for this author → add that date to the `missing_dates` set.
   - Files that do contain entries for this author are skipped.
   This catches gaps where earlier dates have standup files but the current user never contributed to them.

2. **Compute forward range** — Determine `latest_generated_date`: the most recent date from matching filenames (ignoring future-dated files). Generate standup files for **every date** from `latest_generated_date` (inclusive) through **yesterday** (relative to current date). Never generate a file for today — today's work is not complete.
   - **No existing `.standup/` directory or no files** — Default `latest_generated_date` to 6 calendar days before yesterday (i.e., generate the last 7 completed days). Do not warn or ask; it is the expected first-run case.
   - **Gap in coverage** — Include every date in the range even if some intermediate dates are missing from disk.

3. **Merge target dates** — Take the union of `missing_dates` and the forward range. This is the full set of dates to process. Deduplicate and sort chronologically.

4. **Edge cases:**
   - **Future-dated file** — If a file exists with a date after today, ignore it for `latest_generated_date`. Fall back to the most recent valid file before today.
   - **Nothing to generate** — If both the forward range and `missing_dates` are empty, report "Standup is current — nothing to generate." and stop.

## How to Use

Collect session data once per target date. Loop over each date in the computed range:

```powershell
# Specific calendar date (UTC+7 timezone)
$data = powershell -ExecutionPolicy Bypass -File "skills/standup/scripts/Get-StandupData.ps1" -Date "2026-07-06" | ConvertFrom-Json

# Last 24 hours (relative) — useful for a single-date run
$data = powershell -ExecutionPolicy Bypass -File "skills/standup/scripts/Get-StandupData.ps1" -Days 1 | ConvertFrom-Json

# Override repository (when CWD is not the target repo)
$data = powershell -ExecutionPolicy Bypass -File "skills/standup/scripts/Get-StandupData.ps1" -Days 1 -Repository "owner/repo" | ConvertFrom-Json
```

> **Timezone:** All date filtering defaults to **UTC+7 (Indochina Time)**. The `-Date` parameter treats the given date as midnight UTC+7. Override with `-UtcOffsetHours` (e.g. `-UtcOffsetHours 8` for UTC+8).

The script auto-detects the author from `git config user.name` and the current repo from `git remote get-url origin`. It only returns sessions matching that repo. Override with `-Author "Name"` or `-Repository "owner/repo"`.

**Date filtering is turn-timestamp based** — it finds sessions by when actual work happened (conversation turns), not when the session was created. This correctly catches multi-day sessions, resumed sessions, and overnight work.

## Author Model

Each run is scoped to the current git user — sessions, commits, and entries are filtered to that user alone. Standup files accumulate contributions from multiple authors as different developers run the skill, each adding their own `## @<name>` section.

### File naming

Standup files follow this convention under `.standup/`:

```
.standup/standup-2026-07-07.md
.standup/standup-2026-07-06.md
```

### Per-date merge flow

For each date in the computed range:

1. Collect session data for the date (see How to Use above) — this only returns sessions matching the current repo and author
2. Compose entries for the current author from the filtered session data — if filtering leaves zero usable entries **and** `gitCommits` has no commits for this date → **skip this date** (fire `NO_ENTRIES` from `composing-entries`); never author an empty section
3. Cross-check with the current user's git commits to verify done status (see [Cross-check with Git](#cross-check-with-git-verification-only-current-user-only) below) — **skip this step when `isRepo` is false**; if neither sessions nor commits yield any entry → **skip this date** (fire `NO_ENTRIES` from `cross-checking-git`)
4. Check if `.standup/standup-<yyyy>-<mm>-<dd>.md` already exists
5. If it does not exist → write the file fresh using `assets/templates/standup.md` as the format reference
6. If it does exist → read it, then dedup against the current user's entries (see [Dedup rules](#dedup-rules)):
   - Scan for `Author: @<current-user>` lines matching the current git user name
   - If the author's section already contains **every** composed entry → **skip this date** (fire `ALREADY_RECORDED`) — this user is already recorded
   - If some entries are new → append/merge only the new entries under this author's section (create the `## @<current-user>` section if absent)

#### Dedup rules

Each entry is identified by a composite key: **(feature title, branch, author)**. Two entries are considered equal if all three match.

| Case | Action |
|------|--------|
| Entry exists for this author + feature + branch | **Skip** — already recorded |
| Entry exists with different author but same feature + branch | **Keep both** — different contributors, different perspective |
| Entry exists for this author but different feature/branch | **Add** — new work item |
| Author section exists but entries differ | **Merge** — update content, keep the existing |

#### File structure (multi-author)

Use the canonical template at `assets/templates/standup.md`. Copy the section for each author, replace placeholders (curly-brace tokens) with real values, and append entries for each author in sequence under the date heading.

**Do NOT include** a `## Git Commits` section or any other raw commit listing in the standup file. Git commits are used for cross-checking done status only — they do not appear in the output.

## Data Interpretation Rules

### Session filtering — turn-timestamp based, scoped to the current user

The script filters by **turn timestamps**, not session creation time. This correctly captures:
- Multi-day sessions (started at 11 PM, finished at 2 AM the next day)
- Resumed sessions (created days ago but actively worked on today)
- Overnight work that crosses the calendar boundary

It also auto-detects the current git user from `git config user.name` and the current repo from `git remote get-url origin`. Only sessions belonging to the matching repo and author are returned. When not in a git repo, all sessions are returned with no repo filter.

Skip sessions that have:
- An empty `summary` AND empty `firstMessage` (noise/boot sessions)
- A `summary` that is only "/chronicle standup" or "/standup" (previous standup runs)

### Never emit empty entries

- Drop any candidate entry that would have **no outcome line** after the noise filter above
- Never write an author section whose `✅ Done` **and** `🚧 In Progress` are both empty — if composing yields nothing usable for a date, **skip that date entirely** (machine events `NO_ENTRIES` / `ALREADY_RECORDED`); a standup file is never created or appended with empty sections
- Never leave template placeholders (`{...}`) or blank bullets in output — `No PR found` / `No issue found` alone do not make an entry; the entry still needs a description line and a `Session:` line with the full UUID

### Classifying work status

**✅ Done** — Session meets any of these:
- Commits found in `gitCommits` referencing the same branch
- Last `userMessage` mentions commit, completion, or finishing the work
- Last `response` references commits or completion

**🚧 In Progress** — Session meets any of these:
- Last `userMessage` indicates ongoing work ("next is to", "fleet deployed", "continue", "start implementation")
- No commits found for this work
- Session has a clear summary but no completion signal

### Grouping
Group sessions by `branch` and by topic. Multiple sessions on the same branch and related topic get merged into one standup entry. Use the `summary` and `firstMessage` to determine the feature name.

### Branch display
- `develop` → no branch note needed in standup
- Other branches → show branch name in parentheses

### Sourcing GitHub issues (three sources, scoped per entry)

Every entry's `Issue:` bullet links issue(s) relevant to **that entry only**. Merge candidates from three sources, deduplicated by issue number (first source wins):

1. **Copilot session database** — `refs` recorded on the session (already scoped to the work in the entry)
2. **Git history** — `gitIssueRefs` from the script output: `#N` parsed from commit subjects/bodies in the date range; match to an entry by branch and author
3. **gh CLI** — `issueDetails` from the script output (script resolves candidates with ≤10 bounded, fail-soft `gh issue view` calls). If sources 1–2 yield nothing for an entry, run at most **one** fallback search per date: `gh issue list --search "<branch or feature keywords>" --limit 10 --json number,title,state,url`

Efficiency rules:
- Never invoke `gh` when `isRepo` is false or `gh` is unavailable — the script already gates this
- At most one agent-side `gh` search per date; reuse its results across all entries
- Never call `gh` for a number already present in `issueCandidates`
- If no source matches an entry → write "No issue found" — never attach an unrelated issue

### Formatting rules
- **Session line uses the full session UUID** — e.g. `Session: 4839574f-070c-47f4-969e-d94a000ff6c1`. The `sessions[].id` value from the script output is the full UUID; never truncate it to 8 characters or any other short prefix
- Link PRs/Issues as `[#123](https://github.com/owner/repo/pull/123)` if found in `refs`
- If no refs found for a session, write "No PR found"
- For sessions only, show the most recent session per feature
- Output is relative to the date range, not the calendar day
- Every entry must include `Author: @<name>` as a bullet line for PIC identification

## Cross-check with Git (Verification Only, Current User Only)

> **Skip this entire section when `isRepo` is false** — there is no git data to cross-check.

After grouping from session data, cross-reference with `gitCommits` to verify done status. Filter git commits to the current user's commits using `git log --author="$(git config user.name)"`. Other authors' commits are **not** used.

1. Verify done status (commits by the current user on this branch = done)
2. Check for additional work by the current user not captured in sessions — only add entries if the commits represent distinct work items with no corresponding session

**Never output raw commit hashes or a `## Git Commits` section.** Git data is evidence, not output.
