# Data Interpretation Rules

## Session filtering — turn-timestamp based, scoped to the current user

The script filters by **turn timestamps**, not session creation time. This correctly captures:
- Multi-day sessions (started at 11 PM, finished at 2 AM the next day)
- Resumed sessions (created days ago but actively worked on today)
- Overnight work that crosses the calendar boundary

It also auto-detects the current git user from `git config user.name` and the current repo from `git remote get-url origin`. Only sessions belonging to the matching repo and author are returned. When not in a git repo, all sessions are returned with no repo filter.

Skip sessions that have:
- An empty `summary` AND empty `firstMessage` (noise/boot sessions)
- A `summary` that is only "/chronicle standup" or "/standup" (previous standup runs)

## Never emit empty entries

- Drop any candidate entry that would have **no outcome line** after the noise filter above
- Never write an author section whose `✅ Done` **and** `🚧 In Progress` are both empty — if composing yields nothing usable for a date, **skip that date entirely** (machine events `NO_ENTRIES` / `ALREADY_RECORDED`); a standup file is never created or appended with empty sections
- Never leave template placeholders (`{...}`) or blank bullets in output — `No PR found` / `No issue found` alone do not make an entry; the entry still needs a description line and a `Session:` line with the full UUID

## Classifying work status

**✅ Done** — Session meets any of these:
- Commits found in `gitCommits` referencing the same branch
- Last `userMessage` mentions commit, completion, or finishing the work
- Last `response` references commits or completion

**🚧 In Progress** — Session meets any of these:
- Last `userMessage` indicates ongoing work ("next is to", "fleet deployed", "continue", "start implementation")
- No commits found for this work
- Session has a clear summary but no completion signal

## Grouping
Group sessions by `branch` and by topic. Multiple sessions on the same branch and related topic get merged into one standup entry. Use the `summary` and `firstMessage` to determine the feature name.

## Branch display
- `develop` → no branch note needed in standup
- Other branches → show branch name in parentheses

## Sourcing GitHub issues (three sources, scoped per entry)

Every entry's `Issue:` bullet links issue(s) relevant to **that entry only**. Merge candidates from three sources, deduplicated by issue number (first source wins):

1. **Copilot session database** — `refs` recorded on the session (already scoped to the work in the entry)
2. **Git history** — `gitIssueRefs` from the script output: `#N` parsed from commit subjects/bodies in the date range; match to an entry by branch and author
3. **gh CLI** — `issueDetails` from the script output (script resolves candidates with ≤10 bounded, fail-soft `gh issue view` calls). If sources 1–2 yield nothing for an entry, run at most **one** fallback search per date: `gh issue list --search "<branch or feature keywords>" --limit 10 --json number,title,state,url`

Efficiency rules:
- Never invoke `gh` when `isRepo` is false or `gh` is unavailable — the script already gates this
- At most one agent-side `gh` search per date; reuse its results across all entries
- Never call `gh` for a number already present in `issueCandidates`
- If no source matches an entry → write "No issue found" — never attach an unrelated issue

## Formatting rules
- **Session line uses the full session UUID** — e.g. `Session: 4839574f-070c-47f4-969e-d94a000ff6c1`. The `sessions[].id` value from the script output is the full UUID; never truncate it to 8 characters or any other short prefix
- Link PRs/Issues as `[#123](https://github.com/owner/repo/pull/123)` if found in `refs`
- If no refs found for a session, write "No PR found"
- For sessions only, show the most recent session per feature
- Output is relative to the date range, not the calendar day
- Every entry must include `Author: @<name>` as a bullet line for PIC identification
