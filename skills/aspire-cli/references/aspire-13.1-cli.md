# Aspire 13.1 CLI changes and notes

Sources:
- https://aspire.dev/reference/cli/overview/
- https://aspire.dev/reference/cli/commands/
- https://aspire.dev/whats-new/aspire-13-1/

## Channel selection and persistence

- Use `--channel` with `aspire new` or `aspire init` when selecting preview or stable builds.
- When you run `aspire update --self` and select a channel, your selection is saved to `~/.aspire/globalsettings.json`.
- The saved channel becomes the default for future `aspire new` and `aspire init` commands.

## AppHost detection

- AppHost discovery prioritizes explicit `--project`, then `.aspire/settings.json` `appHostPath`, then scans current directory and subdirectories.
- When multiple AppHosts exist, run commands from the intended AppHost folder or pass `--project` to disambiguate.
- **New in 13.1**: Running `aspire run` when an instance is already running now automatically terminates the previous instance.

## Execution flags

- `-d`, `--debug` and `--wait-for-debugger` are available on `aspire run`, `aspire exec`, and `aspire do` for troubleshooting.

## Exec command feature gate

- `aspire exec` is disabled by default; enable via `aspire config set features.execCommandEnabled true`.

## MCP for AI coding agents

Aspire 13.1 introduces comprehensive MCP support via `aspire mcp init`:

- Detects your development environment
- Configures MCP servers for VS Code, GitHub Copilot CLI, Claude Code, or Open Code
- Optionally creates an agent instructions file (AGENTS.md)
- Optionally configures Playwright MCP server
- MCP tools available to AI agents: `list_integrations`, `get_integration_docs`, `list_apphosts`, `select_apphost`

## Installation options

- **New in 13.1**: Installation scripts support `--skip-path` to install without modifying PATH:
  ```bash
  curl -fsSL https://aspire.dev/install.sh | bash -s -- --skip-path
  ```

## Breaking changes in 13.1

### Azure Managed Redis
- `AddAzureRedisEnterprise` renamed to `AddAzureManagedRedis`
- `AddAzureRedis` is now obsolete; migrate to `AddAzureManagedRedis`

### Connection Properties rename
Some connection properties were renamed for consistency:
| Resource         | Old      | New          |
| ---------------- | -------- | ------------ |
| GitHub Models    | Model    | ModelName    |
| OpenAI model     | Model    | ModelName    |
| Milvus database  | Database | DatabaseName |
| MongoDB database | Database | DatabaseName |
| MySQL database   | Database | DatabaseName |
| Oracle database  | Database | DatabaseName |

Environment variables change accordingly (e.g., `CHAT_MODEL` becomes `CHAT_MODELNAME`).

## Upgrade path from 13.0 to 13.1

1. Update the CLI: `aspire update --self`
2. Update your projects: `aspire update` in your project directory
3. Rename Azure Redis: Replace `AddAzureRedisEnterprise` with `AddAzureManagedRedis`
4. Review MCP configuration: Run `aspire mcp init` to set up AI coding agent support
