# Rule availability across trackers

Which rules, gates, and behaviors this skill provides for each supported
`tracker` value in `.github/issue-tracker.json`. **Every row was probed against
the shipped scripts, not inferred** — the "Verified by" column names the probe.

Three trackers are supported, and they are **not** symmetric. Availability is
a property of the *mode*, not an oversight, so read the legend before the table.

## Legend

| Mark | Meaning |
|---|---|
| **yes** | Provided, and the script in question runs |
| **derive** | Provided, but the value is computed from tracker data instead of authored — no input exists to validate |
| **n/a** | Not applicable: the rule describes local files or theme structure the tracker does not model |
| **route** | Not this skill: hand off to another skill (`triage-backlog` for github, `az boards` for azure-devops) |
| **refused** | The script exits 1 with an explicit refusal message |

`local-markdown` is the reference implementation. `github` adds a synced tree
view (`treeSource: github`) but delegates triage. `azure-devops` is
**bootstrap-and-route only**: the manifest writer supports it, no script
implements a Boards store.

## Rules and gates

| Rule / behavior | local-markdown | github (+ `treeSource: github`) | azure-devops |
|---|---|---|---|
| Manifest bootstrap (`issue-tracker-init.ps1`) | yes | yes | yes |
| Manifest validation (schema, per-tracker required fields) | yes | yes | yes |
| Triage / evidence checks (step 2) | yes | **route** — `triage-backlog` | **route** — `az boards` |
| Issue templates + consumer override registry | yes | **n/a** — describes local files | **n/a** |
| Template conformance gate (`TEMPLATE` errors) | yes | **n/a** | **n/a** |
| Frontmatter contract (required core fields, `id` = filename, enums) | yes | **n/a** — no store to parse | **n/a** |
| `created` must be `YYYY-MM-DD` | yes | **n/a** | **n/a** |
| `order` must be an integer | yes | **n/a** | **n/a** |
| Collision-free id allocation (`issue-new-id.ps1`) | yes | **n/a** — GitHub assigns ids | **n/a** |
| Duplicate-id gate (allocator leases + pre-commit lint) | yes | **n/a** | **n/a** |
| Theme relation: every non-theme issue resolves to exactly one theme | yes | **derive** — from `theme:` labels / native parents | **n/a** |
| Theme relation: no cycles, `theme:` points at `type: theme` | yes | **derive** — cross-theme rows rejected at sync | **n/a** |
| Every theme has ≥1 active child | yes | **n/a** — a section only exists when it has members | **n/a** |
| Theme status matches completion (100% ⇒ `done`/`dropped`; `done` ⇒ 100%) | **yes** | **derive** — sync computes the header from all members | **n/a** |
| Epic/theme containment (`theme ⊃ epic ⊃ task/bug/chore`) | yes | **n/a** — github mode has no `type:` in its row grammar | **n/a** |
| Tree generation (`issue-tree.ps1`) | yes | **no-op pointer** — never writes; run the sync | **refused** |
| Tree freshness gate (`-Check` byte-compare) | yes | **n/a** — `-Check` is structural only | **refused** |
| Structural tree validation (`-Check`: grammar + count cross-checks) | yes | **yes** | **refused** |
| Machine inventory (`-Inventory`) | yes, rows + `NEXT_ID` | yes, data rows (no `NEXT_ID`) | **refused** |
| html view render (`render-issue-tree.ps1`) | yes | yes | **refused** |
| html freshness + template-drift gate (`render -Check`) | yes | yes | **refused** |
| Remote sync (`sync-github-tree.ps1`) | **refused** | yes (network) | **refused** |
| Pre-commit auto-refresh wiring | regenerate → stage → both `-Check`s | both `-Check`s only (offline) | **n/a** |

One ordering detail the table cannot show: `sync-github-tree.ps1 -Check` is a
purely static pointer that never reads the manifest, so under any tracker it
reports `-Check is offline-deferred` (exit 1) instead of the tracker refusal. The
refusal appears on a **real** sync run. Both exit non-zero, so a gate stays red
either way — but do not debug a missing refusal message in `-Check`.

## Manifest keys by tracker

Enforced by `issue-tracker-init.ps1` (a key outside its tracker is a validation
error, not a silent no-op). Reference: [manifest-schema.md](manifest-schema.md).

| Key | local-markdown | github | azure-devops |
|---|---|---|---|
| `tracker` | required | required | required |
| `issuesDir`, `archiveDir` | yes | rejected | rejected |
| `issueTemplatesDir`, `issueTemplateOverrides` | yes | rejected | rejected |
| `treeSource` | omitted | yes (`github`) | rejected |
| `treeFile` | yes (default) | yes (committed snapshot) | rejected |
| `treeMaxIssues`, `treeLookbackDays`, `treeIncludeClosed`, `treeMinPriority`, `treeFreshnessHours`, `issueQuery` | rejected | yes | rejected |
| `repo` | — | required | — |
| `org`, `project` | — | — | required |
| `gitRemoteHost`, `gitRemoteUrl` | evidence | evidence | evidence |

## Why the asymmetry exists

- **Templates and the frontmatter contract describe files.** GitHub Issues and
  Azure Boards have their own field models; imposing a markdown template on them
  would be a category error. That is why the registry is refused rather than
  ignored for non-local trackers.
- **The theme-closure rule is enforced locally and derived remotely.** A local
  theme has an authored `status:` that can contradict its children, so it must
  be gated ([issue-templates.md](issue-templates.md), "A theme closes with its
  work"). A github theme header has no authored status — the sync computes it
  from every member row, including rows the cap hid — so there is no
  contradiction to catch and `-Check` stays structural by design. Do not port
  the rule to github mode: a header saying `open` while the cap rendered only
  `done` rows is legal there.
- **Ids are tracker-owned remotely.** GitHub and Azure assign their own
  identifiers, so the lease-based allocator (and the duplicate-id gate that
  protects it) has nothing to protect.
- **Only github has a tree pipeline.** The sync composes a search query, fetches
  via `gh`, and writes a committed snapshot that the offline renderer consumes.
  No equivalent exists for Azure Boards, which is why every tree script refuses
  `azure-devops` explicitly rather than failing obscurely.

## Adding a tracker

1. Extend `$validTrackers` in `scripts/issue-tracker-init.ps1` and the
   per-tracker required-field validation beside it.
2. Decide each row of the two tables above — a new tracker without a store
   implementation should be `route`/`n/a`/`refused`, never silently accepted.
3. Keep every refusal explicit and named (`tracker '<x>' is not local-markdown`),
   matching the existing scripts: a refusal tells the user which skill to use.
4. Update this file and the `tracker` row in SKILL.md step 0 together — the
   matrix is the single place where cross-tracker availability is stated.

## Verified by

Probed against the shipped scripts with a manifest per tracker
(`local-markdown`, `github` + `treeSource: github`, `azure-devops`), running
`issue-tree.ps1`, `render-issue-tree.ps1`, `issue-new-id.ps1`,
`issue-template.ps1 -Validate`, and `sync-github-tree.ps1 -Check` in each, and
reading exit codes plus the first output line:

- local-markdown: `issue-tree: OK (… wrote .issues/tree.md)`, `-Check` fresh,
  `-Inventory` rows, `render` writes html, `issue-new-id` prints `ID|NNNN`,
  `issue-template -Validate` reports 5 templates, `sync` refuses.
- github: plain `issue-tree` prints the pointer at exit 0, `-Check` reports
  structurally consistent, `-Inventory` prints data rows, `render` and
  `render -Check` pass, `issue-new-id` / `issue-template` refusal paths as
  tabled.
- azure-devops: `issue-tree`, `render`, `issue-new-id` and `issue-template` all
  exit 1 with the tracker named in the message; `sync` refuses on a real run.

Behaviour is pinned by `tests/test_tracker_matrix.py` (this file's executable
claims: dispatch, refusals, the github no-op pointer, and the azure manifest
shape), alongside `tests/test_theme_completion.py` (local enforcement),
`tests/test_issue_templates.py` (template refusals) and
`tests/test_sync_github_tree.py` (github derivation). Widening a guard clause
without updating this matrix fails those tests.
