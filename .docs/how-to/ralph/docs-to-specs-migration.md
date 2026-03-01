---
category: how-to
source_session: 260227-144634
source_iteration: 2
source_artifacts:
  - iterations/2/reports/task-2-report.md
  - iterations/2/reports/task-3-report.md
  - iterations/2/reports/task-4-report.md
  - iterations/2/reports/task-5-report.md
  - iterations/2/review.md
extracted_at: 2026-02-28T22:32:04+07:00
staged: true
staged_at: 2026-02-28T22:36:14+07:00
promoted: true
promoted_at: 2026-02-28T22:41:09+07:00
---

# How to Migrate Docs to Specs

> Procedure established during Ralph v2.11.0 (Session 260227-144634, Iteration 2) — migrating design docs and references into unified specs with YAML frontmatter.

## When to Use

Use this procedure when:
- Multiple design docs cover the same topic and should be consolidated into a single authoritative spec
- A reference doc is mature enough to be promoted to spec status
- An existing spec lacks the standard YAML frontmatter convention

## Procedure: Merge Multiple Design Docs into a Unified Spec

**Example**: Merging `live-signals-design.md` (400 lines, design rationale) + `live-signals-map.md` (120 lines, implementation tables) → `specs/live-signals.spec.md`.

1. **Create the spec file** at `specs/<topic>.spec.md` with 5-field YAML frontmatter:
   ```yaml
   ---
   title: "Topic Name"
   status: implemented
   version: "2.10.0"
   created_at: <original-creation-date>
   updated_at: <now>
   ---
   ```

2. **Organize content with clear top-level separation**:
   - `## Design` — rationale, problem statement, proposed solution (from design doc)
   - `## Implementation Map` — checkpoint tables, gap analysis (from implementation doc)
   - Use horizontal rule (`---`) between major sections

3. **Convert cross-references** from inter-document links to internal anchors:
   - Before: `live-signals-design.md §4`
   - After: `[§4 Agent Integration](#4-agent-integration--hybrid-polling-model)`

4. **Deduplicate boilerplate** — remove introductory cross-reference notes and redundant explanations that appeared in both source docs.

5. **Delete original files** after verifying the spec.

6. **Update external cross-references** — find all files that linked to the deleted docs and update paths:
   ```powershell
   Select-String -Path "agents/ralph-v2/**/*.md" -Pattern "live-signals-design|live-signals-map" -Recurse
   ```

## Procedure: Transform a Reference Doc into a Spec

**Example**: Converting `docs/reference/normalization.md` → `specs/normalization.spec.md`.

1. **Create the spec file** with YAML frontmatter. Set `version` to when the content was originally implemented (not the current version).

2. **Copy content verbatim** — preserve all sections, rules, and patterns from the original.

3. **Remove freeform status indicators** — convert any `> **Status**: Implemented in v2.2.0` blockquotes into frontmatter fields.

4. **Delete the original** reference doc.

5. **Verify no cross-references are broken**:
   ```powershell
   Select-String -Path "agents/ralph-v2/**/*.md" -Pattern "normalization.md" -Recurse
   ```

## Procedure: Add Frontmatter to an Existing Spec

**Example**: Migrating `specs/ralph-v2-stop-hook-metadata-finalization.spec.md` to frontmatter convention.

1. **Add the 5-field YAML frontmatter block** at the top of the file.
2. **Source `created_at`** from the original drafting date found in any freeform status section.
3. **Remove the freeform `## Status` section** — consolidate into the `status` field.
4. **Preserve all body content** unchanged from `## Problem Statement` onward.

## Post-Migration Checklist

After any docs-to-specs migration:

- [ ] Spec file exists at `specs/<topic>.spec.md` with valid 5-field frontmatter
- [ ] Original source files deleted
- [ ] All cross-references in other files updated to new paths
- [ ] `README.md` directory tree updated (if maintained)
- [ ] `README.md` documentation reference table updated (if maintained)
- [ ] No stale references found via grep scan
- [ ] Git commit with descriptive message (e.g., `docs(agent): merge X docs into unified spec`)

## Cleanup: Remove Legacy Duplicate Directories

When docs are restructured, legacy copies may remain in old locations. Clean up by:

1. **Identify canonical locations** — confirm the new spec/doc location has all content.
2. **Delete legacy directories** — remove entire directories, not just individual files.
3. **Verify no broken references** — grep scan across the workspace.
4. **Update README** — remove deleted directories from the directory tree.
