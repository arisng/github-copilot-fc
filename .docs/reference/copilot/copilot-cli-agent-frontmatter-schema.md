---
category: reference
source_session: 260302-001737
source_iteration: 4
source_artifacts:
  - "Iteration 4 task-1"
  - "Iteration 4 task-3"
  - "Iteration 4 task-1 report"
  - "Iteration 4 task-3 report"
  - "Iteration 4 feedback-driven questions"
extracted_at: 2026-03-02T16:12:52+07:00
promoted: true
promoted_at: 2026-03-02T16:21:15+07:00
---

# Copilot CLI Custom Agent Frontmatter Schema Reference

Complete reference for YAML frontmatter properties supported by GitHub Copilot CLI (coding agent) custom agents (`.agent.md` files). Based on the official GA specification at https://docs.github.com/en/copilot/reference/custom-agents-configuration.

> **VS Code vs CLI**: Some properties are CLI-only (`disable-model-invocation`, `mcp-servers`, `target`), some are VS Code-only (`agents:`), and some are shared (`name`, `description`, `user-invocable`). VS Code uses `agents:` for subagent referencing; CLI uses the TaskTool auto-delegation model.

---

## Rerferences (Official Documentation)

Periodically verify against the official documentation to ensure accuracy, as the CLI is rapidly evolving and may have discrepancies or silent changes:
([Custom agents configuration](https://docs.github.com/en/copilot/reference/custom-agents-configuration))

## Schema Table

| Property                   | CLI             | VS Code         | Notes                                                                                                                                                                                                                                                                                      |
| -------------------------- | --------------- | --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `name`                     | ✅ Supported     | ✅ Supported     | Display name for the agent                                                                                                                                                                                                                                                                 |
| `description`              | ✅ Supported     | ✅ Supported     | Short description shown in agent selector                                                                                                                                                                                                                                                  |
| `user-invocable`           | ✅ Supported     | ✅ Supported     | Controls whether users can manually invoke the agent via `/agent` or `--agent=` flag. Default: `true`                                                                                                                                                                                      |
| `model`                    | ⚠️ Ignored       | ✅ Supported     | Accepted/parsed but **silently ignored** by CLI and GitHub.com coding agent. VS Code uses it for IDE agent model pinning. No CLI per-agent model override exists — use `/model` slash command or `--model` flag at session level                                                           |
| `infer`                    | ⚠️ (Retired)     | ❌ Not supported | **Retired.** Replaced by `disable-model-invocation` + `user-invocable`. See migration table below                                                                                                                                                                                          |
| `disable-model-invocation` | ✅ Supported     | ❌ Not supported | Prevents automatic agent selection by the model. `true` = model cannot auto-select this agent; user can still invoke manually. Direct replacement for `infer: false`                                                                                                                       |
| `mcp-servers`              | ✅ Supported     | ❌ Not supported | Per-agent MCP server declarations (kebab-case required). `mcpServers` (camelCase) is **silently ignored** — per-agent MCP bundling will be non-functional if camelCase is used                                                                                                             |
| `target`                   | ✅ Supported     | ❌ Not supported | Pin agent to a specific runtime: `vscode` or `github-copilot`. If omitted, defaults to both. Single-file alternative to the variant directory pattern — useful for simple agents; variant directories are preferred for complex agents with different frontmatter requirements per runtime |
| `agents`                   | ❌ Not supported | ✅ Supported     | VS Code-only: declare which subagents are available. CLI uses TaskTool auto-delegation instead                                                                                                                                                                                             |
| `argument-hint`            | ❌ Not supported | ✅ Supported     | VS Code-only: hint text for agent activation argument                                                                                                                                                                                                                                      |

---

## Migration Table: `infer` → Current Keys

| Old (`infer`)  | New (GA)                         | Behavior                                                      |
| -------------- | -------------------------------- | ------------------------------------------------------------- |
| `infer: false` | `disable-model-invocation: true` | Model cannot auto-select this agent; user CAN manually invoke |
| `infer: true`  | Omit key entirely                | Model CAN auto-select this agent (default behavior)           |

**Important**: `disable-model-invocation: true` is **not** the same as `user-invocable: false`:
- `disable-model-invocation: true` — stops the model from *automatically* selecting the agent; manual invocation still works
- `user-invocable: false` — stops *users* from manually selecting the agent; only programmatic access works

For orchestrator agents (agents the user starts manually), use only `disable-model-invocation: true`. Do not set `user-invocable: false` unless the agent is truly internal/programmatic-only.

---

## `mcp-servers` Block Format

```yaml
mcp-servers:
  - type: http
    url: https://example.com/mcp
    name: example-server
```

Only `type: http` (remote HTTP servers) is supported in per-agent `mcp-servers` frontmatter. Local stdio MCP servers must be configured globally via `~/.copilot/mcp-config.json`.

---

## Agent Discovery Paths

| Scope        | Path                               | Platform                                        |
| ------------ | ---------------------------------- | ----------------------------------------------- |
| User-level   | `~/.copilot/agents/`               | All (Windows: `%USERPROFILE%\.copilot\agents\`) |
| Repo-level   | `.github/agents/`                  | All                                             |
| XDG override | `$XDG_CONFIG_HOME/copilot/agents/` | Linux/macOS only, when `XDG_CONFIG_HOME` is set |

- `~/.copilot/agents/` is the confirmed correct default discovery path (**not** `~/.config/copilot/agents/`)
- On Linux/macOS with `XDG_CONFIG_HOME=~/.config`, the effective path becomes `~/.config/copilot/agents/` — this is valid but non-default; publish scripts targeting `~/.copilot/agents/` (Windows primary) are correct

---

## Minimal Valid CLI Agent Frontmatter (Orchestrator)

```yaml
---
name: my-agent
description: "Short description"
disable-model-invocation: true
mcp-servers:
  - type: http
    url: https://mcp.context7.com/mcp
    name: context7
---
```

## Minimal Valid CLI Agent Frontmatter (Subagent / auto-selectable)

```yaml
---
name: my-subagent
description: "Short description"
---
```

Subagents that should be auto-invocable by the model omit `disable-model-invocation` entirely.
