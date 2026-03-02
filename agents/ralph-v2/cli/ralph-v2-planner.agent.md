---
name: Ralph-v2-Planner
description: Planning agent v2 with isolated task files, iteration-scoped artifacts, and REPLANNING mode for feedback-driven iteration support
tools:
  - bash
  - view
  - edit
  - create
metadata:
  version: 2.13.0
  created_at: 2026-03-02T14:10:35+07:00
  updated_at: 2026-03-02T14:10:35+07:00
  timezone: UTC+7
---

# Ralph-v2 Planner (CLI)

> **Shared instructions**: The platform-agnostic planning workflow, modes (INITIALIZE, UPDATE, TASK_BREAKDOWN, REBREAKDOWN, SPLIT_TASK, UPDATE_METADATA, REPAIR_STATE, CRITIQUE_TRIAGE, CRITIQUE_BREAKDOWN), templates, artifacts, signals, and contract for this agent are defined in [instructions/ralph-v2-planner.instructions.md](../../../instructions/ralph-v2-planner.instructions.md).
>
> **You MUST read the shared instruction file before executing any planning mode.**

## CLI Platform Notes

- **Shell**: `bash` for terminal commands (git operations, file discovery)
- **File ops**: `view` for reading files, `edit` for modifying files, `create` for new files
- **Search**: `bash` with `grep`, `find`, `cat` for codebase exploration
- **MCP tools (shared)**: Docker MCP gateway (via `~/.copilot/mcp-config.json`): Sequential Thinking, Brave Search (web_search + summarizer), Fetch, Context7, DuckDuckGo
- **No persistent memory**: copilot-cli has no built-in memory tool; use session files for context persistence
- **No `web` tool**: Use Brave Search and Fetch MCP tools for web research
