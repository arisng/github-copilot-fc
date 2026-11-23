# `.github/issue-tracker.json` — manifest schema (owned by the issue-tracking skill)

One manifest per repo, at **`.github/issue-tracker.json`** (repo root). It is the
tracker contract: SKILL.md step 0 reads it to route triage, and
`scripts/issue-tree.ps1` reads `issuesDir` / `treeFile` / `archiveDir` from it.

**Ownership:** this skill owns the schema. Other tooling may *read* the manifest;
only this skill's scripts define or extend its fields. The manifest is created on
first use of this skill in a repo (SKILL.md step 0) — interactive mode asks the user
to fill it, autopilot mode infers it, and `scripts/issue-tracker-init.ps1 -Apply`
writes it after validating against this document. The companion renderer
`scripts/render-issue-tree.ps1` turns the tree file into the human-facing
`<treeFile base>.html` (default `.issues/tree.html`).

## Shape

```json
{
  "schemaVersion": 1,
  "tracker": "local-markdown",
  "issuesDir": ".issues",
  "archiveDir": ".issues/archived",
  "treeFile": ".issues/tree.md",
  "treeScript": "~/.agents/skills/issue-tracking/scripts/issue-tree.ps1",
  "lintTask": "lint:issues",
  "gitRemoteHost": "azure-devops",
  "gitRemoteUrl": "https://dev.azure.com/org/project/_git/repo"
}
```

## Fields

| key | required | default | meaning |
|---|---|---|---|
| `schemaVersion` | no (always written) | `1` | bump on a breaking schema change; readers must ignore unknown keys |
| `tracker` | **yes** | — | `local-markdown` \| `github` \| `azure-devops` — routes the skill workflow |
| `treeSource` | `github`: no (always written unless `-NoTree`) | `github` for `tracker: github`; **omitted** for `local-markdown` | tree data source: `github` (synced snapshot in `treeFile`) \| `local-markdown` (store files) — see Tracker routes |
| `issuesDir` | `local-markdown`: no | `.issues` | store dir, relative to repo root |
| `archiveDir` | no | `<issuesDir>/archived` | archived issues dir |
| `treeFile` | no | `local-markdown`: `<issuesDir>/tree.md`; `github`: none | generated tree file; accepted for `github` too (committed snapshot path — written only when supplied) |
| `treeScript` | no | bundled `issue-tree.ps1` path when the skill copy lives in-repo | script that validates the store and regenerates the tree |
| `lintTask` | no | — | repo task running the gate (e.g. `lint:issues`) |
| `issueTemplatesDir` | no | `.github/ISSUE_TEMPLATE` | `local-markdown` only: consumer dir holding custom issue templates (industry-conventional GitHub template location) |
| `issueTemplateOverrides` | no | — | `local-markdown` only: map of issue type → template filename inside `issueTemplatesDir`; registers consumer templates that override the skill defaults per type ([issue-templates.md](issue-templates.md)) |
| `treeMaxIssues` | `github`: no (always written) | `300` | cap applied after sorting |
| `treeLookbackDays` | `github`: no (always written) | `365` | `createdAt` lookback in days, evaluated against the stored `asOf` — never the wall clock |
| `treeIncludeClosed` | `github`: no (always written) | `true` | closed issues ship in the data; hiding them is a view toggle (JSON boolean) |
| `treeMinPriority` | `github`: no | — | opt-in priority floor (tree grammar values `P0`–`P3`) |
| `treeFreshnessHours` | `github`: no | absent = no freshness enforcement | optional freshness threshold in hours |
| `issueQuery` | `github`: no | absent = knob-built defaults | single-line GitHub search query deciding membership (which issues are candidates) — composed with the fixed knobs sync-side, never delegated to gh |
| `repo` | `github`: **yes** | — | `owner/name` of the GitHub repository |
| `org` | `azure-devops`: **yes** | — | Azure DevOps organization |
| `project` | `azure-devops`: **yes** | — | Azure DevOps project |
| `gitRemoteHost` | no | inferred from `origin` | evidence captured at bootstrap: `github` \| `azure-devops` \| … |
| `gitRemoteUrl` | no | inferred from `origin` | sanitized remote URL — userinfo (`user@`, tokens) is **stripped, never stored** |

## Validation rules (`issue-tracker-init.ps1 -Apply`)

- `tracker` must be one of the three enum values.
- Per-tracker required fields must be present (`repo` for `github`; `org` + `project`
  for `azure-devops`); `repo` must look like `owner/name`.
- Store fields (`issuesDir`/`archiveDir`/`issueTemplatesDir`) apply to
  `local-markdown` only; `treeFile`
  applies to `local-markdown` and `github` (still rejected for `azure-devops`).
  Paths must be repo-relative — no rooted paths, no `..`.
- The GitHub tree fields (`treeSource`, `treeMaxIssues`, `treeLookbackDays`,
  `treeIncludeClosed`, `treeMinPriority`, `treeFreshnessHours`, `issueQuery`, plus
  the `-NoTree` opt-out) apply to `github` only — rejected for `local-markdown`
  and `azure-devops`.
- `treeSource` must be `local-markdown` or `github`; `-NoTree` (omit the key) and an
  explicit `-TreeSource` are mutually exclusive.
- `treeMaxIssues`, `treeLookbackDays` and `treeFreshnessHours` must be positive
  integers when supplied. `treeMaxIssues` (300), `treeLookbackDays` (365) and
  `treeIncludeClosed` (true) are always written for `github` — their schema
  defaults when the flags are absent; `treeMinPriority`, `treeFreshnessHours` and
  `issueQuery` are written only when supplied.
- `issueQuery` is validated by `Test-GithubIssueQuery` from
  `scripts/query-composition-lib.ps1` — the writer dot-sources that library, so
  the reject list has exactly one implementation (no drift): empty or multi-line
  queries, unbalanced double quotes, `is:` values outside `open`/`closed`/`issue`
  (`is:pr` gets the early message), case-variant qualifier names (`IS:`),
  unparseable `created:`/`updated:`/`closed:` dates, `repo:`/`org:` (the
  manifest `repo` field owns the target) and `order:` (a typo for `sort:`) all
  reject with exit 1, each error printed with the `issue-tracker-init:` prefix.
  `sort:` is supported; `@me`/`@team` are not rejected (the sync resolves and
  records them).
- The writer only emits the keys above — unknown keys cannot be introduced without
  extending this schema first (re-running `-Apply -Force` rewrites the manifest in
  canonical form **without stripping the GitHub tree fields**: the writer emits
  every key it validates, so `treeSource` and the limits survive a rewrite;
  `treeFile`, `treeMinPriority`, `treeFreshnessHours` and `issueQuery` come only
  from the current invocation — re-pass them to keep them).
- The script refuses to overwrite an existing manifest unless `-Force`.

## Tracker routes

| `tracker` | Store | Route |
|---|---|---|
| `local-markdown` | files under `issuesDir` | this skill's workflow |
| `github` | GitHub Issues in `repo` | label-based triage — user-level `triage-backlog` skill; local tree view when `treeSource: github` |
| `azure-devops` | Azure Boards in `org`/`project` | `az boards` work items |

Per-rule availability for these routes (which gates, scripts, and manifest keys
apply to each tracker) is tabulated in [tracker-matrix.md](tracker-matrix.md).

Support for the `github` and `azure-devops` routes is incremental: the manifest
fields above are validated today; label triage routes to the user-level
`triage-backlog` skill, while the github tree view is refreshed by this skill's
own `scripts/sync-github-tree.ps1` (network: composes `issueQuery` with the
limit knobs, fetches via `gh`, rewrites `treeFile`; its summary prints the
composed `query:`, `skipped knobs:` and a `warning:` per caveat — read them).
The synced `treeFile` carries a single-line `FILTER|<payload>` record (the
composed query, plus the resolved `@me→<login>` marker when the query used
`@me`/`@team`) ahead of `SUMMARY|`, which the renderer maps to the page's
`filter` dataJson field — grammar-optional, absent → empty. Azure workflows
still live outside this skill.
The local tree view (`issue-tree.ps1`, `render-issue-tree.ps1`) follows an explicit
compound guard — never `treeSource` alone: it runs for `local-markdown`, or for
`github` **with** `treeSource: github`. `azure-devops` and a `github` manifest
without `treeSource` are refused (a missing key behaves as `local-markdown`, so
old manifests fail closed instead of half-running). When in doubt or when the
manifest says anything else, stop and ask.

## Bootstrap inference (autopilot mode, precedence order)

1. A detected file store (a repo-root dir holding `NNNN-*.md` issue files) →
   `local-markdown` with that dir — **file evidence always beats remote evidence**
   (a git remote does not imply where issues live).
2. Else GitHub remote (`github.com`) → `github` + `repo` parsed from the URL +
   `treeSource: github` (the local tree view; the `-Apply` flag `-NoTree` omits
   the key). `treeSource` is written only for `tracker: github` —
   `local-markdown` manifests omit it.
3. Else Azure remote (`dev.azure.com` / `*.visualstudio.com`) → `azure-devops` +
   `org`/`project` parsed from the URL.
4. Else → `local-markdown` with `.issues`, and create the store dir.

`issue-tracker-init.ps1 -Probe` prints this evidence as machine rows; the skill's
step 0 turns it into a question (interactive mode) or an answer (autopilot mode).
