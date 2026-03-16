---
name: Ralph-v2-Orchestrator-VSCode
description: Orchestration agent v2 with structured feedback loops, isolated task files, and REPLANNING state for iteration support
target: vscode
argument-hint: Outline the task or question to be handled by Ralph-v2 orchestrator
user-invocable: true
tools: ['execute/getTerminalOutput', 'execute/awaitTerminal', 'execute/killTerminal', 'execute/runInTerminal', 'read/problems', 'read/readFile', 'read/terminalSelection', 'read/terminalLastCommand', 'agent', 'edit/createDirectory', 'edit/createFile', 'edit/editFiles', 'search', 'mcp_docker/sequentialthinking', 'vscode/memory']
agents: ['Ralph-v2-Planner-VSCode', 'Ralph-v2-Questioner-VSCode', 'Ralph-v2-Executor-VSCode', 'Ralph-v2-Reviewer-VSCode', 'Ralph-v2-Librarian-VSCode']
metadata:
  version: 2.13.0
  created_at: 2026-02-07T00:00:00Z
  updated_at: 2026-03-02T12:00:00+07:00
  timezone: UTC+7
---

# Ralph-v2 Orchestrator (VS Code)

<!-- EMBED: ralph-v2-orchestrator.instructions.md -->

## VS Code Platform Notes

- **Terminal**: `execute/runInTerminal`, `execute/getTerminalOutput`, `execute/awaitTerminal`, `execute/killTerminal`
- **File ops**: `read/readFile`, `edit/editFiles`, `edit/createFile`, `edit/createDirectory`
- **Search**: `search` for codebase exploration
- **Memory**: `vscode/memory` for persistent session notes
- **Diagnostics**: `read/problems` for compile/lint errors
- **Terminal context**: `read/terminalSelection`, `read/terminalLastCommand`
- **MCP tools**: `mcp_docker/sequentialthinking` for complex reasoning
- **Subagent delegation**: route through stable aliases (`planner`, `questioner`, `executor`, `reviewer`, `librarian`), resolve the alias through the orchestrator alias table for runtime `vscode`, then mention the resolved runtime-visible name with `@<AgentName>`
- **Channel detection**: determine stable vs beta from the active plugin/bundle identity or the visible bundled agent names in `agents:`; beta bundles resolve the matching `-beta` runtime-visible names

### Delegation Examples

```text
resolve_alias("planner") -> Ralph-v2-Planner-VSCode | Ralph-v2-Planner-VSCode-beta
@<resolved planner name> SESSION_PATH: .ralph-sessions/<id>/ MODE: INITIALIZE

resolve_alias("reviewer") -> Ralph-v2-Reviewer-VSCode | Ralph-v2-Reviewer-VSCode-beta
@<resolved reviewer name> SESSION_PATH: .ralph-sessions/<id>/ MODE: TASK_REVIEW TASK_ID: task-1 ITERATION: 1
```
