---
name: issue-tracking
description: >
  Repo-agnostic issue tracking for local markdown stores - bootstraps .github/issue-tracker.json on first use (this skill owns its schema), then triages issues with evidence checks, links them into a theme tree, refreshes .issues/tree.md and its HTML view, and allocates ids collision-free across parallel sessions. Classification follows GitHub's native issue type field (default task/bug/feature, overridable via manifest issueTypes); grouping is a label axis - a theme root carries the `theme` label. Gates every issue file against a per-type template (GitHub-conventional defaults; consumers register overrides) and closes themes whose children are done. Use when asked to triage, groom, prioritize, or audit issues, pick next work by theme, file or link an issue, refresh or render the tree, verify claims against git history, enforce issue templates, or set up a tracker manifest. Routes GitHub issues to triage-backlog (plus the synced tree with treeSource: github); Azure DevOps via az boards.
metadata:
  version: 2.1.0
  author: arisng
---

# Issue Tracking + Theme Tree

Repeatable run over the repo's issue store. Each run ends with every active issue
evidence-checked, every non-theme issue linked to a theme, and the tree gate green, so
the next run starts clean. Parsing, sorting, id arithmetic and validation belong to
the script; the LLM only does evidence judgment and decisions. The primary
human-facing surface is the rendered `.issues/tree.html` — a deterministic,
self-contained page (search, filters, deep links) that opens over `file://`.
With `tracker: github` + `treeSource: github` the same run works over a synced
snapshot: triage routes to `triage-backlog`, and steps 1, 4 and 5 operate on
the committed `treeFile` instead of a local store.

## 0. Resolve the tracker (mandatory first step)

The manifest **`.github/issue-tracker.json`** (repo root) is the tracker contract,
and this skill owns its schema — field reference:
[references/manifest-schema.md](references/manifest-schema.md). The four-stage data
flow (store → sync → gate → render), and which script owns each stage, is
[references/pipeline.md](references/pipeline.md) — read it before opening a script
to find out what runs. Never probe `gh`/`az`
or trust a tracker before it speaks — a repo's git remote and its issue store often
disagree (here: Azure DevOps remote, local file issues), and guessing wrong is how
`gh`-based triage hard-failed before the manifest existed. Parsing the configured
remote URL is allowed (bootstrap inference only); calling `gh`/`az` is not.
Commands below use `<skill-folder>` = the folder holding this SKILL.md.

**Manifest exists** → read it and route by `tracker`:

| `tracker` value | Store | Route |
|---|---|---|
| `local-markdown` | files under `issuesDir` (default `.issues`) | workflow below |
| `github` | GitHub Issues in `repo` | label-based triage — the user-level `triage-backlog` skill; **plus** the local tree view (steps 1, 4, 5 below) when `treeSource: github` |
| `azure-devops` | Azure Boards in `org`/`project` | `az boards` work items |
| anything else | — | stop and ask; extend this skill before running |

The three trackers are **not** symmetric: only `local-markdown` has templates,
ids, and the theme-closure gate; only `github` has a tree pipeline (derived
theme status); `azure-devops` is bootstrap-and-route only. The per-rule
availability table is [references/tracker-matrix.md](references/tracker-matrix.md)
— read it before assuming a script works for the tracker in front of you, and
[references/pipeline.md](references/pipeline.md) for which script owns each stage.

**Manifest missing** → bootstrap it now (first use in any repo):

1. Probe: `pwsh <skill-folder>/scripts/issue-tracker-init.ps1 -Probe` — evidence rows
   `STORE|dir|count` (repo-root dirs holding `NNNN-*.md` files), `REMOTE|host|url`
   (sanitized — userinfo stripped), `PARSE|repo/org/project|value`.
2. **Interactive mode** (the harness offers an input tool): ask the user to fill the
   manifest — tracker plus its per-tracker fields, prefilled from the probe rows,
   defaulting to `local-markdown` + `.issues`.
3. **Autopilot mode** (no user to ask): infer by the precedence in
   [references/manifest-schema.md](references/manifest-schema.md) — a detected file
   store beats remote evidence; no evidence at all → `local-markdown` + `.issues`
   (create the store dir so the gate has something to validate).
4. Write it: `pwsh <skill-folder>/scripts/issue-tracker-init.ps1 -Apply -Tracker <t> ...`
   — the script validates against the schema and refuses to overwrite an existing
   manifest (`-Force` replaces). Report what was created or inferred.
   For `tracker: github` the writer emits `treeSource: github` (the local tree
   view over a synced snapshot) by default — pass `-NoTree` to opt out — and
   accepts `-TreeFile <path>` (committed snapshot path) plus `-IssueQuery '<search>'`
   (membership query, validated by the single reject list in
   `query-composition-lib.ps1`); the limit knobs (`-TreeMaxIssues`,
   `-TreeLookbackDays`, `-TreeIncludeClosed`, `-TreeMinPriority`,
   `-TreeFreshnessHours`) are optional. See
   [references/manifest-schema.md](references/manifest-schema.md).

**Done:** manifest present and a tracker route chosen. For `azure-devops` (and
any tracker other than `local-markdown` / `github`-with-`treeSource: github`),
the workflow below does not apply until adapted — route per the table.

## 0.5 Templates — the file shape is gated, not advisory

Every issue file conforms to an **issue template** for its `type`
([references/issue-templates.md](references/issue-templates.md)). Skill
defaults ship in `assets/issue-templates/<type>.md` — GitHub-conventional
markdown templates (`name`/`about`/`title`/`labels`/`assignees` frontmatter +
body) extended with the `type`/`status`/`priority` stamps, the field lists, and
one required section per body heading. A consumer repo overrides any type by
registering its own template in the manifest:

```json
{
  "issueTypes": ["task", "bug", "feature", "epic"],
  "issueTemplatesDir": ".github/ISSUE_TEMPLATE",
  "issueTemplateOverrides": { "bug": "bug-report.md" }
}
```

### Type vs grouping — two axes, deliberately apart

`type` is **classification only**, aligned with GitHub's native issue type field
(a single-select that is *not* a label). The shipped taxonomy is GitHub's own
default vocabulary — `task`, `bug`, `feature` — and `issueTypes` replaces it
wholesale. `epic`, `chore` and `theme` ship as **opt-in extension types**
(templates under `assets/issue-templates/extensions/`), resolvable only when
listed in `issueTypes`.

**Grouping is a label.** A record is a theme root when its labels carry the
`theme` marker — the bare `theme` label or a `theme:<slug>` value:

```yaml
labels: [theme]        # theme root; classify the type normally (type: task)
```

`type: theme` stays accepted forever as a legacy alias, so a store filed under
the old taxonomy keeps passing without a rewrite. Never add grouping semantics
to a new `type` value — that axis belongs to labels.

Register (validated: the file must exist and declare the same `type`; a
`-Force` rewrite carries the persisted registry over and merges new entries):

```powershell
pwsh <skill-folder>/scripts/issue-tracker-init.ps1 -Apply -Force `
    -IssueTypes task,bug,feature,epic `
    -IssueTemplateOverride bug=bug-report.md
```

| Need | Command |
|---|---|
| see the effective registry | `pwsh <skill-folder>/scripts/issue-template.ps1 -List` |
| validate the set + registration | `pwsh <skill-folder>/scripts/issue-template.ps1 -Validate` |
| print a filing skeleton to copy into a new issue file | `pwsh <skill-folder>/scripts/issue-template.ps1 -Show <type>` |

Unregistered files in `issueTemplatesDir` are ignored — they may be native
GitHub.com templates. Templates describe the local store, so the registry is
`tracker: local-markdown` only; `issueTypes` describes the issue model, so it
applies to `local-markdown` and `github` (Azure Boards has no such field).

**Done:** every configured type resolves to a valid template (the gate in step 1
proves it; `-Validate` reports it standalone).

## 1. Inventory — run the script, read its rows

The script is bundled next to this SKILL.md — `<skill-folder>/scripts/issue-tree.ps1`,
where `<skill-folder>` is the folder holding this SKILL.md (`~/.agents/skills/issue-tracking/`
installed; the manifest's `treeScript` names the same file). Always invoke it by that
path **from the repo root**: the issue store resolves from the current directory, never
relative to the script. The script itself reads the manifest for `issuesDir` /
`treeFile` / `archiveDir` (falling back to `.issues`), enforces the compound guard —
it runs for `local-markdown`, or for `github` **with** `treeSource: github`
(`azure-devops` and a `github` manifest without `treeSource` are refused; a missing
key behaves as `local-markdown`, so old manifests fail closed), and fails fast when a
local store directory does not exist.

**Local-markdown mode** (default path, unchanged):

```powershell
pwsh ~/.agents/skills/issue-tracking/scripts/issue-tree.ps1 -Inventory
```

- One row per issue — `id|type|status|priority|theme|parent|order|file|labels|title`
  — followed by `NEXT_ID|NNNN` (next free id across active + archived **and every
  worktree checkout of the clone**, skipping ids reserved by outstanding allocator
  leases — advisory; the allocator is the source of truth). Add `-Brief` to print
  only `SUMMARY|themes=N|issues=N` + `NEXT_ID|NNNN` when the ids/counts are all the
  run needs. Validation runs first: core/relations errors print as
  `THEME .issues/<file>: <reason>`, template conformance errors as
  `TEMPLATE .issues/<file>: <reason>`, and the run exits 1; fix them before doing
  anything else.
- The dump is the working set for the run — open an issue body only where step 2 needs
  its evidence. Never hand-parse frontmatter or hand-count ids.
- Conventions live in `.issues/README.md` when the repo ships one — status/priority/type
  enums, theme rules, the cited-probe rule for package claims (the script enforces the
  enums either way). File shape is enforced by the templates (step 0.5), not by prose.

**Github mode** (`tracker: github` + `treeSource: github`) — the committed `treeFile`
is the source of truth; there is no local store to validate:

- **Refresh first (network):** `pwsh <skill-folder>/scripts/sync-github-tree.ps1`
  reads the manifest (`repo`, `treeFile`, limits, `issueQuery`), composes the
  membership query, fetches via `gh`, and rewrites `treeFile` — see step 4's
  github-mode block for the full refresh order and what to read in its summary.
  A plain `issue-tree.ps1` run here is a **no-op with a pointer**
  (`github tree source: run sync-github-tree.ps1 to regenerate`, exit 0) — it
  never writes an empty tree.
- **Inventory** — `pwsh <skill-folder>/scripts/issue-tree.ps1 -Inventory` parses the
  committed `treeFile` with the same grammar and prints its data rows (no
  `NEXT_ID` — GitHub assigns issue numbers). `-Check` is structural
  self-consistency of `treeFile` only (parser + count cross-checks, offline).
  After a sync, regenerate the view: `pwsh <skill-folder>/scripts/render-issue-tree.ps1`.

**Done:** `-Inventory` exits 0 and its rows have been read.

## 2. Triage each issue — evidence first

- Verify claims against the repo before trusting the file: "fixed?" → `git log` for the
  cited paths; behavior claims → grep/read the code. An unfixed claim filed as done is
  the failure mode to catch.
- Filing a new issue or theme? **Allocate the id first** —
  `pwsh <skill-folder>/scripts/issue-new-id.ps1` prints `ID|NNNN`. The reservation is
  an atomic lease in a machine-shared store keyed by the repo's normalized remote
  URL, so parallel sessions in the same worktree, in sibling worktrees, *or in a
  different clone of this repo on this machine* can never be handed the same id
  (24 h TTL reclaims crashed sessions; `-List` shows leases, `-Release NNNN` drops
  one). The allocator also **counts ids filed** in every worktree checkout of
  the clone (`git worktree list`), so an id committed on an unmerged branch is
  never re-handed, and one id filed under two different filenames across
  worktrees prints a WARNING — renumber the later file; first-filed keeps the
  id. Write `NNNN-slug.md` immediately after allocating. Never hand-pick an id —
  `NEXT_ID` from `-Inventory` is the advisory view of the same rule. Isolated
  machines cannot see each other's uncommitted issues; there the always-on
  duplicate-id gate (the repo's issue lint, pre-commit) refuses to let a collision
  land — resolution protocol in step 5.
- Adjust `status`/`priority` in place and append findings to `## Notes`; flag any
  third-party package claim that lacks the repo's cited-probe rule (`.issues/README.md`,
  when present) instead of repeating it.
- Apply non-destructive edits directly; propose close/drop/archive and new-id decisions
  to the user first.

**Done:** each active issue has either an evidence-checked state or a Notes entry
recording what could not be checked.

## 3. Theme pass — the point of the run

- Every non-theme issue resolves to exactly one active theme: direct `theme: NNNN`, or
  a `parent:` chain ending at a theme. Step 4's `-Check` proves it — never by eye.

### Types: theme vs epic (which contains which)

Classification (`type`) and grouping (`theme` label) are separate axes, so the
containment question is about **structure**, not about two competing type values:

| | `theme` (a root, marked by label) | `epic` (opt-in extension type) |
|---|---|---|
| carried by | the `theme` label (`theme` or `theme:<slug>`); `type: theme` is a legacy alias | `type: epic` — only valid when `epic` is in `issueTypes` |
| role | **root grouping** — the workstream every issue must belong to | **intermediate grouping** — a sub-bundle of one theme's work |
| relation | must not declare `theme:` or `parent:` | must resolve to a theme (`theme:` or a `parent:` chain) |
| resolvable by `theme:`? | yes — the only thing a `theme:` ref may point at | no — `theme:` pointing at an epic is a validation error |
| may have children | yes (issues, epics, tasks) | yes (tasks, bugs, chores, other epics) |
| containment enforced? | yes — the theme root is required | no — nesting order is convention (see below) |
| must have active children | required (a childless theme is clutter) | not required |
| status vs completion | **enforced** — 100% must be `done`/`dropped`, `done` must be 100% | no rule (an epic is not a status boundary) |
| count | one or more | zero or more (optional depth) |

So **a theme is the superset**: it is the boundary of the tree, and every epic,
task, bug and chore lives under exactly one theme. An epic is a *narrower* container
than a theme — an optional mid-level grouping whose members are a subset of that
theme's work. "Theme ⊃ epic ⊃ task/bug/chore" is the containment order; two epics
may sit side by side in one theme, and an epic may nest under another epic. Never
model a theme as a child of an epic, and never use `epic` when one workstream is
intended — the gate requires the theme root either way.

**Only the theme root is gated.** `issue-tree.ps1` proves that a theme root is not
a child and that every non-root issue reaches a theme; it does **not** compare a
child's `type` against its parent's, so a mis-nested epic (parented by a task or
chore) passes. The containment order below `theme` is a modelling convention you
are expected to honour, not a gate. Cross-tracker availability:
[references/tracker-matrix.md](references/tracker-matrix.md).

- A new cluster of related work with no home → create a theme file: id from
  `issue-new-id.ps1` (step 2's allocator — never hand-picked), `labels: [theme]`,
  `type` = an ordinary classification (e.g. `task`), `priority` = its most urgent
  open child, then link its children (`theme:` / `order:` shape in the README).
  Reach for `epic` only when a theme's work needs an intermediate grouping — and
  only after adding `epic` to `issueTypes`; it does not replace the theme.
- **Close the theme when its work is done — the gate refuses a contradiction.**
  Completion is `done / (children − dropped)`, the same formula the HTML view
  prints, so a theme at 100% must carry `status: done` (or `dropped`), and a theme
  marked `done` must be at 100%. Whichever way it is wrong, `issue-tree.ps1 -Check`
  fails and names the theme file with the count. A partly-done theme stays
  `open`/`in-progress` — a `blocked` or `dropped` child is not done; only
  `dropped` leaves the denominator. `status` is authored, never derived: fixing
  it is a one-line edit, not a regenerated tree. **`local-markdown` only** — in
  github mode the sync *derives* the header from all member rows (so it cannot
  contradict itself) and `-Check` stays structural; do not port the rule.
- Chain order is the sort key: priority → `order` → id — computed by the script, so
  set `order` only when same-priority children need an explicit sequence.

**Done:** every non-theme issue carries a resolvable link (proved in step 4), and
every theme whose children are all `done`/`dropped` is closed (local-markdown;
github mode derives the header instead).

## 4. Refresh the tree, the view, and go green

**Local-markdown mode:**

```powershell
pwsh ~/.agents/skills/issue-tracking/scripts/issue-tree.ps1         # regenerate the tree file
pwsh ~/.agents/skills/issue-tracking/scripts/render-issue-tree.ps1  # hydrate the human view .issues/tree.html
pwsh ~/.agents/skills/issue-tracking/scripts/issue-tree.ps1 -Check         # gate (wire into your repo's issue lint)
pwsh ~/.agents/skills/issue-tracking/scripts/render-issue-tree.ps1 -Check  # same gate, HTML half
```

**Github mode** (`treeSource: github`) — refresh order is **sync → check → render**
(the sync is the only step that touches the network; `issue-tree.ps1` plain run is
a no-op here, so never put it in a gate):

```powershell
pwsh <skill-folder>/scripts/sync-github-tree.ps1           # network: fetch + rewrite treeFile
pwsh <skill-folder>/scripts/issue-tree.ps1 -Check          # structural self-consistency of treeFile (offline)
pwsh <skill-folder>/scripts/render-issue-tree.ps1          # hydrate .issues/tree.html from treeFile
pwsh <skill-folder>/scripts/render-issue-tree.ps1 -Check   # byte-compare HTML <-> treeFile + template fingerprint
```

- `lint:issues` in github mode = `issue-tree.ps1 -Check` + `render-issue-tree.ps1
  -Check` — **never a plain `issue-tree.ps1` run**: it no-ops by design (pointer
  exit 0) and would gate nothing. `-Repo owner/name` overrides the manifest's
  `repo`; `-FromJson <file>` is the offline fixture mode used by the tests.
- **The HTML view is not local-markdown-only.** github mode renders the same
  `.issues/tree.html` (same template, same interactivity, same drift gate) from
  the synced `treeFile` — only the pipeline differs, and the footer hint names
  `sync-github-tree.ps1` first. `render -Check` is also the stronger gate here:
  `issue-tree.ps1 -Check` is self-consistency only, so a hand-edited or reordered
  snapshot passes it and is caught by `render -Check`.
- **Read the sync summary before moving on:** `query:` (the composed membership
  query), `skipped knobs:` (fixed knobs suppressed because `issueQuery` already
  carries that qualifier class — logged, never silently dropped), and
  `fetched= shown= truncated= total=(exact|floor) asOf=`. `truncated=true` means
  the post-filter cap was hit (fetch probed cap+1 rows — more issues exist than
  shown); `total` is an exact GraphQL `ISSUE_ADVANCED` count only when
  `issueQuery` is set, otherwise an honest fetched floor. Every
  `sync-github-tree: warning:` line (sub-issue shortfall, fallback theme bucket,
  unresolved `@me`, count fallback, **issue type outside the configured
  `issueTypes`**, …) must be read and, if it affects the view, reported in step 5.
- **Issue `type` is enforced, not rendered.** The sync fetches GitHub's native
  `issueType` field, which is classification (a single-select, not a label) and
  has no slot in the tree row grammar. An issue whose type falls outside the
  manifest's `issueTypes` vocabulary produces a warning naming the fix — add the
  type to `issueTypes`, or retype the issue on GitHub. Unset types are silent.
- **`@me`/`@team` in `issueQuery`** is resolved once per sync and recorded in the
  artifact's `FILTER|` line as `@me→<login>` (echoed into the page banner via the
  `filter` dataJson field) — the snapshot discloses whose view it is; that is the
  one deliberate cross-machine non-reproducibility.
- **Freshness is advisory by design:** the `asOf` epoch is baked into `SUMMARY`
  and the lookback window anchors to it, so a committed snapshot is a frozen,
  offline-verifiable artifact — `render -Check` byte-compares unchanged in both
  modes. There is **no `-MaxAgeHours` switch and no enforcement of
  `treeFreshnessHours`** (the manifest key is stored for future use only); the
  freshness policy that exists is *run the sync* (step 1's refresh) when the
  snapshot may be old.

The HTML is rendered from `assets/tree-template.html` + the parsed tree — never
edited by hand; `-Check` fails when either the template or the tree moved without a
re-render. Deterministic: same inputs, byte-identical output.

**Template versioning — drift detection and patch.** The template's identity lives in
`assets/tree-template.version.json` (`version` + `sha256` of `assets/tree-template.html`);
the render injects the version into the page (head `tree-template-version` meta + footer),
so every generated `.issues/tree.html` states which template built it.

- **Every edit to `assets/tree-template.html` must bump the version** — run
  `pwsh <skill-folder>/scripts/bump-tree-template-version.ps1 -Version <new>` (it
  re-fingerprints the template and refuses downgrades). Until you do, every render and
  `-Check` fails with `changed without a version bump`, so an un-bumped template cannot
  ship. Current template is **v1.1.0** (snapshot banner, hide-closed toggle,
  github-variant footer) — consumer drift detection covers those changes too: a
  page generated before the upgrade reports `version drift` and the patch is the
  same re-render.
- **Consumer repos detect drift at `-Check`**, before data staleness: the embedded version
  is compared against the installed template's recorded one —
  `version drift: generated with template vX, current template is vY` means a skill
  upgrade moved the template. Patch = re-run `render-issue-tree.ps1`, which re-embeds the
  new version (the pre-commit wiring below does this automatically).

**Auto-refresh wiring (pre-commit):** when a commit stages store files, regenerate
first — `issue-tree.ps1` then `render-issue-tree.ps1`, both validation-first (an
invalid store is refused *before* anything is written) — then `git add` the two
artifacts and run both `-Check`s. An issue mutation can then never land with a
stale tree or view, while corrupt data still fails the commit.

Note the limit for **github mode**: a staged-file hook cannot observe *remote*
issue changes — nothing staged moves when someone files an issue on GitHub. A
`gh`-backed refresh hook is possible but must stay optional and auth/offline
aware (pre-commit itself stays fully offline: it runs the two `-Check`s against
the committed artifacts). The freshness path there is the explicit sync in step 1,
or a scheduled/manual refresh — not a gate. In this repo the gates are
`scripts/workspace/workspace-check.ps1` (via `task lint` / `task check` in
`Taskfile.yml`); wire `lint:issues` to the two `-Check` commands above for either
mode.

**Done:** both `-Check`s exit 0. A stale tree or view exits 1 here; a repo wired
with the pattern above regenerates and stages the artifacts itself, and still
refuses an invalid store (store files live under `.issues/` by default).

## 5. Report and land

- Report from the tree file (`.issues/tree.md` here) — it is generated from the store
  (or, in github mode, the synced snapshot), so quote its `SUMMARY`/`NEXT` lines and
  `## THEME` sections instead of recomputing
  counts or order; `git diff` on it shows what moved since the last run. The
  human-facing view of the same data is `.issues/tree.html` — open it (or hand its
  path to the user) when the conversation benefits from the interactive surface.
- Call out what was created/archived and every decision you need from the user.
- One atomic commit using the repo's commit-scope convention (e.g. `docs(issue)`);
  follow the repo's own staging rules (its AGENTS.md, when present).
- **Cross-machine duplicate surfaced?** (`lint-issues: duplicate id NNNN` at the
  gate — two isolated machines each allocated the same id and only now share a
  tree). Resolve on the side that has **not** pushed yet, before landing:
  1. Keep the id that already exists on the remote/merged side — it is the shared
     truth; never renumber what already landed.
  2. Re-allocate a fresh id locally: `pwsh <skill-folder>/scripts/issue-new-id.ps1`.
  3. Rename the local file to the new prefix, update its frontmatter `id:`, and
     retarget every reference to the old id (`theme:`, `parent:`, cross-issue
     mentions, filename pointers) — the gate names what still dangles.
  4. Re-run step 4's checks (ids, tree, view all green), commit, push.
