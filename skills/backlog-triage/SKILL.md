---
name: backlog-triage
description: >
  Triage a GitHub issue backlog — classify, prioritize, dedup, and groom issues.
  Repo-agnostic: works in any GitHub repo that uses labels, and each repo supplies
  its own label taxonomy via a triage.json config (a FinOps P0–P3 taxonomy ships as
  the built-in default). Use when: triaging new issues, clearing the needs-triage
  queue, grooming the backlog, prioritizing or reprioritizing issues, hunting
  duplicate issues, splitting oversized issues, deciding what to work on next, or
  re-anchoring roadmap items to issues. Triggers: triage, needs-triage, issue queue,
  backlog grooming, prioritize, reprioritize, dedup issues, label issues, what should
  I work on next.
metadata:
  version: 0.3.0
---

# Issue Triage

A repo-agnostic skill for triaging a GitHub issue backlog. It reads every issue in
**one** `gh` call, derives all signals locally, and leaves mutation to explicit `gh`
commands you run after deciding.

The skill reasons about **abstract concepts** — an untriaged marker, a blocked marker,
an owner-decision marker, an ordered priority axis, and area/type tag families. Each
repo maps those onto **its own label names**. Nothing about the FinOps taxonomy is
hard-coded into the logic.

## Taxonomy (per-repo label model)

Every concept the skill uses resolves to a concrete label for the target repo:

| Concept | Default (FinOps) | Role |
|---|---|---|
| `needs_triage` | `needs-triage` | Marks an untriaged issue; the queue is exactly these |
| `blocked` | `blocked` | Waiting on a dependency |
| `owner_decision` | `owner-decision` | Needs owner confirmation before work proceeds |
| `priority_levels` | `priority:P0`…`priority:P3` | Ordered axis, highest first; each has a portable `code` |
| `area_prefix` | `area:` | Multi-valued tag family (e.g. `area:ingest`) |
| `type_prefix` | `type:` | Single-valued tag family (e.g. `type:bug`) |
| `form_priority_heading` / `form_area_heading` | `Priority` / `Area` | Issue-form headings parsed for the proposed values |
| `roadmap_pattern` / `goal_pattern` | `R#` / `G1–G5` | Optional reference regexes; set to `null` to disable |
| `due_pattern` | `**Due:** YYYY-MM-DD` | Optional overdue marker regex |
| `stale_priority_codes` / `stale_age_days` | `["P1"]` / `30` | Which tiers count as "top priority" for the stale check, and the age threshold |

### Config file

A repo overrides any of the above with a JSON config. Discovery order:

1. `-Config <path>` passed to a script (authoritative; a missing file is an error).
2. Repo-local config in the current checkout root — `triage.json`, `.triage.json`,
   or `.github/triage.json`. At user level this makes the **target repo's** config
   win over anything shipped with the skill.
3. `triage.json` **co-located with the skill** — portable: copy the skill folder and
   a hand-maintained config travels with it.
4. Built-in defaults (the FinOps taxonomy) — the skill works with zero config.

```json
{
  "repo": "owner/name",
  "needs_triage": "needs-triage",
  "blocked": "blocked",
  "owner_decision": "owner-decision",
  "priority_prefix": "priority:",
  "priority_levels": [
    { "code": "P0", "label": "priority:P0", "meaning": "Emergency" },
    { "code": "P1", "label": "priority:P1", "meaning": "This cycle" },
    { "code": "P2", "label": "priority:P2", "meaning": "Scheduled" },
    { "code": "P3", "label": "priority:P3", "meaning": "Backlog" }
  ],
  "area_prefix": "area:",
  "type_prefix": "type:",
  "form_priority_heading": "Priority",
  "form_area_heading": "Area",
  "roadmap_pattern": "\\b(R\\d+[a-z]?)\\b",
  "goal_pattern": "\\b(G[1-5])\\b",
  "due_pattern": "\\*\\*Due:\\*\\*\\s*(\\d{4}-\\d{2}-\\d{2})",
  "stale_priority_codes": ["P1"],
  "stale_age_days": 30
}
```

Only specify what differs from the defaults. To **disable** a concept a repo does not
use, set it to `null` or `""` (e.g. `"owner_decision": null`). Absent keys keep the
default.

### Validation & graceful degradation

Both `triage-signals.ps1` and `triage-queue.ps1` fetch the repo's real label set (a
second, cheap `gh` call; skip in signals with `-NoLabelCheck`) and record any
configured label the repo lacks under `taxonomy.missing_labels` — surfaced as a
console warning **and** a banner in the HTML report. The queue warns too: without
this, a stale config (e.g. the defaults against a repo using `status/triage`)
renders an empty queue as if there were nothing to triage.

What is actually non-fatal: unknown labels on issues, `null`/empty patterns (the
extractor is skipped), and a disabled concept (its checks are skipped). What still
aborts the run: a missing explicit `-Config` file, an unparseable config (falls back
to defaults with a warning — the run continues), and a `gh` failure on the issue
list. Unknown config keys are skipped with a warning; `priority_levels` and
`stale_priority_codes` are non-nullable (an empty overlay keeps the base values);
`stale_age_days` must be a positive integer (anything else keeps the base value).
Config regex patterns are validated at resolution: an invalid pattern (or one without
a capture group) warns and falls back to the default.

### Schema

The signals payload is versioned (`schema_version`, currently **2**). v2 renamed the
v1 keys to taxonomy-neutral names: `summary.p0/p1/p2/p3` → `summary.priority_counts`
(keyed by priority code), `grooming.p3_accumulation` →
`grooming.low_priority_accumulation`, `grooming.stale_p1` → `grooming.stale_priority`,
and added the `taxonomy` block. The report refuses a non-v2 cache with a warning
telling you to regenerate.

## Queue

```powershell
pwsh .github/skills/triage/scripts/triage-queue.ps1                        # the queue
pwsh .github/skills/triage/scripts/triage-queue.ps1 -All                   # grooming view, grouped by priority
pwsh .github/skills/triage/scripts/triage-queue.ps1 -Repo owner/name -Config path/to/triage.json
```

`-Repo` (when passed) is authoritative; otherwise the config's `repo`, then the
origin remote of the current checkout (no silent default repo — see **Target repo
resolution** above). The queue is every open issue carrying the `needs_triage` label.

## Signals → decisions → apply

Do **not** make per-issue `gh` calls to gather context. One script call produces every
signal you need; you do the semantic work on that payload; `gh` is used only to mutate.

```powershell
# 1. Signals (deterministic; issues + labels, ~2s)
pwsh .github/skills/triage/scripts/triage-signals.ps1 -Json -OutFile cache/triage-signals.json

# 2. Human-readable view of the same payload (static HTML, no JS, no server)
pwsh .github/skills/triage/scripts/triage-report.ps1
```

The JSON is **self-describing**: a `taxonomy` block echoes the resolved label model (so
the report renders from it), and `summary.priority_counts` is keyed by the portable
priority code. For every queued issue it carries labels, age, form-proposed
priority/area, roadmap/goal references, issue references, **open vs closed dependency
state**, dedup candidates, and a body excerpt — plus a `grooming` block with
`stale_dependency_refs`, `missing_blocked_label`, `blocked_chains`, `overdue`,
`low_priority_accumulation`, and `stale_priority`.

Read the JSON once and decide for the whole queue. Then apply with `gh` (step 8 below).

**Report for the human:** the script prints the path and a `file://` URL. Open it if you
want the clickable, action-grouped view; do not spawn a browser automatically — this
class of tool often runs headless on VPS/Docker, where there is no browser to open.

## Autonomy contract

**Apply-and-report with hard gates.** Apply the full label set and post a rationale
comment on the issue — the comment is the review surface, no confirmation ping.

**Hard gates — stop and confirm before:**

- Closing an issue (duplicate / wontfix / invalid)
- Splitting an issue into children
- Rewriting an issue body
- Changing a roadmap R-item's status

**Escalation valve — ask one focused question when:**

- The priority heuristic ties and the top-two priority choice changes this cycle's work
- You would override the priority proposed in the issue form (flag the override prominently in the report)

## The triage pass (per issue)

Work from the signals payload, not from fresh `gh` calls.

1. **Read** — the queue entry in `cache/triage-signals.json` (title, labels, body excerpt, refs).
2. **Dedup** — use the payload's `dedup_candidates`; confirm with
   `gh issue list --repo <owner/name> --search "<keywords>" --state all` only when a
   candidate looks real. Match found → hard gate: propose closing as duplicate.
3. **Type** — verify the template's `type:*` matches the content (bug vs task vs feature-plan vs map).
4. **Priority** — apply the heuristics below against the repo's priority axis.
5. **Area** — from the form answer plus code knowledge; one or more.
6. **Dependencies** — the payload already resolved open vs closed. Open dependency and no
   `blocked` label → add `blocked`.
7. **Owner-decision** — the issue needs owner confirmation before work proceeds → add `owner_decision`.
8. **Apply + report:**

   ```powershell
   gh issue edit <N> --repo <owner/name> `
     --add-label priority:P1 --add-label area:ingest --remove-label needs-triage
   gh issue comment <N> --repo <owner/name> `
     --body "**Triage:** type:task, priority:P1 (blocks G2), area:ingest. <one-line rationale>"
   ```

## Priority heuristics

The default taxonomy is a four-tier P0–P3 axis. Map the intent onto whatever axis the
target repo uses (the `code` values are what the heuristics reason about):

| Tier | Assign when |
|---|---|
| top (`P0`) | Data loss, corruption, security — drop everything |
| high (`P1`) | Blocks a north-star goal or a roadmap item |
| mid (`P2`) | Important, but not blocking |
| low (`P3`) | Nice to have |

Tie-break: *"if this waits one more cycle, what breaks?"* A goal or integrity issue →
high; convenience → low.

The top tier is reserved for true emergencies; nothing in the normal backlog qualifies.

## Grooming (`-All`, or the `grooming` block in the signals JSON)

Review for:

- **Stale top-priority** (`stale_priority`) — a top-tier item (per `stale_priority_codes`) older than `stale_age_days` is misprioritized or blocked; say which in the report. (The check is label + age only; it does not filter on open dependencies.)
- **Blocked chains** (`blocked_chains`) — which single issue unblocks the most work
- **Low-priority accumulation** (`low_priority_accumulation`) — bottom-tier items; candidates for `wontfix`
- **Priority drift** — labels that no longer match reality (reprioritize with a comment)
- **Stale dependency references** (`stale_dependency_refs`) — body cites a closed issue; the `blocked` label is correctly absent but the body text is stale (fixing the body is a hard gate)
- **Missing `blocked` label** (`missing_blocked_label`) — body cites an open dependency but the label is absent

## Scripts

All accept `-Repo <owner/name>` and `-Config <path>`; both fall back through the
discovery order above (repo-local config, then co-located `triage.json`, then
defaults). Full parameter sets: `triage-queue.ps1` also
takes `-All`; `triage-signals.ps1` also takes `-Json`/`-OutFile`/`-Now`/`-NoLabelCheck`;
`triage-report.ps1` also takes `-SignalsFile`/`-OutFile` (note: `-Config`/`-Repo` are
only used when the signals file must be generated — otherwise the report renders from
the payload's own `taxonomy` block and warns on a mismatch).

| Script | Purpose |
|---|---|
| `triage-queue.ps1` | Human queue / grooming view in the terminal |
| `triage-signals.ps1` | Issues + labels → all signals as JSON (`-Json`, `-OutFile`); `-NoLabelCheck` skips label validation |
| `triage-report.ps1` | Signals JSON → self-contained static HTML |
| `triage-helpers.ps1` | Pure parsing/derivation + taxonomy functions; dot-sourced by the above and by the tests |

Tests: `task test:ps1` (Pester, `tests/triage-signals.Tests.ps1`). The helpers are covered
without network access; the end-to-end cases are skipped when `SKIP_NETWORK_TESTS=1`.

### Behavior deltas from the generalization (v0.1.0 → v0.2.0)

- `Get-ProposedPriority` matches whole tokens, longest code first: a `P10` body no
  longer reads as `P1` (old substring behavior).
- Queue `Priority` is the highest tier per the axis (was: first `priority:*` label).
- Grooming groups sort in taxonomy order (identical output for P0–P3; custom axes
  sort by priority, not alphabetically).
- The default stale watch covers `P1` only — a rotting `P0` never flags. Deliberate:
  P0 is drop-everything by definition, so staleness is meaningless; it either gets
  handled immediately or was never a P0.

### User-level promotion changes (v0.2.0 → v0.3.0)

- Config discovery adds **repo-local** candidates (`triage.json`, `.triage.json`,
  `.github/triage.json` in the checkout root) ahead of the skill-co-located config,
  so each target repo's taxonomy wins at user level.
- The hard-coded `arisng/fin-ops` repo fallback is gone: repo resolution is
  `-Repo` → config `repo` → origin remote of the checkout → error.
- `triage-queue.ps1` now validates the configured labels against the repo's real
  label set (was signals-only); a stale config warns instead of silently showing
  an empty queue. Queue messages quote the configured `needs_triage` label.
- Report footer regenerate hint uses the script's real path (was the fin-ops
  repo-relative path).

## Full-lifecycle operations

- **Dedup-close** (hard gate): comment linking the canonical issue, then

  ```powershell
  gh issue close <N> --repo <owner/name> --reason "duplicate" --duplicate-of <canonical>
  ```

  `--reason duplicate` records GitHub's native duplicate linkage; `--duplicate-of`
  takes the canonical issue number or URL. Use `--reason "not planned"` only when
  there is no canonical issue to point at.
- **Split** (hard gate): create children with `gh issue create`, always passing the
  `needs_triage` label plus the type/priority/area labels — an unlabeled child never
  enters the queue and is permanently invisible to triage. Reference the parent in each
  child body, then narrow or close the parent.

  ```powershell
  gh issue create --repo <owner/name> --title "[task] <child>" --body-file body.md `
    --label needs-triage --label type:task --label priority:P2 --label area:ingest
  ```
- **Roadmap re-anchor**: match roadmap items to issues; status changes are a hard gate.

## Cycle hook

If the repo runs a periodic planning cycle, triage the queue before generating the
plan — plan against a clean backlog. Triage ad hoc any time new issues land.

## References

- Label taxonomy config (this repo's instance): `triage.json` co-located with the
  skill; other repos use their own repo-local config (see **Config file**)
- FinOps-only: label source of truth is `scripts/sync-github-labels.ps1`;
  conventions live in `docs/engineering/issue-tracking.md`
