# Pipeline — which script owns which stage

The skill is four stages over one manifest. Read this before opening a script:
it names the stage each file owns, so a question about *what runs* is answered
here instead of by scanning 800-line scripts.

```text
                         .github/issue-tracker.json   (the contract: tracker, issueTypes, dirs, limits)
                                     |
        +----------------------------+----------------------------+
        |                            |                            |
  [1] STORE                   [2] SYNC (network)            [3] GATE
  .issues/NNNN-*.md           GitHub Issues -> treeFile     validate + regenerate
  (local-markdown only)       (github + treeSource: github) (both modes)
        |                            |                            |
        +----------------------------+----------------------------+
                                     |
                          .issues/tree.md   (generated; the machine grammar)
                                     |
                              [4] RENDER (.issues/tree.html)
```

## Stage 1 — store (local-markdown)

Files at `issuesDir` (default `.issues/`), one `NNNN-slug.md` per issue with YAML
frontmatter + body sections. This is the only stage with author-editable issue
files; `archiveDir` holds retired ones.

| Script | Role |
|---|---|
| `issue-new-id.ps1` | allocates the next id under a machine-shared lease (parallel-safe across clones) |
| `issue-id-lib.ps1` | the lease store and id arithmetic shared by the allocator and the gate |
| `issue-template.ps1` | `-List` / `-Show <type>` / `-Validate` over the resolved template set |
| `issue-template-lib.ps1` | **the single source of truth** for the enums, the taxonomy (`Get-IssueTypeTaxonomy`), theme-root detection (`Test-IssueThemeMarker`), and template resolution |

## Stage 2 — sync (github only)

Network stage. Refuses unless `tracker: github` **and** `treeSource: github`.
Composes the membership query from `issueQuery` + the limit knobs, fetches via
`gh`, and rewrites `treeFile`.

| Script | Role |
|---|---|
| `sync-github-tree.ps1` | fetch + map + write the tree file (the only network script) |
| `query-composition-lib.ps1` | the query reject list and knob composition — one implementation for the writer and the sync |

`-FromJson <file>` is the offline fixture mode the tests use; `-Check` is
deliberately offline-deferred (it points at stages 3 and 4 instead of pretending
to validate the remote).

## Stage 3 — gate

No network. `-Check` is the repo lint; a plain run regenerates the tree
(local-markdown) or no-ops with a pointer (github — the sync owns that file).

| Script | Role |
|---|---|
| `issue-tree.ps1` | validate the store, then regenerate / check / inventory the tree file |
| `template-version-lib.ps1` | the template fingerprint used by stage 4's drift gate |
| `bump-tree-template-version.ps1` | only run after editing `assets/tree-template.html` |

## Stage 4 — render

Turns `tree.md` into the self-contained `tree.html` (search, filter chips, deep
links, light/dark). Deterministic: same tree + same template → byte-identical
output.

| Script | Role |
|---|---|
| `render-issue-tree.ps1` | parse the tree grammar, hydrate `assets/tree-template.html`, `-Check` drift |

## The shared grammar

All three tree-aware parsers read the same lines. A change to the row format
touches every parser below, so change the grammar in one pass:

```text
SUMMARY|themes=N|issues=N|P0=N|P1=N|P2=N|P3=N|blocked=N
NEXT|id|theme|priority|status|title          (absent when nothing actionable)
## THEME|id|priority|status|title
- id|theme|parent|priority|status|title      (3 spaces per nesting level;
                                              title is last and may contain '|')
```

- `issue-tree.ps1` writes it (local-markdown) and parses it in github mode.
- `render-issue-tree.ps1` parses it for the HTML view.
- `sync-github-tree.ps1` writes it (github).

The `id|type|...` line of `issue-tree.ps1 -Inventory` is a **different**,
pipe-delimited dump for the caller — not this grammar.

## Which reference answers which question

| Question | File |
|---|---|
| which manifest key does what, and its validation | [manifest-schema.md](manifest-schema.md) |
| what shape an issue file must have | [issue-templates.md](issue-templates.md) |
| which rule applies to which tracker | [tracker-matrix.md](tracker-matrix.md) |
| which script owns which stage | this file |
