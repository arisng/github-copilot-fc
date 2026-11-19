---
name: issue-tracking
description: >
  Repo-agnostic issue tracking for local markdown stores - bootstraps .github/issue-tracker.json on first use (interactive Q&A or auto-inferred in autopilot; the manifest schema is owned by this skill), then triages incoming issues with evidence checks, prioritizes and links them into a theme tree, refreshes the generated issue tree and its interactive static HTML view (.issues/tree.html), and hands out new issue ids collision-free across parallel sessions. Use when asked to triage, groom, refine, prioritize, or audit issues, decide what to work on next by theme, file or link a new issue, refresh .issues/tree.md, render or view the issue tree HTML, verify issue claims against git history, or set up a repo's issue tracker manifest. Routes GitHub issues to triage-backlog; Azure DevOps via az boards.
metadata:
  version: 1.0.1
  author: arisng
---

# Issue Tracking + Theme Tree

Repeatable run over the repo's issue store. Each run ends with every active issue
evidence-checked, every non-theme issue linked to a theme, and the tree gate green, so
the next run starts clean. Parsing, sorting, id arithmetic and validation belong to
the script; the LLM only does evidence judgment and decisions. The primary
human-facing surface is the rendered `.issues/tree.html` — a deterministic,
self-contained page (search, filters, deep links) that opens over `file://`.

## 0. Resolve the tracker (mandatory first step)

The manifest **`.github/issue-tracker.json`** (repo root) is the tracker contract,
and this skill owns its schema — field reference:
[references/manifest-schema.md](references/manifest-schema.md). Never probe `gh`/`az`
or trust a tracker before it speaks — a repo's git remote and its issue store often
disagree (here: Azure DevOps remote, local file issues), and guessing wrong is how
`gh`-based triage hard-failed before the manifest existed. Parsing the configured
remote URL is allowed (bootstrap inference only); calling `gh`/`az` is not.
Commands below use `<skill-folder>` = the folder holding this SKILL.md.

**Manifest exists** → read it and route by `tracker`:

| `tracker` value | Store | Route |
|---|---|---|
| `local-markdown` | files under `issuesDir` (default `.issues`) | workflow below |
| `github` | GitHub Issues in `repo` | label-based triage — the user-level `triage-backlog` skill |
| `azure-devops` | Azure Boards in `org`/`project` | `az boards` work items |
| anything else | — | stop and ask; extend this skill before running |

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

**Done:** manifest present and a tracker route chosen. For any `tracker` other than
`local-markdown`, the workflow below does not apply until adapted — route per the table.

## 1. Inventory — run the script, read its rows

The script is bundled next to this SKILL.md — `<skill-folder>/scripts/issue-tree.ps1`,
where `<skill-folder>` is the folder holding this SKILL.md (`~/.agents/skills/issue-tracking/`
installed; the manifest's `treeScript` names the same file). Always invoke it by that
path **from the repo root**: the issue store resolves from the current directory, never
relative to the script. The script itself reads the manifest for `issuesDir` /
`treeFile` / `archiveDir` (falling back to `.issues`), refuses a non-local-markdown
tracker, and fails fast when the store directory does not exist.

```powershell
pwsh ~/.agents/skills/issue-tracking/scripts/issue-tree.ps1 -Inventory
```

- One row per issue — `id|type|status|priority|theme|parent|order|file|title` —
  followed by `NEXT_ID|NNNN` (next free id across active + archived, skipping ids
  reserved by outstanding allocator leases — advisory; the allocator is the source
  of truth). Validation runs first: schema or theme errors print as
  `THEME .issues/<file>: <reason>` and exit 1; fix them before doing anything else.
- The dump is the working set for the run — open an issue body only where step 2 needs
  its evidence. Never hand-parse frontmatter or hand-count ids.
- Conventions live in `.issues/README.md` when the repo ships one — status/priority/type
  enums, theme rules, the cited-probe rule for package claims (the script enforces the
  enums either way).

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
  one). Write `NNNN-slug.md` immediately after allocating. Never hand-pick an id —
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
- A new cluster of related work with no home → create a theme file: id from
  `issue-new-id.ps1` (step 2's allocator — never hand-picked), `type: theme`,
  `priority` = its most urgent open child, then link its children
  (`theme:` / `order:` shape in the README).
- Chain order is the sort key: priority → `order` → id — computed by the script, so
  set `order` only when same-priority children need an explicit sequence.

**Done:** every non-theme issue carries a resolvable link (proved in step 4).

## 4. Refresh the tree, the view, and go green

```powershell
pwsh ~/.agents/skills/issue-tracking/scripts/issue-tree.ps1         # regenerate the tree file
pwsh ~/.agents/skills/issue-tracking/scripts/render-issue-tree.ps1  # hydrate the human view .issues/tree.html
pwsh ~/.agents/skills/issue-tracking/scripts/issue-tree.ps1 -Check         # gate (wire into your repo's issue lint)
pwsh ~/.agents/skills/issue-tracking/scripts/render-issue-tree.ps1 -Check  # same gate, HTML half
```

The HTML is rendered from `assets/tree-template.html` + the parsed tree — never
edited by hand; `-Check` fails when either the template or the tree moved without a
re-render. Deterministic: same inputs, byte-identical output.

**Auto-refresh wiring (pre-commit):** when a commit stages store files, regenerate
first — `issue-tree.ps1` then `render-issue-tree.ps1`, both validation-first (an
invalid store is refused *before* anything is written) — then `git add` the two
artifacts and run both `-Check`s. An issue mutation can then never land with a
stale tree or view, while corrupt data still fails the commit.

**Done:** both `-Check`s exit 0. A stale tree or view exits 1 here; a repo wired
with the pattern above regenerates and stages the artifacts itself, and still
refuses an invalid store (store files live under `.issues/` by default).

## 5. Report and land

- Report from the tree file (`.issues/tree.md` here) — it is generated from the store,
  so quote its `SUMMARY`/`NEXT` lines and `## THEME` sections instead of recomputing
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
