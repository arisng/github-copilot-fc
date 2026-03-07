---
category: reference
source_session: 260227-144634
source_iteration: 2
source_artifacts:
  - Iteration 2 task-7 self-critique report
  - Iteration 2 review summary
extracted_at: 2026-02-28T22:32:04+07:00
promoted: true
promoted_at: 2026-02-28T22:41:09+07:00
---

# Self-Critique Checklist (11 Dimensions)

> Established by task-7 in Ralph v2.11.0 (Session 260227-144634, Iteration 2). Extended to 11 dimensions in Iteration 3. Used for holistic quality assurance across all files in `agents/ralph-v2/` and `.docs/`.

## The 11 Dimensions

### (a) Version Consistency

Check that all agent file frontmatter versions match the declared version in README.md.

**Verification**:
```powershell
Select-String -Path "agents/ralph-v2/*.agent.md" -Pattern "version:"
```

**Common issue**: README version bumped but agent frontmatter not updated.

### (b) Signal Type Consistency

Verify active signal type references match the current spec (STEER, INFO, PAUSE, ABORT). The former SKIP signal type is replaced by `INFO` with `target: Librarian` and `SKIP_PROMOTION:` message prefix — verify no raw `SKIP` signal references remain outside historical changelog entries. Other removed signal types (e.g., APPROVE) should likewise only appear in historical contexts.

> **Note**: The `INFO + target: Librarian + SKIP_PROMOTION:` convention replaces the former SKIP signal type. References to this convention in operational contexts are valid.

**Verification**:
```powershell
Select-String -Path "agents/ralph-v2/**/*.md" -Pattern "APPROVE|CURATE|\bSKIP\b" -Recurse
```

**Filter**: Matches in version history sections, changelog entries, or the SKIP_PROMOTION convention description are acceptable historical references.

### (c) Contract Field Alignment

Ensure all active frontmatter and contract references use current field names (e.g., `promoted`/`promoted_at`, not `approved`/`approved_at`).

### (d) Cross-File Reference Integrity

Verify every markdown link (`](...)`) resolves to an existing file. Check both relative and absolute paths.

**Common issues**:
- Links to files that were deleted/migrated (e.g., `docs/reference/normalization.md` → `specs/normalization.spec.md`)
- Workspace-root-relative paths used where file-relative paths are required

**Verification**: For each markdown link in a file, manually resolve the relative path from the file's directory and confirm the target exists.

### (e) Terminology Consistency

Verify active terminology matches current conventions:
- "promoted" not "approved" (in active contexts)
- EXTRACT/STAGE/PROMOTE not old mode names
- Current signal names used in operational sections

### (f) README Accuracy

Cross-check README against actual filesystem:

```powershell
Get-ChildItem -Path "agents/ralph-v2/" -Recurse -File |
  Select-Object @{N='RelativePath'; E={$_.FullName.Replace((Resolve-Path "agents/ralph-v2/").Path, '')}}
```

Verify:
- Directory tree matches filesystem (file count, names, structure)
- Documentation reference table lists correct paths
- Version history entries are accurate

### (g) Duplicate File Detection

Check for files with the same name across different directories:

```powershell
Get-ChildItem -Path "agents/ralph-v2/" -Recurse -File |
  Group-Object Name |
  Where-Object { $_.Count -gt 1 }
```

### (h) Spec Format Consistency

Verify all specs have valid YAML frontmatter with the 5 required fields (title, status, version, created_at, updated_at).

### (i) Stale Content Detection

Grep for references to deleted directories or files:

```powershell
Select-String -Path "agents/ralph-v2/**/*.md" -Pattern "appendixes|docs/specs/|/templates/" -Recurse
```

**Filter**: References in historical changelog entries are acceptable.

### (j) Knowledge Self-Containment

Verify no promoted `.docs/` files contain ephemeral session references. Promoted knowledge must stand alone without requiring access to session-specific artifacts.

**Scan patterns**:
- `iterations/\d+/` — session iteration references
- `\.ralph-sessions/` — session directory references
- `\d{6}-\d{6}` — session ID format (e.g., `260227-144634`)

**Filter**: Generic template patterns in how-to guides (e.g., `iterations/<N>/`, `<SESSION_ID>`) are acceptable. The `source_session` and `source_iteration` scalar frontmatter fields are acceptable traceability metadata. Only concrete session-relative paths (e.g., `iterations/2/reports/task-7-report.md`) and literal session IDs in body text are violations.

**Verification**:
```powershell
Select-String -Path ".docs/**/*.md" -Pattern "iterations/\d+/|\.ralph-sessions/|\d{6}-\d{6}" -Recurse
```

**Common issues**:
- `source_artifacts` frontmatter containing session-relative paths (should be transformed to descriptive labels)
- Body text referencing specific iteration reports or session directories
- Residual `staged`/`staged_at` frontmatter fields from pre-transformation promotion

### (k) Sub-Category Structure Consistency

Verify files in `.docs/` are placed in appropriate sub-category folders per domain taxonomy and that the folder structure is internally consistent.

**Threshold checks**:
1. No sub-category folder should have fewer than 3 files (below threshold → files should be at category root)
2. No category root should have more than 5 files sharing a domain keyword (should be sub-categorized)
3. `index.md` must reflect the actual folder structure (all categories and sub-categories listed)

**Verification**:
```powershell
# Check sub-category folder file counts
Get-ChildItem -Path ".docs" -Directory -Recurse |
  Where-Object { $_.Parent.Name -ne ".docs" } |
  ForEach-Object { [PSCustomObject]@{ Path = $_.FullName.Replace((Resolve-Path ".docs").Path, ''); Count = (Get-ChildItem $_.FullName -File).Count } } |
  Where-Object { $_.Count -lt 3 -and $_.Count -gt 0 }

# Check category root file overflow
Get-ChildItem -Path ".docs" -Directory |
  Where-Object { $_.Name -ne "research" } |
  ForEach-Object { [PSCustomObject]@{ Category = $_.Name; RootFiles = (Get-ChildItem $_.FullName -File -MaxDepth 0).Count } } |
  Where-Object { $_.RootFiles -gt 5 }
```

**Common issues**:
- Sub-category created with only 1–2 files (below ≥3 threshold)
- Files left at category root when a matching sub-category already exists
- `index.md` not updated after file moves

## Quantitative Results (Iteration 2)

The self-critique process ran 3 passes:

| Pass   | Issues Found | Severity Breakdown         | Resolved       |
| ------ | ------------ | -------------------------- | -------------- |
| Pass 1 | 4            | 1 Critical, 3 Major        | 4/4            |
| Pass 2 | 1            | 1 Major (missed by Pass 1) | 1/1            |
| Pass 3 | 0            | —                          | — (Clean Pass) |

### Issues Found and Root Causes

| ID        | Severity | Dimension     | Issue                                                       | Root Cause                                                     |
| --------- | -------- | ------------- | ----------------------------------------------------------- | -------------------------------------------------------------- |
| ISS-C-001 | Critical | (a) Version   | 6 agent files at v2.10.0, README at v2.11.0                 | README version bumped in task-6, agent frontmatter not updated |
| ISS-M-001 | Major    | (d) Cross-ref | critique.md line 249 linked to deleted normalization.md     | File migrated in task-3, link not updated                      |
| ISS-M-002 | Major    | (i) Stale     | stop-hook spec lines 24, 154 referenced deleted appendixes/ | Directory deleted in task-5, spec not updated                  |
| ISS-M-003 | Major    | (d) Cross-ref | critique.md line 274 used workspace-root-relative path      | Incorrect relative path pattern (not caught in Pass 1)         |
