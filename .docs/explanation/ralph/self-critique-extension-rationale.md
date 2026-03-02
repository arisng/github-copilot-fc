---
category: explanation
source_session: "260227-144634"
source_iteration: 3
source_artifacts:
  - "Iteration 3 task-6 spec and report — self-critique checklist extension"
  - "Iteration 3 task-6 attempt 2 rework report"
extracted_at: "2026-03-01T12:35:28+07:00"
promoted: true
promoted_at: "2026-03-01T12:43:56+07:00"
---

# Why the Self-Critique Checklist Was Extended from 9 to 11 Dimensions

## Background

The Ralph v2 self-critique checklist is a validation framework that runs after implementation tasks complete, scanning all agent files and workspace wiki content for consistency issues across multiple dimensions. Each dimension checks a specific class of potential problem — version mismatches, stale references, broken links, duplicate files, and more.

The checklist originally contained 9 dimensions (a through i), established during earlier iterations to catch common consistency issues.

## New Dimensions

### Dimension (j): Knowledge Self-Containment

**Problem solved**: Promoted knowledge files in the workspace wiki were found to contain ephemeral session references — concrete iteration paths, session IDs, and pipeline-internal metadata fields. These references are meaningless outside their originating session and make the wiki files non-portable.

**What it checks**:
- Scan for patterns matching concrete iteration paths (e.g., `iterations/2/reports/...`)
- Scan for session directory references (e.g., `.ralph-sessions/...`)
- Scan for session ID patterns (six-digit date followed by six-digit time)
- Check frontmatter `source_artifacts` for session-relative paths instead of descriptive labels
- Check for pipeline-internal fields (`staged`, `staged_at`) that should have been stripped during promotion

**Acceptable exceptions**:
- Generic template patterns in how-to guides (e.g., `iterations/<N>/`)
- Frontmatter `source_session` field (provenance metadata, intentionally preserved)
- Code block examples showing placeholder formats

**Verification command**:
```powershell
Select-String -Path ".docs/**/*.md" -Pattern "iterations/\d+/|\.ralph-sessions/|\d{6}-\d{6}" -Recurse
```

### Dimension (k): Sub-Category Structure Consistency

**Problem solved**: After introducing domain-based sub-categories to the workspace wiki, the directory structure needs ongoing validation to ensure sub-folders aren't created prematurely (below the ≥3-file threshold) and that category roots don't accumulate too many files sharing a domain.

**What it checks**:
- No sub-category folder has fewer than 3 files (threshold violation — folder should not exist)
- No category root has more than 5 files sharing a single domain keyword (should have been sub-categorized)
- The wiki `index.md` accurately reflects the actual folder structure (no phantom entries, no missing files)

## Updated Dimension

### Dimension (b): Signal Type Consistency

**Change**: Updated to reflect the reduction from 5 signal types to 4. The valid active set is now **STEER, INFO, PAUSE, ABORT**. The former `SKIP` signal type was replaced by a targeted INFO convention (`INFO + target: Librarian + SKIP_PROMOTION:` prefix). The verification regex now includes `\bSKIP\b` to catch stale references. Historical/changelog mentions of SKIP are acceptable; active operational references are not.

## Why These Dimensions Matter

The original 9 dimensions caught issues like version drift, broken cross-references, stale terminology, and duplicate files. The two new dimensions address structural gaps that emerged as the system matured:

- **Dimension (j)** prevents knowledge decay — without it, promoted files silently accumulate ephemeral references that erode wiki quality over time. The self-containment content transformation step in the promotion workflow prevents new violations, but dimension (j) catches anything that slips through or predates the transformation.

- **Dimension (k)** prevents structural drift — sub-categories can become too sparse (premature creation) or category roots can become cluttered (missed consolidation). Both degrade navigation and discoverability.

Together, the 11 dimensions form a comprehensive quality gate that validates the full lifecycle: from agent consistency (a, b, c, e) to documentation integrity (d, f, g, h, i) to knowledge quality (j, k).
