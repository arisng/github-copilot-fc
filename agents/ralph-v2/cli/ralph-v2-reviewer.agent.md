---
name: Ralph-v2-Reviewer
description: Quality assurance agent v2 with isolated task files, feedback-aware validation, and structured review reports
infer: true
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

# Ralph-v2 Reviewer (CLI)

> **Shared instructions**: The platform-agnostic quality assurance workflow, review modes (TASK_REVIEW, SESSION_REVIEW, TIMEOUT_FAIL, COMMIT), commit workflow, signals, and contract for this agent are defined in [instructions/ralph-v2-reviewer.instructions.md](../../../instructions/ralph-v2-reviewer.instructions.md).
>
> **You MUST read the shared instruction file before executing any review mode.**

## CLI Platform Notes

- **Shell**: `bash` for terminal commands (git operations, build/test validation)
- **File ops**: `view` for reading files, `edit` for modifying files, `create` for new files
- **Search**: `bash` with `grep`, `find`, `cat` for codebase exploration
- **Testing**: `bash` for running test commands directly
- **Diagnostics**: `bash` with build/lint commands for compile-time validation
- **MCP tools (shared)**: Docker MCP gateway (via `~/.copilot/mcp-config.json`): Sequential Thinking, Brave Search (web_search + summarizer), Fetch, DuckDuckGo
- **No persistent memory**: copilot-cli has no built-in memory tool; use session files for context persistence
- **No `web` tool**: Use Brave Search and Fetch MCP tools for web research
