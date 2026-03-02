---
category: how-to
source_session: "260227-144634"
source_iteration: 3
source_artifacts:
  - "Iteration 3 task-1 spec and report — self-contained knowledge enforcement"
extracted_at: "2026-03-01T12:35:28+07:00"
promoted: true
promoted_at: "2026-03-01T12:43:56+07:00"
---

# How to Ensure Promoted Knowledge Is Self-Contained

## Problem

When knowledge files are promoted from a session staging area to the workspace wiki, they may carry ephemeral references — session-relative file paths, session IDs, iteration numbers, and pipeline-internal bookkeeping fields. These references are meaningless outside the originating session and degrade the wiki's standalone usability.

## Solution: Two-Layer Prevention

Self-containment is enforced at two layers: **upstream authoring** (prevention) and **downstream transformation** (correction).

### Layer 1 — Authoring Guideline (Upstream Prevention)

During knowledge extraction, authors follow a self-containment discipline:

> Write body content as standalone documents. Never reference session-relative paths, session IDs, or iteration numbers in prose. Use descriptive context instead (e.g., "during the rename cascade task" rather than citing a specific task identifier from a specific iteration). Frontmatter traceability fields handle provenance — the body stands alone.

This guideline is enforced as a step in the extraction workflow, between writing the files and adding traceability frontmatter.

### Layer 2 — Content Transformation (Downstream Correction)

During promotion, a content transformation step runs after the merge algorithm and before marking files as promoted. This step performs four operations:

1. **Frontmatter `source_artifacts` path transformation**: Replace session-relative paths (e.g., file references like `reports/task-2-report.md`) with descriptive labels (e.g., "Iteration 2 task-2 report"). Scalar fields like `source_session` and `source_iteration` are kept as-is since they are values, not paths.

2. **Strip pipeline bookkeeping**: Remove fields that are only meaningful within the staging pipeline (e.g., `staged`, `staged_at`). These are internal lifecycle markers irrelevant after promotion.

3. **Body text scan**: Scan the document body for patterns matching ephemeral session references:
   - Concrete iteration paths (e.g., `iterations/2/reports/...`)
   - Session directory references (e.g., `.ralph-sessions/...`)
   - Session ID patterns (six-digit date followed by six-digit time)
   
   Replace concrete references with descriptive text. Generic template references in how-to guides (e.g., `iterations/<N>/`) are left intact since they describe a pattern, not a specific session.

4. **Stale signal scan**: Flag references to signal types that have been removed from the protocol (e.g., deprecated signal names). These are marked for manual review since they may indicate outdated content.

## Verification

After promotion, validate self-containment by scanning for residual ephemeral references:

```powershell
Select-String -Path ".docs/**/*.md" -Pattern "iterations/\d+/|\.ralph-sessions/|\d{6}-\d{6}" -Recurse
```

Filter acceptable matches:
- Frontmatter `source_session` fields (provenance metadata, acceptable)
- Generic template patterns in how-to guides (e.g., `iterations/<N>/`)
- Code block examples showing placeholder formats

Any remaining matches outside these categories indicate a self-containment violation.
