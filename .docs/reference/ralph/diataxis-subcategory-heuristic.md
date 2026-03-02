---
category: reference
source_session: "260227-144634"
source_iteration: 3
source_artifacts:
  - "Iteration 3 task-3 spec and report — diataxis-categorizer skill creation"
extracted_at: "2026-03-01T12:35:28+07:00"
promoted: true
promoted_at: "2026-03-01T12:43:56+07:00"
---

# Diátaxis Sub-Category Heuristic (Three-Rule Classification)

## Overview

The Diátaxis framework organizes documentation into four top-level categories: **tutorials**, **how-to**, **reference**, and **explanation**. Within each category, a domain-based sub-category heuristic determines whether a file should be placed in a sub-folder (e.g., `reference/ralph/`) or remain at the category root.

This heuristic is implemented in the `diataxis-categorizer` skill, which supplements the existing `diataxis` skill (responsible for top-level classification).

## The Three Rules

### Rule 1 — Keyword Extraction

Extract the primary domain keyword from the file using a 4-step priority chain:

1. **Filename prefix**: Check if the filename starts with a known domain keyword (e.g., `ralph-artifact-templates.md` → `ralph`)
2. **Frontmatter fields**: Check `category`, `domain`, or similar metadata fields
3. **H1 title**: Extract the dominant domain keyword from the document's main heading
4. **Body content scan**: Count domain keyword occurrences; require >2× frequency over the next-most-common domain to classify confidently

If no single domain dominates, the file is considered **cross-domain** and skips to fallback.

### Rule 2 — Reuse Check

If an existing sub-category folder matches the extracted domain keyword:
- **Action**: Place the file in the existing sub-folder → `<category>/<domain>/filename.md`
- **Rationale**: Reuse keeps related files together without threshold recalculation

### Rule 3 — Create Check (≥3 Threshold)

If no matching sub-category folder exists:
- Count how many other files at the category root (or in the current promotion batch) share the same domain keyword
- **If ≥3 peers share the domain**: Create the sub-category folder and move all matching files into it
- **If <3 peers**: Fall through to fallback

The ≥3 threshold prevents premature sub-categorization that creates sparse directories.

### Fallback

A file stays at the category root when:
- No single domain keyword dominates (cross-domain content)
- Fewer than 3 peers share the domain (below threshold)
- Keyword extraction yields no confident result

## Domain Taxonomy Convention

- **Naming**: `<category>/<domain>/filename.md` using lowercase kebab-case domain names
- **Known domains**: `ralph`, `copilot`, `sdk`, `blazor`, `blazor-agui` (extensible — new domains emerge naturally as files accumulate)
- **Cross-domain files**: Stay at category root (e.g., `reference/urls.md`)

## Research Staging Convention

A `research/` folder is treated as a **staging area**, not a permanent 5th Diátaxis category:
- New exploratory content lands in `research/` initially
- Once mature (addressed in later iterations, conclusions are actionable, relationships to existing categories are clear), files are reclassified into standard Diátaxis categories
- Target maturity timeline: 1–2 iterations
- After reclassification, `research/` retains only a README documenting the staging convention

## Batch Reorganization Workflow

For retroactive reorganization of an existing wiki:

1. **Scan** all files in a category directory
2. **Classify** each file using the three-rule heuristic
3. **Generate manifest** — a JSON list of proposed moves with source, target, and reason
4. **Human review** — review the manifest before execution
5. **Execute** approved moves (create sub-folders, move files, update cross-references)
6. **Regenerate index** with nested sub-category sections
