---
name: Ralph-v2-Orchestrator
description: Orchestration agent v2 with structured feedback loops, isolated task files, and REPLANNING state for iteration support
infer: false
tools:
  - bash
  - view
  - edit
  - create
  - task
metadata:
  version: 2.13.0
  created_at: 2026-03-02T14:10:35+07:00
  updated_at: 2026-03-02T14:10:35+07:00
  timezone: UTC+7
---

# Ralph-v2 Orchestrator (CLI)

<!-- NOTE: Orchestrator is excluded from instruction embedding (46.4K combined exceeds 30K limit). 
     Instructions must be read at runtime via the shared instruction file reference. -->

> **Shared instructions**: The platform-agnostic orchestration workflow, state machine, feedback loop protocols, signals, and contract for this agent are defined in [instructions/ralph-v2-orchestrator.instructions.md](../../../instructions/ralph-v2-orchestrator.instructions.md).
>
> **You MUST read the shared instruction file before executing any orchestration logic.**

## CLI Platform Notes

- **Shell**: `bash` for terminal commands (shell execution, git operations, build/test commands)
- **File ops**: `view` for reading files, `edit` for modifying files, `create` for new files
- **Search**: `bash` with `grep`, `find`, `cat` for codebase exploration
- **MCP tools**: Docker MCP gateway (via `~/.copilot/mcp-config.json`): Sequential Thinking, Brave Search (web_search + summarizer), Fetch, Context7, DuckDuckGo
- **No persistent memory**: copilot-cli has no built-in memory tool; use session files for context persistence
- **Subagent delegation**: Use `task("Ralph-v2-Planner", "...")`, `task("Ralph-v2-Questioner", "...")`, `task("Ralph-v2-Executor", "...")`, `task("Ralph-v2-Reviewer", "...")`, `task("Ralph-v2-Librarian", "...")` to delegate to subagents
- **No `@AgentName` syntax**: CLI uses `task()` function calls instead of VS Code's `@SubAgent` mentions

### Delegation Examples

```
task("Ralph-v2-Planner", "SESSION_PATH: .ralph-sessions/YYMMDD-HHMMSS/ MODE: INITIALIZE")
task("Ralph-v2-Executor", "SESSION_PATH: .ralph-sessions/YYMMDD-HHMMSS/ TASK_ID: task-1 ATTEMPT_NUMBER: 1 ITERATION: 1")
task("Ralph-v2-Reviewer", "SESSION_PATH: .ralph-sessions/YYMMDD-HHMMSS/ MODE: TASK_REVIEW TASK_ID: task-1 ITERATION: 1")
```
