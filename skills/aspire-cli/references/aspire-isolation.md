# Aspire isolated mode for parallel AppHosts

Sources:
- https://devblogs.microsoft.com/aspire/aspire-isolated-mode-parallel-development/
- https://aspire.dev/reference/cli/commands/aspire-run/
- https://aspire.dev/reference/cli/commands/aspire-start/
- https://aspire.dev/whats-new/aspire-13-2/

## Default recommendation

For parallel development in Aspire 13.2+, use isolated mode first:

```bash
aspire run --isolated
```

or:

```bash
aspire start --isolated --format Json
```

This is now the native solution for git worktrees, multiple checkouts, background agents, side-by-side comparison runs, and live integration testing against more than one copy of the same AppHost.

## What isolated mode does

`--isolated` gives each run:

- randomized ports
- isolated user secrets
- separate runtime configuration for that instance

This removes the two biggest multi-instance problems:

1. port collisions
2. cross-instance config leakage

Aspire service discovery and the dashboard adjust automatically, so isolated mode does not require AppHost code changes just to support parallel runs.

## When to use it

Use `--isolated` when:

- multiple worktrees or checkouts may run the same AppHost
- a background agent may start the same AppHost you are already running
- you want side-by-side comparison of different branches or fixes
- automated or exploratory tests need their own live AppHost
- parallel local development would otherwise fight over shared ports or secrets

## When normal mode is still fine

Use normal `aspire run` or `aspire start` when:

- only one AppHost instance is running
- predictable ports are useful for your local workflow
- the environment is already isolated enough that host port collisions are not a concern

## Quick workflows

### Worktree or background-agent workflow

```bash
aspire start --isolated --format Json
aspire wait web --status healthy
aspire describe --format Json
aspire logs web --tail 100
```

### Cleanup

```bash
aspire ps
aspire stop --all
```

## Advanced fallback patterns

The older script-and-proxy approach is now fallback guidance, not the default.

Consider custom scripts, stable port allocation, or proxy layers only when you specifically need:

- fixed ports for external tools that cannot follow dynamic discovery
- fixed MCP client wiring across dynamic instances
- repo-specific lifecycle automation or cleanup behavior
- support for older Aspire CLI versions that do not have native isolated mode

If you do not need one of those constraints, prefer isolated mode over manual port or environment variable management.

## Troubleshooting

### Parallel run fails with port conflicts

Retry with `--isolated` first. Do not start by manually juggling environment variables.

### I need stable ports for one local workflow

Use normal `aspire run` or `aspire start`, or adopt a repo-specific script only for that fixed-port scenario.

### I am not sure which AppHost instance is running

Use `aspire ps` to list running AppHosts, then `aspire stop` or `aspire stop --all` to clean up detached instances.

### Secrets or configuration appear to leak between runs

Confirm the affected runs were started with `--isolated`. Mixed isolated and non-isolated runs can still produce confusing local state.

**Causes:**
- Orphaned processes from previous runs
- Manual `dotnet run` bypassing scripts

**Solution:**
```powershell
.\scripts\kill-apphost.ps1 -All
```

Re-run using the script.

### MCP proxy connection fails

**Symptom:** AI agent can't connect to Aspire MCP.

**Checks:**
1. Verify AppHost is running: check dashboard URL
2. Confirm `settings.json` exists and has correct port
3. Check environment variables if using overrides
4. Review proxy stderr output for connection errors

**Test proxy manually:**
```powershell
dotnet run scripts/aspire-mcp-proxy.cs
```

Look for connection success/failure messages.

### Worktree detection not working

**Symptom:** Dashboard name doesn't include worktree name.

**Solution:**
- Verify `GitFolderResolver` implementation
- Check that `.git` is a file (worktree indicator), not a directory
- Test worktree path parsing in isolation

### Resource-dependent commands fail

**Symptom:** `aspire exec` or `aspire do` commands fail.

**Solution:**
- Verify AppHost builds successfully
- Check resources exist in Program.cs
- Ensure current directory is AppHost folder or parent
- For multiple AppHosts, confirm you're in the correct folder

## Best Practices

### Port Management

- **Always use scripts** – Never run `dotnet run` directly for parallel workflows
- **Prefer portless endpoints** – Use `WithHttpEndpoint(name: "http")` without explicit ports
- **Random allocation** – Let Aspire allocate ports dynamically
- **Script-driven discovery** – Store allocated ports in `settings.json` for tooling

### Dashboard Naming

- **Worktree detection** – Implement `GitFolderResolver` for automatic naming
- **Clear labels** – Use format like `AppName-worktree-name`
- **Visual distinction** – Makes parallel instances easily identifiable

### MCP Integration

- **Proxy for flexibility** – Use MCP proxy when supporting multiple instances
- **Fixed client config** – AI agent configuration never changes
- **Dynamic discovery** – Proxy reads `settings.json` on every request
- **Graceful degradation** – Cache tools for offline mode

### Cleanup Discipline

- **Regular cleanup** – Use `kill-apphost -All` between work sessions
- **Process tracking** – Scripts output process IDs for selective cleanup
- **Automated shutdown** – Consider cleanup hooks in development workflows

### Testing Integration

- **Prefer DistributedApplicationTestingBuilder** – Built-in isolation and port randomization
- **E2E with Playwright** – Full-stack validation without manual setup
- **Agent autonomy** – Enable AI agents to test their own changes
- **Resource health checks** – Use `WaitForResourceHealthyAsync` before tests

## Reference Implementation

For a complete working example, see: [worktrees-example repository](https://github.com/tamirdresher/worktrees-example)

Includes:
- NoteTaker sample application
- start-apphost.ps1/sh scripts
- kill-apphost.ps1/sh scripts
- aspire-mcp-proxy.cs implementation
- GitFolderResolver pattern
- Playwright E2E tests with Aspire orchestration

## Future: Native Aspire CLI Support

The isolation pattern demonstrates the need for first-class multi-instance support. A future `aspire run --isolated` command could:

- Automatically detect worktree context
- Allocate unique ports without scripts
- Update MCP proxy configuration
- Manage cleanup on exit

See GitHub issue: [dotnet/aspire#13932](https://github.com/dotnet/aspire/issues/13932)
