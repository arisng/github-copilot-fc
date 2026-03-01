---
category: how-to
source_session: 260227-144634
source_iteration: 1
source_artifacts:
  - iterations/1/tasks/task-7.md
  - iterations/1/reports/task-7-report.md
  - iterations/1/review.md
staged_at: 2026-02-27T16:07:02+07:00
approved: true
approved_at: 2026-02-27T16:09:38+07:00
---

# How to Verify a Rename Cascade Across Agent Files

## Goal

After renaming a mode, state, or keyword across multiple Ralph-v2 agent files, verify that:
- All old references are removed (except changelog documentation)
- All new references are correctly placed
- No cross-reference inconsistencies exist between agents

## Procedure

### 1. Define Verification Scope

List all files that were modified or could reference the renamed term:

```
agents/ralph-v2/*.agent.md
agents/ralph-v2/README.md
agents/ralph-v2/docs/*.md
```

### 2. Run Stale Name Grep

For each old name, verify zero active usage:

```powershell
Select-String -Path "agents/ralph-v2/*.agent.md","agents/ralph-v2/README.md","agents/ralph-v2/docs/*.md" -Pattern "OLD_NAME"
```

**Expected result**: Zero matches, or matches only in changelog entries documenting the rename itself.

**Exception rule**: Compound names that embed the old keyword (e.g., `plan-knowledge-approval` contains `KNOWLEDGE_APPROVAL` as a substring) are a different naming convention and must be preserved.

### 3. Run New Name Coverage Check

Verify the new name appears in all expected locations:

```powershell
Select-String -Path "agents/ralph-v2/*.agent.md" -Pattern "NEW_NAME"
```

Cross-check against expected locations: frontmatter, mode listings, workflow headers, contract enums, checklist headers, signal checkpoint tables.

### 4. Verify Contract Schema Alignment

For each agent with a contract block, extract the MODE enum and verify it matches the expected set:

| Agent | Expected MODE Enum |
|-------|--------------------|
| Librarian | `STAGE \| PROMOTE \| CURATE` |
| Planner | `INITIALIZE \| UPDATE \| TASK_BREAKDOWN \| REBREAKDOWN \| SPLIT_TASK \| UPDATE_METADATA \| REPAIR_STATE` |

### 5. Verify Semantic Consistency

Check that no documentation text implies the old semantics. Example: if knowledge scoping changed from iteration to session, verify no text says "iteration-scoped knowledge".

### 6. Verify Version Consistency

All modified agent files should have the same version in frontmatter:

```powershell
Select-String -Path "agents/ralph-v2/*.agent.md" -Pattern "version:" | Select-Object -First 15
```

### 7. Assert Clean Result

Summarize total assertions and pass/fail. Example from v2.9.0 verification:
