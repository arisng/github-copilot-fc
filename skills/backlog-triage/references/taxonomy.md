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

- `triage-signals.ps1` and `triage-queue.ps1` fetch the repo's real label set (a
  second, cheap `gh` call; skip in signals with `-NoLabelCheck`) and record any
  configured label the repo lacks under `taxonomy.missing_labels` — console
  warning and HTML banner. Without this a stale config renders an empty queue
  as if there were nothing to triage.
- Non-fatal: unknown labels on issues, `null`/empty patterns (extractor
  skipped), disabled concepts (checks skipped).
- Aborts the run: missing explicit `-Config` file, `gh` failure on the issue
  list. Unparseable config falls back to defaults with a warning; unknown keys
  are skipped with a warning.
- `priority_levels` and `stale_priority_codes` are non-nullable (empty overlay
  keeps base values); `stale_age_days` must be a positive integer. Regex
  patterns are validated at resolution: invalid or capture-less patterns warn
  and fall back to the default.
- Signals payload is versioned (`schema_version`, currently **2**). The report
  refuses a non-v2 cache with a warning telling you to regenerate.
