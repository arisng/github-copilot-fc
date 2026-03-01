---
category: reference
source_session: 260227-144634
source_iteration: 1
source_artifacts:
  - iterations/1/plan.md
  - iterations/1/reports/task-7-report.md
staged_at: 2026-02-27T16:07:02+07:00
approved: true
approved_at: 2026-02-27T16:09:38+07:00
---

# Ralph v2 Rename Blast Radius Analysis

## Purpose

When renaming a mode, state, or keyword in the Ralph v2 agent system, the blast radius must be assessed to determine which files need modification. This reference documents the scoping rules established during the v2.9.0 rename cascade.

## Blast Radius Boundaries

### In-scope (agent markdown files)

State machine state names, mode parameter values, and cross-references are confined to:

| File Category | Path Pattern | Typical References |
|---------------|--------------|-------------------|
| Agent definitions | `agents/ralph-v2/*.agent.md` | MODE enums, workflow headers, contract blocks, signal tables |
| Agent README | `agents/ralph-v2/README.md` | Agent reference table, mode listings, version history |
| Design docs | `agents/ralph-v2/docs/*.md` | Signal maps, design rationale, critique checklists |

### Out-of-scope (no changes needed)

| Category | Path Pattern | Why Safe |
|----------|--------------|----------|
| Hook configs | `hooks/*.hooks.json` | Reference lifecycle events (onStop), not state machine states |
| Hook scripts | `scripts/hooks/*.ps1`, `*.sh`, `*.py` | Read `metadata.yaml` fields (status, session_id), not mode names |
| Publish scripts | `scripts/publish/*.ps1` | Operate on file paths, not agent content |
| Workspace scripts | `scripts/workspace/*.ps1` | Command dispatch, not agent semantics |
| Toolsets | `toolsets/*.jsonc` | Tool configurations, no agent state references |
| Instructions | `instructions/*.instructions.md` | Language/framework guidelines, no Ralph state refs |

### Verification Command

To confirm zero external references before beginning a rename:

```powershell
# Search everything EXCEPT agents/ralph-v2/ for the old name
Get-ChildItem -Recurse -Include *.md,*.ps1,*.sh,*.py,*.json,*.jsonc -Exclude agents/ralph-v2/** |
  Select-String -Pattern "OLD_NAME" |
  Where-Object { $_.Path -notmatch "ralph-v2" }
```

## Key Rule

> **Rename scope = `agents/ralph-v2/` markdown files only.**
> No external scripts, hooks, or configurations reference state machine state names.

This was verified by grep during the v2.9.0 rename (KNOWLEDGE_APPROVAL → CURATE, REBREAKDOWN_TASK → SPLIT_TASK) with 0 external matches found.

## Exceptions

- **`plan-*` task names** (e.g., `plan-knowledge-approval`): These follow a `plan-<concept>` naming convention independent of mode names. They are explicitly preserved during mode renames.
- **Signal type names** (e.g., `APPROVE`, `SKIP`, `STEER`): These are a separate controlled vocabulary. Mode renames must not collide with existing signal types (see: [CURATE rename rationale](../../explanation/ralph/curate-rename-rationale.md)).
