# [Custom Agents (.agent.md)](https://docs.github.com/en/copilot/reference/custom-agents-configuration)

Custom personas for Copilot CLI with specific instructions, tools, and invocation behavior.

## Locations

| Path | Scope |
|------|-------|
| `.github/agents/*.agent.md` | Repository |
| `~/.copilot/agents/*.agent.md` | Personal |

## Frontmatter

```yaml
---
description: "Use when reviewing CLI plugin bundles, command wiring, or bundle install problems."
name: "Plugin Bundle Reviewer"
tools: [read, search]
user-invocable: true
disable-model-invocation: true
target: github-copilot
mcp-servers:
  - type: http
    url: https://example.com/mcp
    name: example-server
---
```

## Key CLI Fields

| Field | Meaning |
|-------|---------|
| `description` | Required discovery surface for agent selection and delegation |
| `name` | Optional display name; defaults to filename when omitted |
| `tools` | Tool restrictions for the agent |
| `user-invocable` | Controls whether users can select the agent directly |
| `disable-model-invocation` | Prevents automatic model selection while still allowing manual use |
| `target` | Runtime targeting such as `github-copilot` or `vscode` |
| `mcp-servers` | Per-agent remote MCP server declarations |

## Important CLI Differences

- CLI uses `disable-model-invocation`, `target`, and `mcp-servers`
- VS Code-specific fields such as `agents:` and `argument-hint:` do not belong in CLI-focused agent docs
- Per-agent `model` settings are not the main CLI control surface; use `/model` or `--model` at session level

## Invocation Control

| Attribute | Effect |
|-----------|--------|
| `user-invocable: false` | Hide from manual selection; only callable programmatically |
| `disable-model-invocation: true` | Prevent automatic model selection while keeping manual invocation available |

Do not confuse the two. An internal-only agent may need both, but most user-started orchestrators only need `disable-model-invocation: true`.

## Tool Surface Notes

CLI agent behavior is shaped by both agent frontmatter and session-level permissions such as:

- `--allow-tool`
- `--deny-tool`
- `--available-tools`
- `--excluded-tools`

Write agent guidance with terminal-first permissions in mind, not editor picker assumptions.

## Template

```markdown
---
description: "Use when debugging Copilot CLI hooks, hook scripts, or tool-blocking behavior."
tools: [read, search]
disable-model-invocation: true
---
You are a specialist in Copilot CLI hook authoring and troubleshooting.

## Constraints
- Focus on CLI hook schema and runtime behavior
- Do not drift into general coding advice

## Approach
1. Inspect the hook files and related scripts
2. Check event names and field names against the CLI schema
3. Return the smallest concrete fix or explanation
```

## Core Principles

1. **Keep the persona narrow**: One role, one job
2. **Use the minimum tool set**: More tools dilute behavior
3. **Write discovery-friendly descriptions**: Include trigger phrases
4. **Stay runtime-aware**: CLI and VS Code agents are not interchangeable

## Anti-patterns

- **Copying VS Code `agents:` lists into CLI docs**
- **Using `mcpServers` instead of `mcp-servers`**
- **Relying on per-agent model pinning for CLI**
- **Hiding a user-facing agent by setting both invocation controls without intent**
