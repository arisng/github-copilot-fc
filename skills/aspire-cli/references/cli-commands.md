# Aspire CLI commands overview (13.2)

Sources:
- https://aspire.dev/reference/cli/overview/
- https://aspire.dev/reference/cli/commands/aspire-run/
- https://aspire.dev/reference/cli/commands/aspire-start/
- https://aspire.dev/reference/cli/commands/aspire-agent/
- https://aspire.dev/reference/cli/commands/aspire-agent-init/
- https://aspire.dev/reference/cli/commands/aspire-describe/
- https://aspire.dev/reference/cli/commands/aspire-logs/
- https://aspire.dev/reference/cli/commands/aspire-wait/
- https://aspire.dev/reference/cli/commands/aspire-resource/
- https://aspire.dev/reference/cli/commands/aspire-doctor/
- https://aspire.dev/reference/cli/commands/aspire-docs/
- https://aspire.dev/reference/cli/commands/aspire-docs-list/
- https://aspire.dev/reference/cli/commands/aspire-docs-search/
- https://aspire.dev/reference/cli/commands/aspire-docs-get/

## Core lifecycle

| Scenario | Command | Notes |
| --- | --- | --- |
| Create a new Aspire solution | `aspire new` | Interactive-first template picker |
| Add Aspire to an existing repo | `aspire init` | Adds an AppHost or single-file AppHost |
| Restore AppHost dependencies | `aspire restore` | Useful in CI and after TypeScript AppHost changes |
| Run in foreground | `aspire run` | Attached session; prints dashboard URL and log file path |
| Run in background | `aspire start` | Detached-friendly shorthand for background startup |
| List or stop running AppHosts | `aspire ps`, `aspire stop` | Use `--all` on `stop` to clean up multiple runs |
| Run multiple instances safely | `aspire run --isolated` or `aspire start --isolated` | Randomized ports plus isolated user secrets |
| Wait for readiness | `aspire wait <resource>` | Defaults to `healthy`; useful in automation |
| Inspect resources and endpoints | `aspire describe` | Use `--follow` or `--format Json` for automation |
| Read console logs | `aspire logs [resource]` | Supports `--follow`, `--tail`, and `--format Json` |
| Inspect telemetry | `aspire otel` | CLI-first access to structured logs and traces |
| Manage one resource | `aspire resource <resource> <command>` | Built-ins include `start`, `stop`, and `restart` |

## Agent and automation workflows

| Scenario | Command | Notes |
| --- | --- | --- |
| Configure agent integrations | `aspire agent init` | Sets up skill/MCP configuration for supported coding agents |
| Start the Aspire MCP server | `aspire agent mcp` | Manual MCP server entry point when needed |
| Validate local environment | `aspire doctor` | Check SDK, certs, container runtime, and related prerequisites |
| Browse docs from the terminal | `aspire docs list` | Use when the right page or slug is not obvious yet |
| Search docs from the terminal | `aspire docs search "redis"` | Search returns slugs you can pass to `docs get`; use `--limit` to keep results tight |
| Read a doc page or section | `aspire docs get redis-integration --section "Add Redis resource"` | Use `--format Json` for automation or downstream tools |
| Discover integrations after confirming the docs pattern | `aspire add <name-or-id>` | Fuzzy search works well in 13.2 |
| Update project packages | `aspire update` | Updates Aspire packages in the project |
| Update the CLI itself | `aspire update --self` | Use before adopting new command surface or docs |

## Advanced or conditional commands

- `aspire do <step>` runs one pipeline step and its dependencies.
- `aspire exec --resource <name> -- <command>` runs a new command inside a resource context; it is feature-gated and not a log reader.
- `aspire publish`, `aspire deploy`, and `aspire export` cover publish, deploy, and diagnostics packaging workflows.
- `aspire secret`, `aspire certs`, `aspire config`, and `aspire cache clear` manage secrets, certs, config, and cache.

## Agent-friendly flags

- `--format Json` for machine-readable output.
- `--non-interactive` to disable prompts and spinners.
- `--apphost <path>` to disambiguate the target AppHost.
- `--isolated` for parallel worktrees, agents, or comparison runs.
- `--no-build` when artifacts are already up to date.
- `--` to pass arguments through to the AppHost.

## Notes

- Prefer `aspire run` for an attached local loop and `aspire start` for background or delegated sessions.
- Prefer `aspire describe` or MCP `list_resources` for endpoint discovery; do not hardcode ports.
- Use `aspire docs list` when the right page or slug is unclear, `aspire docs search` to get ranked results and slugs, and `aspire docs get` to read the full page or one section.
- For unfamiliar integrations, custom commands, or AppHost APIs, use docs lookup before `aspire add` or AppHost edits.
- 13.2 renamed `aspire mcp ...` to `aspire agent ...`; older posts or references may still use the former names.
- Aspire now prefers rooted `aspire.config.json`; older `.aspire\settings.json` files are read during migration.
