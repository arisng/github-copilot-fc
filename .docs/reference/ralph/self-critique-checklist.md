---
category: reference
source_session: 260227-144634
source_iteration: 2
source_artifacts:
  - iterations/2/reports/task-7-report.md
  - iterations/2/review.md
extracted_at: 2026-02-28T22:32:04+07:00
staged: true
staged_at: 2026-02-28T22:36:14+07:00
promoted: true
promoted_at: 2026-02-28T22:41:09+07:00
---

# Self-Critique Checklist (9 Dimensions)

> Established by task-7 in Ralph v2.11.0 (Session 260227-144634, Iteration 2). Used for holistic quality assurance across all files in `agents/ralph-v2/`.

## The 9 Dimensions

### (a) Version Consistency

Check that all agent file frontmatter versions match the declared version in README.md.

**Verification**:
```powershell
Select-String -Path "agents/ralph-v2/*.agent.md" -Pattern "version:"
```

**Common issue**: README version bumped but agent frontmatter not updated.

### (b) Signal Type Consistency

Verify active signal type references match the current spec (STEER, INFO, PAUSE, ABORT). Removed signal types (e.g., APPROVE, SKIP) should only appear in historical changelog entries.

> **Note**: The `INFO + target: Librarian + SKIP_PROMOTION:` convention replaces the former SKIP signal type. References to this convention in operational contexts are valid.

**Verification**:
```powershell
Select-String -Path "agents/ralph-v2/**/*.md" -Pattern "APPROVE|CURATE" -Recurse
```

**Filter**: Matches in version history sections or changelog entries are acceptable historical references.

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

## Quantitative Results (Iteration 2)

The self-critique process ran 3 passes:

| Pass | Issues Found | Severity Breakdown | Resolved |
|------|-------------|-------------------|----------|
| Pass 1 | 4 | 1 Critical, 3 Major | 4/4 |
| Pass 2 | 1 | 1 Major (missed by Pass 1) | 1/1 |
| Pass 3 | 0 | — | — (Clean Pass) |

### Issues Found and Root Causes

| ID | Severity | Dimension | Issue | Root Cause |
|----|----------|-----------|-------|------------|
| ISS-C-001 | Critical | (a) Version | 6 agent files at v2.10.0, README at v2.11.0 | README version bumped in task-6, agent frontmatter not updated |
| ISS-M-001 | Major | (d) Cross-ref | critique.md line 249 linked to deleted normalization.md | File migrated in task-3, link not updated |
| ISS-M-002 | Major | (i) Stale | stop-hook spec lines 24, 154 referenced deleted appendixes/ | Directory deleted in task-5, spec not updated |
| ISS-M-003 | Major | (d) Cross-ref | critique.md line 274 used workspace-root-relative path | Incorrect relative path pattern (not caught in Pass 1) |
