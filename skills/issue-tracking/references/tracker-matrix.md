# Rule availability across trackers

Which rules, gates, scripts, and manifest keys this skill provides for each
supported `tracker` value in `.github/issue-tracker.json`. **Every row was
probed against the shipped scripts** — see [Verified by](#verified-by) for the
probe method and what could not be exercised.

Three trackers are supported, and they are **not** symmetric. Read the legend
before the tables: a mark describes the *mode*, not an oversight.

## Legend

| Mark | Meaning |
|---|---|
| **yes** | Provided, and the script in question runs |
| **partial** | Partly provided — the cell names the unenforced half |
| **derive** | Provided, but the value is computed from tracker data instead of authored — no input exists to validate |
| **n/a** | Not applicable: the rule describes local files or theme structure the tracker does not model |
| **route** | Not this skill: hand off to another skill (`triage-backlog` for github, `az boards` for azure-devops) |
| **refused** | The script exits 1 with an explicit refusal message |
| **ignored** | The writer accepts the flag and silently drops it (no diagnostic) |

`local-markdown` is the reference implementation. `github` adds a synced tree
view (`treeSource: github`) but delegates triage. `azure-devops` is
**bootstrap-and-route only**: the manifest writer supports it, no script
implements a Boards store.

**Validation is `-Apply`-only.** Nothing re-validates a manifest afterwards, and
five of the seven scripts run without one at all (see
[Missing-manifest fallback](#missing-manifest-fallback-and-mode-notes)).

## Rules and gates

| Rule / behavior | local-markdown | github (+ `treeSource: github`) | azure-devops |
|---|---|---|---|
| Manifest bootstrap (`issue-tracker-init.ps1 -Apply`) | yes | yes | yes |
| Manifest validation (schema, per-tracker required fields) | yes | yes | yes |
| Evidence probe (`issue-tracker-init.ps1 -Probe`) | yes | yes | yes |
| `issueTypes` taxonomy override (classification vocabulary) | yes | yes | **rejected** — no issue-type field |
| Native issue-type enforcement against `issueTypes` | **n/a** — no remote field | yes — sync warns on an out-of-vocabulary `issueType` | **n/a** |
| Theme root marked by the `theme` label | yes | **derive** — the sync buckets by `theme:` labels | **n/a** |
| Triage / evidence checks (step 2) | yes | **route** — `triage-backlog` | **route** — `az boards` |
| Issue templates (`-Validate`) + consumer override registry | yes | **refused** — describes local files | **refused** |
| Template resolution for filing (`issue-template.ps1 -Show`) | yes | **refused** | **refused** |
| Template conformance gate (`TEMPLATE` errors) | yes | **n/a** — no local store is parsed | **n/a** |
| Frontmatter contract (required core fields, `id` = filename, enums) | yes | **n/a** | **n/a** |
| `created` must be `YYYY-MM-DD` | yes | **n/a** | **n/a** |
| `order` must be an integer | yes | **n/a** | **n/a** |
| Collision-free id allocation (`issue-new-id.ps1`) | yes | **n/a** — GitHub assigns ids | **n/a** |
| Id lease inspection / release (`-List`, `-Release`) | yes | **n/a** | **n/a** |
| Duplicate-id gate (gate + allocator) | yes | **n/a** | **n/a** |
| Theme relation: every non-theme issue resolves to exactly one theme | yes | **derive** — from `theme:` labels / native parents | **n/a** |
| Theme relation: no cycles; `theme:` points at a theme root (the `theme` label; `type: theme` is a legacy alias) | yes | **derive** — sync promotes a cross-theme child with a warning; the `-Check` gates reject a hand-nested one | **n/a** |
| Every theme has ≥1 active child | yes | **n/a** — a section only exists when it has members | **n/a** |
| Theme status matches completion (100% ⇒ `done`/`dropped`; `done` ⇒ 100%) | **yes** | **derive** — sync computes the header from all members | **n/a** |
| Epic/theme containment (`theme ⊃ epic ⊃ task/bug/chore`) | **partial** — the theme root (label-marked) is enforced; the epic-inside-theme ordering is convention only | **n/a** — github rows carry no `type:` | **n/a** |
| Tree generation (`issue-tree.ps1`) | yes | **no-op pointer** — exit 0, never writes; run the sync | **refused** |
| Tree freshness gate (`-Check` byte-compare) | yes | **n/a** — `-Check` is self-consistency only | **refused** |
| Structural tree validation (`-Check`: grammar + count cross-checks) | yes | **yes** — see the reorder caveat below | **refused** |
| Machine inventory (`-Inventory`) | yes, rows + `NEXT_ID` | yes, data rows (no `NEXT_ID`) | **refused** |
| html view render (`render-issue-tree.ps1`) | yes | **yes** — full feature parity, rendered from `treeFile` | **refused** |
| html freshness + template-drift gate (`render -Check`) | yes | **yes** — the only gate that catches a hand-edited snapshot | **refused** |
| Remote sync (`sync-github-tree.ps1`) | **refused** | yes (network; `-FromJson` offline) | **refused** |
| Pre-commit auto-refresh wiring | regenerate → stage → both `-Check`s | both `-Check`s only (offline) | **n/a** |

### Gate-wiring caveats the table cannot show

- **The HTML view is identical in both modes.** `render-issue-tree.ps1` renders
  the same page (same template, same interactivity, same drift gate) whether the
  data came from a local store or a synced github snapshot — the only difference
  is the footer hint (`edit issues, not this file` vs `sync first, then render`).
  So a github-tracker repo gets the full human view; only the *pipeline* differs
  (sync → check → render instead of regenerate → render).
- **`issue-tree.ps1 -Check` in github mode does not read GitHub and does not
  byte-compare.** It proves the committed tree is internally consistent, so a
  plain row **reorder** or a count-preserving text edit still exits 0 — while
  `render -Check` catches it (`tree.html is stale (tree data changed)`). Wire
  **both**; `issue-tree -Check` alone leaves a hand-edited snapshot unguarded.
- **`sync-github-tree.ps1 -Check` never reads the manifest.** Under every tracker
  — including no manifest — it prints `-Check is offline-deferred` (exit 1)
  instead of a tracker refusal, and it wins over `-FromJson`. The refusal appears
  only on a real run. Both exit non-zero, so a gate stays red either way, but do
  not debug a missing refusal message in `-Check`.
- **`-Check` and `-Inventory` are mutually exclusive** in both implementing modes
  (`pass either -Check or -Inventory, not both`, exit 1). A gate invoking both
  checks nothing. Ordering differs by mode: github rejects the pair before the
  tree-missing check; local-markdown validates the store first, so store errors
  can print before the exclusivity message; azure-devops refuses the tracker
  before either.
- **Local regeneration is validation-first.** `issue-tree.ps1` refuses an invalid
  store *before* writing, so "regenerate then check" is not a two-phase gate —
  local mode cannot be red for staleness, only for invalid data. In github mode
  the opposite holds: a stale snapshot stays red until a human syncs.
- **`treeMinPriority` is validated only at sync.** `-Apply` accepts and persists
  any string (`P9` is written verbatim, exit 0); `sync-github-tree.ps1` is what
  rejects it (`treeMinPriority must be one of P0, P1, P2, P3`). A bootstrap can
  therefore commit an unusable manifest that looks green until the first sync.

## Manifest keys by tracker

Enforced by `issue-tracker-init.ps1`. Reference: [manifest-schema.md](manifest-schema.md).

| Key | local-markdown | github | azure-devops |
|---|---|---|---|
| `schemaVersion` | yes | yes | yes |
| `tracker` | required | required | required |
| `treeScript`, `lintTask` | yes | yes | yes |
| `issuesDir`, `archiveDir` | yes | rejected | rejected |
| `issueTypes` | yes | yes | rejected |
| `issueTemplatesDir`, `issueTemplateOverrides` | yes | rejected | rejected |
| `treeSource` | rejected | yes (`github`) | rejected |
| `treeFile` | yes (default) | yes (committed snapshot; default `.issues/tree.md`) | rejected |
| `treeMaxIssues`, `treeLookbackDays`, `treeIncludeClosed`, `treeMinPriority`, `issueQuery` | rejected | yes | rejected |
| `treeFreshnessHours` | rejected | **stored-only** — no script reads it, so it gates nothing | rejected |
| `repo` | **ignored** | required | **ignored** |
| `org`, `project` | **ignored** | **ignored** | required |
| `gitRemoteHost`, `gitRemoteUrl` | evidence | evidence | evidence |

Two notes on this table:

- **`—` is not used: `repo`/`org`/`project` are *ignored*, not rejected.** Unlike
  every store/tree key — which raises `… only applies to tracker <x>` — a
  repository-identity flag passed to the wrong tracker is dropped silently
  (`-Apply -Tracker azure-devops -Repo a/b` exits 0 with no `repo` key). Do not
  expect a diagnostic for a misfiled identity flag.
- **The `gitRemote*` keys are conditional.** `-Apply` writes them for all three
  trackers **only when `git remote get-url origin` succeeds**; a repo with no
  `origin` gets neither key and still bootstraps cleanly. Userinfo in the URL is
  stripped. Nothing validates these keys afterwards.

### `treeSource` and the dead-manifest trap

`github`-with-`treeSource: github` is the only tree-capable combination. A
**`github` manifest without `treeSource` behaves like `azure-devops`** for the
tree scripts — it is refused by `issue-tree.ps1` (all modes),
`render-issue-tree.ps1` (all modes), and `issue-new-id.ps1`, with a second hint
line naming the fix. A missing key is treated as `local-markdown` so old
manifests fail closed.

That combination is reachable by accident: `-Apply -TreeSource local-markdown`
is **accepted**, producing a github manifest whose every tree script refuses.
Use `-NoTree` to intentionally omit the key, never `-TreeSource local-markdown`.

### Missing-manifest fallback and mode notes

A repo with **no** `.github/issue-tracker.json` falls back to
`local-markdown` + `.issues` + `.issues/tree.md` + `.issues/archived`:

| Script | No manifest |
|---|---|
| `issue-tree.ps1`, `render-issue-tree.ps1` | yes — run on the defaults |
| `issue-template.ps1 -Validate` | yes — reports the 5 skill defaults |
| `issue-new-id.ps1` | **refused** — `no .github/issue-tracker.json - bootstrap the manifest first` |
| `sync-github-tree.ps1` | **refused** — `tracker: github` is required |

So tree and render gates go green in a repo that was never bootstrapped; only
the allocator and the sync tell the truth. `archiveDir` participates in id
arithmetic only (archived files are excluded from `-Inventory` rows but still
advance `NEXT_ID`). `-Probe` reports evidence and never validates an existing
manifest, so it is not a health check.

## Why the asymmetry exists

- **Templates and the frontmatter contract describe files.** GitHub Issues and
  Azure Boards have their own field models; imposing a markdown template on them
  would be a category error. That is why the registry is refused rather than
  ignored for non-local trackers.
- **The theme-closure rule is enforced locally and derived remotely.** A local
  theme has an authored `status:` that can contradict its children, so it must be
  gated ([issue-templates.md](issue-templates.md), "A theme closes with its
  work"). A github theme header has no authored status — the sync computes it
  from every member row, including rows the cap hid — so there is no
  contradiction to catch and `-Check` stays structural by design. Do not port the
  rule to github mode: a header saying `open` while the cap rendered only `done`
  rows is legal there.
- **Epic containment is convention, not a gate, even locally.** The gate enforces
  that a theme root (a `theme`-labelled record) is not a child and that every
  non-root issue reaches one; it does **not** compare a child's `type` against
  its parent's. An epic parented by a task or chore passes `-Check` green.
- **Classification and grouping are separate axes by design.** `type` mirrors
  GitHub's native issue type (a single-select field that is not a label); grouping
  is expressed with the `theme` label, which is how GitHub models it. Conflating
  them was the pre-2.0 design and forced every grouping concept to masquerade as
  a classification value.
- **Ids are tracker-owned remotely.** GitHub and Azure assign their own
  identifiers, so the lease-based allocator (and the duplicate-id gate that
  protects it) has nothing to protect. Leases live outside the repo
  (`<temp>/issue-id-leases/<hash-of-origin>`), so they are machine state, not
  committed repo state.
- **Only github has a tree pipeline.** The sync composes a search query, fetches
  via `gh`, and writes a committed snapshot that the offline renderer consumes.
  No equivalent exists for Azure Boards, which is why every tree script refuses
  `azure-devops` explicitly rather than failing obscurely.
- **The github snapshot is deterministic except for one marker.** `FILTER|`
  records the composed query and the resolved `@me→<login>`; that login is the
  single deliberately non-reproducible value, so two machines can differ on line
  one and agree everywhere else.

## Adding a tracker

1. Extend `$validTrackers` in `scripts/issue-tracker-init.ps1` and the
   per-tracker required-field validation beside it.
2. Decide each row of the tables above — a new tracker without a store
   implementation should be `route`/`n/a`/`refused`, never silently accepted.
3. Keep every refusal explicit and named (`tracker '<x>' is not local-markdown`),
   matching the existing scripts: a refusal tells the user which skill to use.
4. Update this file and the `tracker` row in SKILL.md step 0 together — the
   matrix is the single place where cross-tracker availability is stated.

## Verified by

Probed with one scratch repo per tracker (a verbatim copy of the skill beside a
manifest, plus a conforming store for `local-markdown`) running every entry point
in every mode: `issue-tree.ps1` (plain, `-Check`, `-Inventory`, both together),
`render-issue-tree.ps1` (plain, `-Check`, `-Out`), `issue-new-id.ps1` (plain,
`-List`, `-Release`, `-TtlHours`), `issue-template.ps1` (`-Validate`, `-List`,
`-Show`, mode exclusivity), `sync-github-tree.ps1` (plain, `-Check`, `-FromJson`,
`-Repo`), `issue-tracker-init.ps1` (`-Probe`, `-Apply` per tracker, and
deliberately misfiled flags), and `bump-tree-template-version.ps1` — capturing
exit codes, messages, and whether files were written.

Every `yes`/`derive`/`refused` mark was confirmed, including: the github no-op
pointer at exit 0 with no write; the compound `treeSource` guard on plain and
`-Check` paths; the azure refusals naming the tracker; and each manifest key's
accept/reject behaviour.

**Not exercised:** a live `gh` sync (no authenticated remote — the sync was
driven through `-FromJson`, which reproduces the fetch contract; `-Repo` was
confirmed to reach the gh call path by its resolution error), Azure Boards
(no `az` CLI, and the tracker is bootstrap-and-route only), and cross-clone lease
visibility (needs two working trees sharing an `origin`; the lease path was
confirmed to be machine-scoped).

Behaviour is pinned by `tests/test_tracker_matrix.py`, which asserts the
dispatch and refusal claims above so a widened guard fails the suite rather than
silently invalidating this table.
