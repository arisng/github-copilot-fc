# Issue templates — enforced file shapes (issue-tracking skill)

Every issue file in the local store must conform to an **issue template**:
the frontmatter it may and must carry, and the body sections it must keep.
Templates follow the **industry convention for GitHub issue templates** — a
markdown file with YAML frontmatter (`name`, `about`, `title`, `labels`,
`assignees`) plus a markdown body — extended with the keys this skill needs
to stamp and enforce issue files. The gate (`issue-tree.ps1`, any mode)
validates every file against its template and fails closed.

## Issue types and containment (theme vs epic)

**Two orthogonal axes, deliberately kept apart** — this mirrors GitHub, where
issue *type* is a first-class single-select field that is **not** a label, and
grouping is expressed with labels:

| axis | carried by | meaning |
|---|---|---|
| **classification** | `type:` frontmatter | *what kind of work this is* — one value from the configured taxonomy |
| **grouping** | the `theme` label + `theme:`/`parent:` links | *which workstream it belongs to* |

### The `type` taxonomy

The default taxonomy is **GitHub's own default issue-type vocabulary**:
`task`, `bug`, `feature`. A consumer repo replaces it wholesale by listing its
own types in the manifest:

```json
{ "issueTypes": ["task", "bug", "feature", "root-cause", "spike"] }
```

Rules: lowercase kebab-case names, no duplicates, at most **25** per repo
(GitHub's per-owner ceiling). Every configured type must resolve to a template —
a shipped default or a registered override — so configuring a type the skill
ships nothing for is a gate error until you register one.

`epic`, `chore` and `theme` ship as **opt-in extension types** (templates under
`assets/issue-templates/extensions/`). They are resolvable only when listed in
`issueTypes`; they are not part of the default vocabulary because GitHub does not
ship them.

### Grouping is a label

A record is a **theme root** when its labels carry the `theme` marker — the bare
`theme` label, or a `theme:<slug>` family value:

```yaml
labels: [theme]            # or labels: [theme:payments]
```

`type: theme` is accepted **permanently as a legacy alias**, so a store filed
under the pre-label taxonomy keeps passing the gate without being rewritten.
New records should mark the root with the label and classify the type normally
(`type: task` + `labels: [theme]` is a valid theme root).

The rest of the tree rules are unchanged:

- **`theme` is the root grouping and the superset.** Every non-root issue must
  resolve to exactly one theme, directly (`theme: NNNN`) or through a `parent:`
  chain. A `theme:` value may only point at a theme root. A theme root must not
  declare `theme:` or `parent:`, and must have at least one active child *and* a
  status that matches its completion.
- **`epic` is an intermediate grouping inside a theme** — an optional mid-level
  bundle of that theme's work. When `epic` is enabled, an epic must itself
  resolve to a theme, and epics may nest under other epics.

Containment order: **theme ⊃ epic ⊃ task/bug/chore**. Model one workstream as a
theme, not an epic; add an epic only when a theme's work needs an intermediate
grouping. Only the theme root is gated — a mis-nested epic (parented by a task or
chore) passes `-Check`, so the order below `theme` is a convention to honour, not
an enforced rule.

### A theme closes with its work

The gate ties a theme's `status` to its completion, in both directions: a theme at
100% must be `done` (or `dropped`), and a theme marked `done` must be at 100%.
Completion is the HTML view's formula — `done / (children − dropped)`, an
all-`dropped` theme being vacuously complete — so the number next to the theme in
`tree.html` and the verdict from `issue-tree.ps1 -Check` can never disagree.
`blocked` and `in-progress` children are remaining work; only `dropped` leaves the
denominator. The rule is **enforced, not derived**: `status` stays the authored
value and an inconsistent state is an error, not silently rewritten. Epics are not
status boundaries, so no equivalent rule applies to them.

**This applies to `local-markdown` only.** Under `tracker: github` +
`treeSource: github` there is no authored theme status to check: the sync
*derives* each `## THEME` header from all of that theme's member rows
(open if any member is live, `done` if any was completed, `dropped` only when
nothing was), and the cap can never hide live work because an open child of a
closed parent is promoted into the section's open region. So the contradiction
this rule forbids cannot be produced, and `issue-tree.ps1 -Check` correctly stays
a structural check that accepts a header disagreeing with the rows the cap
happened to render. Do not "fix" that by porting the rule: a github-mode header
may legitimately disagree with its visible rows. The full cross-tracker picture
is [tracker-matrix.md](tracker-matrix.md).

## Where templates live

| Set | Location | Owned by |
|---|---|---|
| Skill defaults (one per default type) | `assets/issue-templates/<type>.md` in this skill | this skill |
| Extension types (opt-in) | `assets/issue-templates/extensions/<type>.md` | this skill |
| Consumer overrides | `issueTemplatesDir` in the consumer repo (default `.github/ISSUE_TEMPLATE/`, GitHub's conventional location) | the consumer repo |

Resolution per configured issue type: a template registered in the manifest's
`issueTemplateOverrides` wins; otherwise the shipped default for that type is
used (from `assets/issue-templates/`, or `extensions/` for an extension type);
otherwise the gate fails and asks for a registration. Files in
`issueTemplatesDir` that are not registered are ignored (they may be
GitHub-native templates for github.com's own issue UI).

## Template format

```markdown
---
name: Bug report
about: File a defect to fix
title: "[Bug] "
labels: [bug]
assignees: []
type: bug
status: open
priority: P2
requiredFields: severity
optionalFields: component
---

## Summary

Observed vs expected behavior.

## Notes

Triage findings, evidence checks, and decisions (append-only).
```

### Frontmatter keys

| key | required | meaning |
|---|---|---|
| `name` | **yes** | template display name (GitHub convention) |
| `about` | **yes** | one-line purpose; `description` is accepted as an alias (GitHub markdown templates use `about`, issue forms use `description`) |
| `type` | **yes** | the issue `type:` this template stamps — must be one of the **configured** types (`issueTypes`, default `task`/`bug`/`feature`, plus opt-in `epic`/`chore`/`theme`) |
| `title` | no | default title prefix for new issues (GitHub convention) |
| `labels` | no | template metadata carried for GitHub-convention compatibility (comma list or `[a, b]`); shown by `issue-template.ps1 -List`, not written into issues |
| `assignees` | no | same as `labels` — template metadata only |
| `status` | no | default `status:` stamped on new issues (must be a valid status) |
| `priority` | no | default `priority:` stamped on new issues (must be a valid priority) |
| `requiredFields` | no | comma list of **extra** issue frontmatter fields this template requires |
| `optionalFields` | no | comma list of **extra** issue frontmatter fields this template permits |

Any other frontmatter key makes the template invalid (typo protection).
`requiredFields`/`optionalFields` entries must be field names
(`[A-Za-z_][A-Za-z0-9_]*`), must not repeat, and cannot redeclare the core
contract (`id`, `title`, `status`, `priority`, `type`, `created`, `labels`) or
the link fields (`theme`, `parent`, `order`).

### Body = required sections

Every level-2 heading (`## Text`) in the template body is a **required
section**: each issue filed from the template must keep that heading (matched
trimmed, case-insensitive). Headings inside fenced code blocks do not count.
Extra headings in issues are allowed — prose is only checked for what the
template requires. A template must declare at least one section; the skill
defaults declare `## Summary` and `## Notes` (`## Notes` is where the triage
loop appends findings — keep it in consumer templates too).

## What the gate enforces

For each `NNNN-*.md` in the store (`issue-tree.ps1`, any mode, before
anything else):

1. Core contract (template-independent): required fields `id`, `title`,
   `status`, `priority`, `type`, `created`; `id` matches the filename;
   status/priority enums; `type` is a configured taxonomy value (or the
   permanently-accepted legacy `theme`); `order` integer; `created` a
   `YYYY-MM-DD` date.
2. Taxonomy + template set integrity: the effective `issueTypes` list validates
   (kebab-case, unique, ≤ 25), every skill default and every registered override
   exists and validates (a broken registration fails the whole gate), and every
   configured type resolves to a template.
3. Template conformance: no unknown frontmatter field, every template
   `requiredFields` entry present, every required section present. A legacy
   `type: theme` record has no template in a default-taxonomy repo, so it is
   held to the core contract only — unknown fields still fail, body sections do
   not.

Template errors print as `TEMPLATE` lines and exit 1 (`THEME` lines remain the
core/relations errors):

```text
TEMPLATE   .issues/0002-fix-widget.md: unknown frontmatter field 'severity' (template 'bug' does not declare it)
TEMPLATE   .issues/0002-fix-widget.md: missing required section 'Notes' (template 'bug')
```

## Registering consumer overrides (on demand)

The manifest (`.github/issue-tracker.json`, schema:
[manifest-schema.md](manifest-schema.md)) carries the registry:

```json
{
  "issueTypes": ["task", "bug", "feature", "epic"],
  "issueTemplatesDir": ".github/ISSUE_TEMPLATE",
  "issueTemplateOverrides": {
    "bug": "bug-report.md",
    "task": "custom-task.md"
  }
}
```

Register with the manifest writer (from the repo root):

```powershell
pwsh <skill-folder>/scripts/issue-tracker-init.ps1 -Apply -Force `
    -IssueTypes task,bug,feature,epic `
    -IssueTemplateOverride bug=bug-report.md
```

Rules:

- `issueTypes` replaces the shipped taxonomy wholesale. Omit it to keep the
  defaults (`task`, `bug`, `feature`); `-Force` carries a configured list over.
- `issueTemplateOverrides` maps issue type → **plain `.md` filename** inside
  `issueTemplatesDir` (no path separators). The file must exist, and the
  template must declare that same `type` — registration validates both, at
  write time and at every gate run.
- `-Force` rewrites **carry the persisted registry over** and merge new
  `-IssueTemplateOverride type=file` entries into it (an entry replaces the
  file for its type). Removing an entry is a direct edit of the manifest — the
  CLI never silently drops registrations.
- `issueTemplatesDir` / `issueTemplateOverrides` apply to `tracker:
  local-markdown` only (the template contract describes the local file store).
  `issueTypes` describes the vocabulary, not the store, so it applies to
  `local-markdown` and `github`; Azure Boards has no issue-type field and
  rejects it.

Verify the effective set any time:

```powershell
pwsh <skill-folder>/scripts/issue-template.ps1 -Validate
pwsh <skill-folder>/scripts/issue-template.ps1 -List
```

## Filing an issue from a template

```powershell
pwsh <skill-folder>/scripts/issue-template.ps1 -Show <type>
```

prints the resolved template; copy it to `NNNN-slug.md`, fill `id`, `title`,
`created`, the link fields (`theme`/`parent`/`order`), and adjust the stamps
(`status`/`priority` default from the template). Never hand-shape a file —
the gate checks it against the same template.

## Adopting templates in an existing store

The defaults require `## Summary` and `## Notes` in every issue body and
reject undeclared frontmatter fields. To adopt in a store filed before
templates existed, either add the missing headings and drop undeclared
fields, or register consumer overrides whose body/field lists match the
legacy shape (every template still requires at least one section).
