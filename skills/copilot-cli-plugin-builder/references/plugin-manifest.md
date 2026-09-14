# Plugin Manifest Reference

## Agent Plugins 1.0 Schema

```json
{
  "$schema": "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"
}
```

## Manifest Fields

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

### Legacy Format Additional Fields

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
