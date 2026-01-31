---
name: copilot-cli-mcp-config
description: Manage GitHub Copilot CLI MCP server configuration using mcp-config.json. Use when configuring MCP servers for GitHub Copilot CLI in ~/.copilot or custom paths, adding local/remote MCP servers with proper syntax, or understanding differences between GitHub Copilot CLI (mcp-config.json) and VS Code (mcp.json) configuration formats.
version: 1.0.0
---

# GitHub Copilot CLI MCP Configuration Management

Configure MCP servers for GitHub Copilot CLI using the `mcp-config.json` file, which uses different syntax from VS Code's `mcp.json`.

## Configuration Location

**Default**: `~/.copilot/mcp-config.json`

**Custom location**: Set `XDG_CONFIG_HOME` environment variable to redirect configuration directory.

```bash
# In ~/.zshrc or ~/.bashrc
export XDG_CONFIG_HOME="/path/to/your/config"
```

## CLI Commands

```bash
# Add MCP server interactively
copilot /mcp add <server-name>

# Show configured servers
copilot /mcp show

# Remove MCP server
copilot /mcp remove <server-name>
```

## Configuration Syntax

### Root Structure

GitHub Copilot CLI uses `mcpServers` (VS Code uses `servers`):

```json
{
  "mcpServers": {
    "server-name": { /* config */ }
  }
}
```

### Server Types

GitHub Copilot CLI supports four server types:

#### Type: `local` (Local Command Execution)

Run MCP server via local command:

```json
{
  "mcpServers": {
    "serena": {
      "type": "local",
      "command": "uvx",
      "args": [
        "--from",
        "git+https://github.com/oraios/serena",
        "serena",
        "start-mcp-server"
      ],
      "tools": ["*"],
      "env": {
        "API_KEY": "${MY_API_KEY}"
      }
    }
  }
}
```

#### Type: `stdio` (Standard I/O Communication)

Communicate via stdin/stdout (common for local servers):

```json
{
  "mcpServers": {
    "azure": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@azure/mcp@latest", "server", "start"],
      "tools": ["*"],
      "env": {}
    }
  }
}
```

#### Type: `http` (HTTP Server)

Connect to HTTP-based MCP server:

```json
{
  "mcpServers": {
    "github": {
      "type": "http",
      "url": "https://api.githubcopilot.com/mcp/readonly",
      "tools": ["*"],
      "headers": {
        "Authorization": "Bearer ${GITHUB_TOKEN}",
        "X-MCP-Toolsets": "repos,issues,pull_requests"
      }
    }
  }
}
```

#### Type: `sse` (Server-Sent Events)

Connect to SSE-based MCP server:

```json
{
  "mcpServers": {
    "cloudflare": {
      "type": "sse",
      "url": "https://docs.mcp.cloudflare.com/sse",
      "tools": ["*"]
    }
  }
}
```

### Common Configuration Keys

**Required for all types:**
- `type`: Server type (`"local"`, `"stdio"`, `"http"`, `"sse"`)
- `tools`: Array of tool names or `["*"]` for all tools

**Local/stdio specific (required):**
- `command`: Executable command (e.g., `"npx"`, `"uvx"`, `"docker"`)
- `args`: Array of command arguments

**HTTP/sse specific (required):**
- `url`: Server endpoint URL

**Optional for all:**
- `env`: Environment variables object (local/stdio only)
- `headers`: HTTP headers object (http/sse only)

### Environment Variable Expansion

Use `${VAR_NAME}` syntax for variable substitution:

```json
{
  "mcpServers": {
    "sentry": {
      "type": "local",
      "command": "npx",
      "args": ["@sentry/mcp-server@latest", "--host=${SENTRY_HOST}"],
      "tools": ["*"],
      "env": {
        "SENTRY_HOST": "${COPILOT_MCP_SENTRY_HOST}",
        "SENTRY_TOKEN": "${COPILOT_MCP_SENTRY_TOKEN}"
      }
    }
  }
}
```

## VS Code vs GitHub Copilot CLI Syntax Differences

Key differences between `mcp.json` (VS Code) and `mcp-config.json` (GitHub Copilot CLI):

| Feature             | VS Code (mcp.json)                    | GitHub Copilot CLI (mcp-config.json)                                        |
| ------------------- | ------------------------------------- | --------------------------------------------------------------------------- |
| **Root key**        | `"servers"`                           | `"mcpServers"`                                                              |
| **Type values**     | `"stdio"`, `"http"`                   | `"local"`, `"stdio"`, `"http"`, `"sse"`                                     |
| **Env vars**        | Supports `inputs` and `envFile`       | Only `env` object with `${VAR}` syntax                                      |
| **Location**        | `.vscode/mcp.json` or global settings | `~/.copilot/mcp-config.json` or `$XDG_CONFIG_HOME/.copilot/mcp-config.json` |
| **Variable syntax** | Can use `inputs` references           | Must use `${VARIABLE}` syntax                                               |

**VS Code example:**

```json
{
  "servers": {
    "memory": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-memory"],
      "env": {
        "MEMORY_FILE_PATH": "${workspaceFolder}/.github/memory.json"
      },
      "type": "stdio"
    }
  }
}
```

**GitHub Copilot CLI equivalent:**

```json
{
  "mcpServers": {
    "memory": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-memory"],
      "tools": ["*"],
      "env": {
        "MEMORY_FILE_PATH": "${MEMORY_FILE_PATH}"
      }
    }
  }
}
```

## Complete Configuration Examples

### Multiple Servers

```json
{
  "mcpServers": {
    "azure": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@azure/mcp@latest", "server", "start"],
      "tools": ["*"]
    },
    "github": {
      "type": "http",
      "url": "https://api.githubcopilot.com/mcp/readonly",
      "tools": ["get_issue", "list_repositories"],
      "headers": {
        "Authorization": "Bearer ${GITHUB_PAT}"
      }
    },
    "cloudflare": {
      "type": "sse",
      "url": "https://docs.mcp.cloudflare.com/sse",
      "tools": ["*"]
    }
  }
}
```

### Docker-Based Server

```json
{
  "mcpServers": {
    "notion": {
      "type": "local",
      "command": "docker",
      "args": [
        "run", "--rm", "-i",
        "-e", "OPENAPI_MCP_HEADERS={\"Authorization\": \"Bearer ${NOTION_API_KEY}\"}",
        "mcp/notion"
      ],
      "tools": ["*"],
      "env": {
        "NOTION_API_KEY": "${COPILOT_MCP_NOTION_API_KEY}"
      }
    }
  }
}
```

## Setting Custom Output Path

To store configuration in a custom location:

**Option 1: Environment variable (recommended for global change)**

```bash
# In ~/.zshrc or ~/.bashrc
export XDG_CONFIG_HOME="/path/to/config"
```

**Option 2: Temporary override for single session**

```bash
XDG_CONFIG_HOME="/path/to/config" copilot
```

**Option 3: Repository-level configuration (for team standardization)**

Create `.devcontainer/postCreateCommand.sh`:

```bash
#!/bin/bash
GH_CLI_CONFIG_DIR="/workspaces/your-repo"

if ! grep -q 'export XDG_CONFIG_HOME=' ~/.bashrc; then
    echo "export XDG_CONFIG_HOME=\"$GH_CLI_CONFIG_DIR\"" >> ~/.bashrc
fi
```

Add to `.devcontainer/devcontainer.json`:

```json
{
  "postCreateCommand": "bash .devcontainer/postCreateCommand.sh"
}
```

Create `.copilot/mcp-config.json` in repository root with your MCP configuration.

Exclude environment-specific files in `.gitignore`:

```gitignore
.copilot/logs/
.copilot/config.json
```

## Troubleshooting

**Configuration not loading:**
- Verify `XDG_CONFIG_HOME`: `echo $XDG_CONFIG_HOME`
- Check `.copilot/mcp-config.json` exists at expected location
- Restart Copilot CLI

**MCP server not starting:**
- Verify command available (e.g., `which npx`, `which uvx`)
- Check logs in `~/.copilot/logs/` or `$XDG_CONFIG_HOME/.copilot/logs/`
- Test command manually

**Environment variables not expanding:**
- Ensure using `${VAR_NAME}` syntax (not `$VAR_NAME`)
- Verify environment variable is set: `echo $VAR_NAME`
- Check variable is exported: `export VAR_NAME="value"`

**Tools not appearing:**
- Verify `"tools"` field is present (required)
- Use `["*"]` to enable all tools
- Check server initialization logs for errors

## Converting VS Code to CLI Configuration

When migrating from VS Code `mcp.json` to CLI `mcp-config.json`:

1. Change root key: `"servers"` → `"mcpServers"`
2. Add `"tools"` field to each server (required)
3. Replace `inputs` with `env` and use `${VAR}` syntax
4. Convert `envFile` to explicit `env` entries
5. Ensure `type` is valid for CLI: `"local"`, `"stdio"`, `"http"`, or `"sse"`

## Use Cases

**Personal configuration**: Store in default `~/.copilot/mcp-config.json`

**Project-specific configuration**: Use `XDG_CONFIG_HOME` to point to repository `.copilot/` directory

**Team standardization**: Commit `.copilot/mcp-config.json` to repository and configure XDG_CONFIG_HOME in DevContainers

**Multiple environments**: Use different `XDG_CONFIG_HOME` values for different projects

## References

- [GitHub Docs: Extending Copilot coding agent with MCP](https://docs.github.com/copilot/how-tos/agents/copilot-coding-agent/extending-copilot-coding-agent-with-mcp)
- [GitHub Docs: Using Copilot CLI](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/use-copilot-cli)
- [Original article by Mikoshiba Kyu](https://dev.to/mikoshiba-kyu/managing-github-copilot-cli-mcp-server-configuration-in-your-repository-58i6)
