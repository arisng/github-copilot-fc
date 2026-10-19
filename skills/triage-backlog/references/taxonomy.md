# Taxonomy (per-repo label model)

The skill reasons about abstract concepts. Each repo maps them onto its own
label names. Nothing repo-specific is hard-coded into the logic.

| Concept | Default | Role |
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
| `stale_priority_codes` / `stale_age_days` | `["P1"]` / `30` | Which tiers count as top priority for the stale check, and the age threshold |

Defaults live in `Get-DefaultTaxonomy` in `../scripts/triage-helpers.ps1`.
No co-located `triage.json` ships with this workspace skill.

## Config file

Discovery order:

1. `-Config <path>` passed to a script (authoritative; a missing file is an error).
2. Repo-local config in the current checkout root — `triage.json`, `.triage.json`,
   or `.github/triage.json`. At user level the target repo's config wins over
   anything shipped with the skill.
3. `triage.json` co-located with the skill — portable: copy the skill folder and
   a hand-maintained config travels with it.
4. Built-in defaults — the skill works with zero config.

Discovery is relative to the **current directory**, so a config kept in the
target repo is found only when the scripts run from that checkout; from the
installed skill folder (or anywhere else) pass `-Config <path>` instead. A gate
failure names the config a run resolved (`Resolved (from '…')`), so it is easy
to see which one won.

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

Specify only what differs from the defaults. To disable a concept a repo does
not use, set it to `null` or `""` (e.g. `"owner_decision": null`). Absent keys
keep the default.

## Validation and schema

- **Taxonomy gate (hard).** `triage-queue.ps1` and `triage-signals.ps1` fetch
  the repo's real label set (`gh label list`) and **throw** when a required
  label is missing — no queue, no signals, no report. The error names every
  missing label and proposes both next steps: create the missing labels via
  `triage-bootstrap.ps1` (the printed command carries the same `-Config` the
  failing run resolved), or map the repo's own labels via `triage.json`.
  A `gh label list` failure also throws: the label set is never guessed, so a
  failed call cannot be misread as "this repo has no labels" — which would both
  misdiagnose auth/network problems and let `triage-bootstrap.ps1` create
  labels blind.
- `-NoLabelCheck` skips the gate for offline/tests only. The payload then
  records `taxonomy.label_check = "skipped"`, and `triage-report.ps1` refuses
  such a cache — a gate-skipped payload can never pass as a verified one.
- Required labels = enabled single-label concepts (`needs_triage`, `blocked`,
  `owner_decision`) + every `priority_levels[]` label. Prefix families
  (`area:`, `type:`) are open-ended and never required; `null`/empty disables
  a concept. Unknown labels on issues are ignored. `triage-bootstrap.ps1`
  creates exactly this set, so a completed bootstrap always satisfies the gate.
- Non-fatal: `null`/empty patterns (extractor skipped), disabled concepts
  (checks skipped).
- Aborts the run: missing explicit `-Config` file, unparseable config (no
  silent fallback to defaults), `gh` failure on the label set or the issue
  list. Unknown config keys are skipped with a warning.
- `priority_levels` and `stale_priority_codes` are non-nullable (empty overlay
  keeps base values); `stale_age_days` must be a positive integer. Regex
  patterns are validated at resolution: invalid or capture-less patterns warn
  and fall back to the default.
- Signals payload is versioned (`schema_version`, currently **3**). The report
  throws on a cache that is not v3, on `taxonomy.label_check != "passed"`, and
  on a payload whose `taxonomy.missing_labels` is non-empty — regenerate via
  `triage-signals.ps1` after fixing the gate.
