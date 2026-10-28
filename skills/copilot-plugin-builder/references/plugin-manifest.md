# Plugin Manifest Reference

Grounded in the [Agent plugin authoring reference](https://code.visualstudio.com/docs/agents/reference/agent-plugin-reference) and [Creating a plugin for GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-creating).

## Agent Plugins 1.0 Schema

```json
{
  "$schema": "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"
}
```

## Manifest Fields

Only these top-level fields are allowed; unknown fields are reported and ignored.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `$schema` | string | Yes | Always `"https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"` for Agent Plugins 1.0 |
| `name` | string | Yes | 1–64 chars, lowercase ASCII, digits, hyphens, periods |
| `version` | string | No | SemVer string (e.g., `"1.0.0"`) |
| `description` | string | No | Max 1024 chars |
| `author` | object | No | `{ name?, email?, url? }` |
| `homepage` | string | No | URL string |
| `repository` | string | No | URL string |
| `license` | string | No | SPDX identifier (e.g., `"MIT"`) |
| `keywords` | string[] | No | Searchable tags |
| `extensions` | object | No | Client-specific data keyed by reverse-domain namespace (e.g., `"com.github.copilot"`) |

In Agent Plugins 1.0, component locations are fixed: skills must be immediate subdirectories of `skills/` and MCP config must be `mcp.json` at the root — they cannot be overridden in the manifest. Copilot-specific components (agents, commands, rules, hooks, LSP) come from `com.github.copilot/`.

## Plugin Format Detection

| Format | Manifest |
|--------|----------|
| Agent Plugins 1.0 | `plugin.json` with the canonical `$schema` |
| Copilot (legacy) | `plugin.json` without the Agent Plugins `$schema` |
| Claude | `.claude-plugin/plugin.json` |
| Legacy OpenPlugin | `.plugin/plugin.json` |

A root `plugin.json` that declares the Agent Plugins `$schema` uses Agent Plugins semantics; the Copilot format is the default when no other format marker is found.

### Legacy Format Additional Fields

Legacy format only (omit the Agent Plugins `$schema`):

| Field | Type | Description |
|-------|------|-------------|
| `agents` | string | Path to agents directory |
| `skills` | string[] | Paths to skills directories |
| `hooks` | string | Path to hooks.json |
| `mcpServers` | string | Path to MCP config |
| `interface` | object | `{ displayName, category, capabilities }` |

## Validation Rules

- `name`: Must match `^[a-z0-9][a-z0-9.\-]{0,63}$`
- `version`: Must be valid SemVer if provided
- `description`: Truncated to 1024 chars
- `$schema`: Must be a valid URL

## Automation Template Paths (VS Code)

Automation templates default to `automations/*.automation.md` at the plugin root. Add or replace default folders via the manifest:

```json
{
  "$schema": "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json",
  "name": "my-dev-tools",
  "version": "1.2.0",
  "extensions": {
    "com.github.copilot": {
      "automations": {
        "paths": ["./team-automations/"]
      }
    }
  }
}
```

Paths are relative to the `com.github.copilot/` folder. Set `exclusive: true` alongside `paths` to skip the default `automations/` folder. Automation templates are a VS Code-specific capability, not a portable Agent Plugins 1.0 component type.

## Minimal Plugin

```json
{
  "$schema": "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json",
  "name": "hello-plugin"
}
```

## Full Plugin Example

```json
{
  "$schema": "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json",
  "name": "my-dev-tools",
  "version": "1.2.0",
  "description": "React development utilities",
  "author": {
    "name": "Jane Doe",
    "email": "jane@example.com"
  },
  "homepage": "https://github.com/jane/my-dev-tools",
  "repository": "https://github.com/jane/my-dev-tools",
  "license": "MIT",
  "keywords": ["react", "frontend", "devtools"]
}
```

## MCP Server Config (`mcp.json`)

```json
{
  "$schema": "https://agent-plugins.org/schemas/1.0.0/mcp.schema.json",
  "mcpServers": {
    "server-name": {
      "type": "stdio",
      "command": "node",
      "args": ["${PLUGIN_ROOT}/server/index.js"],
      "cwd": "${PLUGIN_ROOT}",
      "env": { "DATA_DIR": "${PLUGIN_DATA}" }
    }
  }
}
```

### Supported Transports

| Transport | Description |
|-----------|-------------|
| `stdio` | Local process communication |
| `streamable-http` | HTTP-based transport |
| `sse` | Server-Sent Events (deprecated) |

### Plugin Variables

| Variable | Expands To |
|----------|------------|
| `${PLUGIN_ROOT}` | Plugin installation directory |
| `${PLUGIN_DATA}` | Plugin data directory |
