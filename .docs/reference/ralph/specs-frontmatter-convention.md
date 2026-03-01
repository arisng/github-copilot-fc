---
category: reference
source_session: 260227-144634
source_iteration: 2
source_artifacts:
  - iterations/2/reports/task-2-report.md
  - iterations/2/reports/task-3-report.md
  - iterations/2/reports/task-4-report.md
  - iterations/2/review.md
extracted_at: 2026-02-28T22:32:04+07:00
staged: true
staged_at: 2026-02-28T22:36:14+07:00
promoted: true
promoted_at: 2026-02-28T22:41:09+07:00
---

# Specs Frontmatter Convention

> Established in Ralph v2.11.0 (Iteration 2, Session 260227-144634). Applies to all spec files under `agents/ralph-v2/specs/`.

## Directory Structure

Specs live in `specs/` as a **top-level peer** to `docs/`:

```
agents/ralph-v2/
├── docs/
│   ├── design/        # Design rationale, critique
│   ├── reference/     # Reference materials
│   └── templates/     # Templates
├── specs/             # ← Specifications (peer to docs/)
│   ├── live-signals.spec.md
│   ├── normalization.spec.md
│   └── ralph-v2-stop-hook-metadata-finalization.spec.md
```

The `specs/` directory is **not** nested under `docs/`. This separation distinguishes authoritative specifications (normative) from design rationale and reference materials (informative).

## YAML Frontmatter Format

Every spec file requires exactly 5 YAML frontmatter fields:

```yaml
---
title: "Human-Readable Spec Title"
status: implemented | draft | proposed | deprecated
version: "2.11.0"
created_at: 2026-02-15T00:00:00+07:00
updated_at: 2026-02-28T21:21:07+07:00
---
```

### Field Definitions

| Field | Type | Description |
|-------|------|-------------|
| `title` | string | Human-readable title of the specification |
| `status` | enum | Lifecycle status (see below) |
| `version` | string | Version when the spec was created or last substantively updated |
| `created_at` | ISO 8601 | Original creation/drafting date with timezone offset |
| `updated_at` | ISO 8601 | Last modification date with timezone offset |

### Lifecycle Statuses

| Status | Meaning |
|--------|---------|
| `proposed` | Under discussion, not yet accepted |
| `draft` | Accepted but not yet implemented |
| `implemented` | Fully implemented in the codebase |
| `deprecated` | Superseded or no longer applicable |

## Key Principles

1. **Exactly 5 fields** — No additional fields. Status, version, and dates capture all necessary lifecycle metadata.
2. **Freeform status sections removed** — Any existing `## Status` sections with bullet points (e.g., "Drafted: ...", "Implementation: ...", "Scope: ...") are consolidated into frontmatter. The body focuses on content, not metadata.
3. **`created_at` sources from original date** — Use the spec's original drafting/creation date, not the migration date. Example: a spec drafted 2024-06-20 and migrated 2026-02-28 uses `created_at: 2024-06-20`.
4. **`version` reflects origin** — Set to the version when the spec content was established, not the current agent version. Example: normalization spec uses `version: "2.2.0"` because that's when normalization was implemented.

## Naming Convention

Spec files use the pattern: `<topic>.spec.md`

Examples:
- `live-signals.spec.md`
- `normalization.spec.md`
- `ralph-v2-stop-hook-metadata-finalization.spec.md`
