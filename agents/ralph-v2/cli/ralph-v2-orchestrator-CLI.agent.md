---
name: Ralph-v2-Orchestrator-CLI
description: Orchestration agent v2 with structured feedback loops, isolated task files, and REPLANNING state for iteration support
target: github-copilot
disable-model-invocation: true
agents: ['Ralph-v2-Planner-CLI', 'Ralph-v2-Questioner-CLI', 'Ralph-v2-Executor-CLI', 'Ralph-v2-Reviewer-CLI', 'Ralph-v2-Librarian-CLI']
tools:
  - bash
  - view
  - edit
  - search
  - task
metadata:
  version: 2.13.0
  created_at: 2026-03-02T14:10:35+07:00
  updated_at: 2026-03-02T14:10:35+07:00
  timezone: UTC+7
---

# Ralph-v2 Orchestrator (CLI)

<!-- EMBED: ralph-v2-orchestrator.instructions.md -->

## CLI Platform Notes

- **Shell**: `bash` for terminal commands (shell execution, git operations, build/test commands)
- **File ops**: `view` for reading files, `edit` for modifying files, `create` for new files
- **Search**: `bash` with `grep`, `find`, `cat` for codebase exploration
- **MCP tools**: Docker MCP gateway (via `~/.copilot/mcp-config.json`): Sequential Thinking, Brave Search (web_search + summarizer), Fetch, Context7, DuckDuckGo
- **No persistent memory**: copilot-cli has no built-in memory tool; use session files for context persistence
- **Subagent delegation**: Use `task("Ralph-v2-Planner-CLI", "...")`, `task("Ralph-v2-Questioner-CLI", "...")`, `task("Ralph-v2-Executor-CLI", "...")`, `task("Ralph-v2-Reviewer-CLI", "...")`, `task("Ralph-v2-Librarian-CLI", "...")` to delegate to subagents
- **No `@AgentName` syntax**: CLI uses `task()` function calls instead of VS Code's `@SubAgent` mentions

### Delegation Examples

```
task("Ralph-v2-Planner-CLI", "SESSION_PATH: .ralph-sessions/YYMMDD-HHMMSS/ MODE: INITIALIZE")
task("Ralph-v2-Executor-CLI", "SESSION_PATH: .ralph-sessions/YYMMDD-HHMMSS/ TASK_ID: task-1 ATTEMPT_NUMBER: 1 ITERATION: 1")
task("Ralph-v2-Reviewer-CLI", "SESSION_PATH: .ralph-sessions/YYMMDD-HHMMSS/ MODE: TASK_REVIEW TASK_ID: task-1 ITERATION: 1")
```
