# Issue templates — enforced file shapes (issue-tracking skill)

Every issue file in the local store must conform to an **issue template**:
the frontmatter it may and must carry, and the body sections it must keep.
Templates follow the **industry convention for GitHub issue templates** — a
markdown file with YAML frontmatter (`name`, `about`, `title`, `labels`,
`assignees`) plus a markdown body — extended with the keys this skill needs
to stamp and enforce issue files. The gate (`issue-tree.ps1`, any mode)
validates every file against its template and fails closed.

## Issue types and containment (theme vs epic)

`type` is one of `theme`, `epic`, `task`, `bug`, `chore`. The grouping types are
**not** peers — the tree has one mandatory root layer:

- **`theme` is the root grouping and the superset.** Every non-theme issue
  (epic, task, bug, chore) must resolve to exactly one theme, directly
  (`theme: NNNN`) or through a `parent:` chain. A `theme:` value may only point
  at `type: theme`. A theme must not declare `theme:` or `parent:`, and must
  have at least one active child.
- **`epic` is an intermediate grouping inside a theme** — an optional mid-level
  bundle of that theme's work. Because it is a non-theme type, an epic must
  itself resolve to a theme, and epics may nest under other epics.

Containment order: **theme ⊃ epic ⊃ task/bug/chore**. Model one workstream as a
theme, not an epic; add an epic only when a theme's work needs an intermediate
grouping.

## Where templates live

| Set | Location | Owned by |
|---|---|---|
| Skill defaults (one per issue type) | `assets/issue-templates/<type>.md` in this skill | this skill |
| Consumer overrides | `issueTemplatesDir` in the consumer repo (default `.github/ISSUE_TEMPLATE/`, GitHub's conventional location) | the consumer repo |

Resolution per issue type: a template registered in the manifest's
`issueTemplateOverrides` wins; otherwise the skill default for that type is
used. Files in `issueTemplatesDir` that are not registered are ignored (they
may be GitHub-native templates for github.com's own issue UI).

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
| `type` | **yes** | the issue `type:` this template stamps — one of `theme`, `epic`, `task`, `bug`, `chore` |
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
contract (`id`, `title`, `status`, `priority`, `type`, `created`) or the link
fields (`theme`, `parent`, `order`).

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
   status/priority/type enums; `order` integer; `created` a `YYYY-MM-DD` date.
2. Template set integrity: every skill default and every registered override
   must exist and validate (a broken registration fails the whole gate).
3. Template conformance: no unknown frontmatter field, every template
   `requiredFields` entry present, every required section present.

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
    -IssueTemplateOverride bug=bug-report.md
```

Rules:

- `issueTemplateOverrides` maps issue type → **plain `.md` filename** inside
  `issueTemplatesDir` (no path separators). The file must exist, and the
  template must declare that same `type` — registration validates both, at
  write time and at every gate run.
- `-Force` rewrites **carry the persisted registry over** and merge new
  `-IssueTemplateOverride type=file` entries into it (an entry replaces the
  file for its type). Removing an entry is a direct edit of the manifest — the
  CLI never silently drops registrations.
- Both keys apply to `tracker: local-markdown` only (the template contract
  describes the local file store).

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
