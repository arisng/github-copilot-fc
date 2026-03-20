---
category: reference
source_session: 260302-001737
source_iteration: 9
source_artifacts:
  - "Iteration 9 task-4 task definition"
  - "Iteration 9 task-4 report"
  - "Iteration 9 feedback-driven questions Q-FDB-010"
  - "Iteration 9 session review SC-2"
extracted_at: 2026-03-03T12:57:17+07:00
promoted: true
promoted_at: 2026-03-03T13:04:46+07:00
---

# CLI Agent File Path Convention

## Canonical Location

All Ralph-v2 CLI agent files (`*.agent.md`) are located at:

```
agents/ralph-v2/cli/
```

## Known Stale Path

An earlier directory structure used `agents/v2/` as the agent root. This path is **stale and incorrect**. Any reference to `agents/v2/ralph-v2-*.agent.md` should be updated to `agents/ralph-v2/cli/ralph-v2-*.agent.md`.

## Current Agent Roster

| Agent file | Path |
|------------|------|
| Orchestrator | `agents/ralph-v2/cli/ralph-v2-orchestrator.agent.md` |
| Executor | `agents/ralph-v2/cli/ralph-v2-executor.agent.md` |
| Librarian | `agents/ralph-v2/cli/ralph-v2-librarian.agent.md` |
| Planner | `agents/ralph-v2/cli/ralph-v2-planner.agent.md` |
| Questioner | `agents/ralph-v2/cli/ralph-v2-questioner.agent.md` |
| Reviewer | `agents/ralph-v2/cli/ralph-v2-reviewer.agent.md` |

## Audit Pattern

```powershell
# Detect stale agents/v2/ references across all instruction and agent files
Select-String "agents/v2/" agents/ralph-v2/instructions/*.instructions.md
Select-String "agents/v2/" agents/ralph-v2/cli/*.agent.md
```

Returns 0 matches when all paths are correct.

## Scope Note

Stale paths in instruction source files (`.instructions.md`) propagate into the `.build/` bundle output because these files are embedded at build time via `<!-- EMBED: filename -->` markers. A stale path fix in source requires a subsequent `publish-plugins.ps1 -Force` run to regenerate the bundle.
