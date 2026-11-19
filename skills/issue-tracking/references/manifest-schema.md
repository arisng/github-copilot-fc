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
| `issuesDir` | `local-markdown`: no | `.issues` | store dir, relative to repo root |
| `archiveDir` | no | `<issuesDir>/archived` | archived issues dir |
| `treeFile` | no | `<issuesDir>/tree.md` | generated tree file |
| `treeScript` | no | bundled `issue-tree.ps1` path when the skill copy lives in-repo | script that validates the store and regenerates the tree |
| `lintTask` | no | — | repo task running the gate (e.g. `lint:issues`) |
| `repo` | `github`: **yes** | — | `owner/name` of the GitHub repository |
| `org` | `azure-devops`: **yes** | — | Azure DevOps organization |
| `project` | `azure-devops`: **yes** | — | Azure DevOps project |
| `gitRemoteHost` | no | inferred from `origin` | evidence captured at bootstrap: `github` \| `azure-devops` \| … |
| `gitRemoteUrl` | no | inferred from `origin` | sanitized remote URL — userinfo (`user@`, tokens) is **stripped, never stored** |

## Validation rules (`issue-tracker-init.ps1 -Apply`)

- `tracker` must be one of the three enum values.
- Per-tracker required fields must be present (`repo` for `github`; `org` + `project`
  for `azure-devops`); `repo` must look like `owner/name`.
- Store fields (`issuesDir`/`archiveDir`/`treeFile`) apply to `local-markdown` only;
  paths must be repo-relative — no rooted paths, no `..`.
- The writer only emits the keys above — unknown keys cannot be introduced without
  extending this schema first (re-running `-Apply -Force` rewrites the manifest in
  canonical form).
- The script refuses to overwrite an existing manifest unless `-Force`.

## Tracker routes

| `tracker` | Store | Route |
|---|---|---|
| `local-markdown` | files under `issuesDir` | this skill's workflow |
| `github` | GitHub Issues in `repo` | label-based triage — user-level `triage-backlog` skill |
| `azure-devops` | Azure Boards in `org`/`project` | `az boards` work items |

Support for `github` and `azure-devops` routes is incremental: the manifest fields
above are validated today; the workflows they route to live outside this skill.
When in doubt or when the manifest says anything else, stop and ask.

## Bootstrap inference (autopilot mode, precedence order)

1. A detected file store (a repo-root dir holding `NNNN-*.md` issue files) →
   `local-markdown` with that dir — **file evidence always beats remote evidence**
   (a git remote does not imply where issues live).
2. Else GitHub remote (`github.com`) → `github` + `repo` parsed from the URL.
3. Else Azure remote (`dev.azure.com` / `*.visualstudio.com`) → `azure-devops` +
   `org`/`project` parsed from the URL.
4. Else → `local-markdown` with `.issues`, and create the store dir.

`issue-tracker-init.ps1 -Probe` prints this evidence as machine rows; the skill's
step 0 turns it into a question (interactive mode) or an answer (autopilot mode).
