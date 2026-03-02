---
name: Ralph-v2-Questioner
description: Q&A discovery agent v2 with feedback-analysis mode for replanning and structured question files per category
tools:
  - bash
  - view
  - edit
  - create
mcp-servers:
  microsoftdocs:
    type: http
    url: https://learn.microsoft.com/api/mcp
  deepwiki:
    type: http
    url: https://mcp.deepwiki.com/mcp
metadata:
  version: 2.13.0
  created_at: 2026-03-02T14:10:35+07:00
  updated_at: 2026-03-02T14:10:35+07:00
  timezone: UTC+7
---

# Ralph-v2 Questioner (CLI)

> **Shared instructions**: The platform-agnostic Q&A discovery workflow, modes (brainstorm, research, feedback-analysis), question templates, signals, and contract for this agent are defined in [instructions/ralph-v2-questioner.instructions.md](../../../instructions/ralph-v2-questioner.instructions.md).
>
> **You MUST read the shared instruction file before executing any Q&A mode.**

## CLI Platform Notes

- **Shell**: `bash` for terminal commands (git operations, file discovery)
- **File ops**: `view` for reading files, `edit` for modifying files, `create` for new files
- **Search**: `bash` with `grep`, `find`, `cat` for codebase exploration
- **MCP tools (shared)**: Docker MCP gateway (via `~/.copilot/mcp-config.json`): Sequential Thinking, Brave Search (web_search + summarizer), Fetch, Context7, DuckDuckGo
- **MCP tools (agent-specific)**: Microsoft Docs (`microsoftdocs`), DeepWiki (`deepwiki`) — bundled via `mcp-servers:` frontmatter
- **No persistent memory**: copilot-cli has no built-in memory tool; use session files for context persistence
- **No `web` tool**: Use Brave Search and Fetch MCP tools for web research
- **GitHub tools**: Built-in to copilot-cli — no separate configuration needed
