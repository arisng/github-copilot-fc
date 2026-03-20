---
category: how-to
source_session: 260302-001737
source_iteration: 3
source_artifacts:
  - "Iteration 3 task-6 report (CLI agent variant creation)"
extracted_at: "2026-03-02T15:06:27+07:00"
promoted: true
promoted_at: "2026-03-02T15:17:25+07:00"
---

# How to Create CLI Agent Variants from VS Code Agents

## Goal

Port VS Code custom agents to GitHub Copilot CLI (`copilot-cli`) by creating CLI-specific variant files that reference the same shared instructions.

## Prerequisites

- Shared instruction files already extracted (see "How to Extract Shared Instructions from Agent Files").
- Multi-runtime directory structure in place (`agents/<group>/vscode/` + `agents/<group>/cli/`).
- `~/.copilot/mcp-config.json` populated with shared MCP servers.

## Steps

### 1. Map Tool Namespaces

Replace VS Code tool namespaces with CLI equivalents:

| VS Code Tool | CLI Equivalent | Notes |
|-------------|----------------|-------|
| `execute/runInTerminal` | `bash` | Shell execution |
| `read/readFile` | `view` | File reading |
| `edit/editFiles` | `edit` | File editing |
| `edit/createFile`, `edit/createDirectory` | `create` | File/directory creation |
| `search` (semantic_search, grep, file) | `grep`, `glob`, `cat`, `ls` | Search tools |
| `agent` (subagent invocation) | `task` | Only for orchestrators (`infer: false`) |
| `vscode/memory` | *No equivalent* | Use MCP tools or file-based state |
| `web` | *No equivalent* | Use MCP (Brave Search, DuckDuckGo) |

### 2. Set `infer` and `tools` in Frontmatter

- **Orchestrator** (delegates to subagents): `infer: false`, `tools: [bash, view, edit, create, task]`
- **Subagents** (execute autonomously): `infer: true`, `tools: [bash, view, edit, create]`
- Subagents MUST NOT have the `task` tool — only the orchestrator delegates.

### 3. Configure MCP Server Distribution

Three tiers of MCP server configuration:

| Tier | Location | Scope |
|------|----------|-------|
| Shared | `~/.copilot/mcp-config.json` | All CLI agents automatically |
| Agent-specific | `mcpServers:` in agent YAML frontmatter | Only that agent |
| Built-in | Provided by copilot-cli | All agents (e.g., GitHub tools) |

- Place universally-needed servers (Sequential Thinking, Brave Search, Fetch) in the shared config.
- Bundle domain-specific servers (Microsoft Docs, DeepWiki) in the agents that need them.
- Servers built into copilot-cli (GitHub) need no configuration.

### 4. Write the CLI Variant

Each CLI variant follows this structure:

```markdown
---
name: <agent-name>
description: <one-line description>
infer: true  # or false for orchestrator
tools:
  - bash
  - view
  - edit
  - create
mcpServers:         # only if agent-specific servers needed
  servername:
    type: http
    url: https://...
---

# <Role> (CLI)

> **Shared instructions**: ../../../instructions/<group>-<role>.instructions.md
> You MUST read the shared instruction file above before proceeding.

## CLI Platform Notes
- **Terminal**: `bash` (replaces VS Code `execute/runInTerminal`)
- **File ops**: `view`, `edit`, `create` (replaces VS Code `read/*`, `edit/*`)
- **MCP tools**: [list available MCP servers]
```

### 5. Validate

- **VS Code deny-list scan**: Search CLI variants for VS Code-only patterns (`execute/`, `read/readFile`, `edit/editFiles`, `vscode/memory`, `@AgentName`). Zero matches expected.
- **Instruction path resolution**: Verify all `../../../instructions/` paths resolve to existing files.
- **Version consistency**: All CLI and VS Code variants should share the same `version:` value.
- Run `validate-agent-variants.ps1` for automated deny-list and parity checks.

## MCP Config File Format

The `~/.copilot/mcp-config.json` file uses this structure:

```json
{
  "mcpServers": {
    "server-name": {
      "type": "stdio",
      "command": "docker",
      "args": ["mcp", "gateway", "run"]
    }
  }
}
```

A single Docker MCP gateway entry can expose multiple registered servers (Sequential Thinking, Brave Search, Fetch, Context7, DuckDuckGo) through one configuration.
