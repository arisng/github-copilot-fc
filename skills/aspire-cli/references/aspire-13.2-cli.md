# Aspire 13.2 CLI notes

Sources:
- https://aspire.dev/reference/cli/overview/
- https://aspire.dev/reference/cli/commands/aspire-agent/
- https://aspire.dev/reference/cli/commands/aspire-agent-init/
- https://aspire.dev/reference/cli/commands/aspire-run/
- https://aspire.dev/reference/cli/commands/aspire-start/
- https://aspire.dev/whats-new/aspire-13-2/
- https://aspire.dev/get-started/ai-coding-agents/

## Big shifts in 13.2

- `aspire mcp ...` was renamed to `aspire agent ...`.
- `aspire agent init` now sets up coding-agent integrations and installs Aspire skill files.
- `aspire start` is the background-friendly shortcut for detached AppHost startup.
- `aspire run --isolated` and `aspire start --isolated` are first-class solutions for parallel worktrees and agents.
- `aspire describe`, `aspire logs`, `aspire wait`, `aspire resource`, `aspire doctor`, `aspire docs`, `aspire restore`, `aspire export`, `aspire secret`, and `aspire certs` expand the CLI far beyond the older 13.1 surface.

## Renames and migration notes

| Older guidance | Current 13.2 guidance |
| --- | --- |
| `aspire mcp init` | `aspire agent init` |
| `aspire mcp start` | `aspire agent mcp` |
| `aspire run --detach` as the main detached story | `aspire start` is the clearer detached-first command |
| `.aspire\settings.json` as primary config | rooted `aspire.config.json` is preferred; legacy files are migrated |
| `AGENTS.md` setup | skill-file setup via `aspire agent init` |

## Rooted AppHost discovery

13.2 prefers rooted `aspire.config.json` for AppHost discovery and persisted CLI metadata. Legacy `.aspire\settings.json` and `apphost.run.json` files are still read during migration.

AppHost targeting order is:

1. explicit `--apphost`
2. rooted `aspire.config.json`
3. directory scanning

## Agent-friendly behaviors

- Use `--format Json` when another tool or agent needs structured output.
- Use `--non-interactive` to suppress prompts and spinners in automation.
- Use `aspire doctor` early when setup issues could be certificate, SDK, or container-runtime related.
- Use `aspire start --isolated` for delegated sessions, worktrees, and parallel agents.
- Use `aspire describe`, `aspire logs`, `aspire otel`, and `aspire wait` instead of asking the user to manually inspect the dashboard first.

## Upgrade checklist

1. Update the CLI: `aspire update --self`
2. Update the project packages: `aspire update`
3. Re-run agent setup if needed: `aspire agent init`
4. Replace old `aspire mcp ...` guidance in docs, scripts, or prompts
5. Prefer `aspire start` or `aspire run --isolated` where older guidance used custom detached or multi-worktree scripts
