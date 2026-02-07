---
name: aspire-cli
description: Guidance for using the .NET Aspire CLI to create, initialize, run, update, publish, deploy, and manage Aspire AppHost projects. Use when selecting or explaining Aspire CLI commands, flags, or workflows (new/init/run/add/update/publish/deploy/do/exec/config/cache/mcp), or when upgrading to Aspire 13.1 CLI behaviors. MCP commands (aspire mcp init) are included when explicitly requested.
metadata:
  version: 1.3.0
  author: arisng
---

# Aspire CLI

Use this skill to pick the right Aspire CLI command, outline the workflow, and provide concise command guidance. Keep answers focused on non-MCP CLI features.

## Quick workflow

1. Identify the user goal (create, initialize, run, update, publish, deploy, execute step, run resource command, configure CLI, clear cache).
2. Determine the working directory (solution root vs AppHost folder) and whether an AppHost already exists.
3. Select the matching command from the CLI reference.
4. Call out required context (AppHost location, channel selection, SDK requirements).
5. Provide minimal example commands and flags.
6. Mention any Aspire 13.1 CLI behavior changes that affect the request.

## Command selection (decision guide)

- New project from templates → `aspire new`
- Add Aspire to existing solution → `aspire init`
- Run dev orchestration and dashboard → `aspire run`
- Add official integration package → `aspire add`
- Update Aspire NuGet packages → `aspire update`
- Update CLI itself → `aspire update --self`
- Publish deployment assets → `aspire publish`
- Deploy serialized assets → `aspire deploy`
- Run a pipeline step only → `aspire do <step>`
- Run a tool inside a resource context → `aspire exec --resource <name> -- <command>`
- Configure CLI settings → `aspire config`
- Clear cache → `aspire cache clear`
- Initialize MCP for AI coding agents → `aspire mcp init` (configures VS Code, GitHub Copilot CLI, Claude Code, Open Code)

## Context checklist

- Confirm .NET SDK 10.0.100+ is installed when using Aspire 13.x CLI.
- Verify current directory contains or is under an AppHost when using `aspire run`, `aspire do`, `aspire exec`, `aspire publish`, or `aspire deploy`.
- When multiple AppHosts exist, tell the user to run commands from the intended AppHost folder.
- If the user mentions “preview/stable” selection, use `--channel` on `aspire new` or `aspire init`, and note channel persistence after `aspire update --self`.
- When running multiple AppHost instances in parallel (worktrees/branches, multi-agent workflows), use isolation patterns from [aspire-isolation.md](references/aspire-isolation.md): management scripts for port allocation, portless endpoints, and worktree-specific dashboard naming.

## Actionable command patterns

- Create a new project (interactive-first): `aspire new`
- Create with a specific template: `aspire new <template>`
- Initialize an existing solution: `aspire init`
- Run the AppHost from a nested folder: `cd <apphost-folder>` then `aspire run`
- Add an integration by known ID: `aspire add <package-id>`
- Update packages in place: `aspire update`
- Update CLI binary: `aspire update --self`
- Publish assets to disk: `aspire publish`
- Deploy using custom annotations: `aspire deploy`
- Run a pipeline step: `aspire do <step>`
- Run EF migrations using resource config: `aspire exec --resource <name> -- dotnet ef migrations add <name>`
- List config: `aspire config list`
- Set config: `aspire config set <key> <value>`
- Clear cache: `aspire cache clear`

## Debugging workflows

- Start the full dev orchestration to reproduce issues: `aspire run` (builds AppHost/resources, starts dashboard, prints endpoints).
- Use the dashboard to inspect resource status, logs, and endpoints before changing code.
- Re-run only the pipeline step tied to a failure: `aspire do <step>`.
- Use `aspire do diagnostics` to list steps, dependencies, and ordering when you need to find the right step to re-run.
- Execute diagnostic tooling inside a resource context (inherits env vars and connection strings): `aspire exec --resource <name> -- <command>`.
- Enable the exec command feature if it is disabled: `aspire config set features.execCommandEnabled true`.
- When multiple AppHosts exist, move into the intended AppHost folder first to ensure the right context.

### Advanced debugging flags (13.x)

- CLI-level debug logging: add `-d` or `--debug` to `aspire run`, `aspire exec`, or `aspire do`.
- Pause for debugger attach: add `--wait-for-debugger` to `aspire run`, `aspire exec`, or `aspire do`.
- If AppHost detection is ambiguous, pass `--project <path-to-apphost.csproj>` to `aspire run`.
- For pipeline step diagnostics, add `--include-exception-details` and `--log-level <level>` to `aspire do` when troubleshooting failures.

## E2E testing facilitation

- Orchestrate dependencies before tests: run `aspire run` to start services, then wait for resources to be healthy in the dashboard.
- Capture endpoints from `aspire run` output or dashboard and pass them to the test runner (keep test config in sync with Aspire-provided URLs).
- Run setup steps as isolated pipeline steps (migrations, seeding, data reset): `aspire do <step>`.
- Execute the test command inside a resource context to inherit connection strings and env vars: `aspire exec --resource <name> -- <command>`.
- Keep the AppHost folder as the working directory to ensure the right resource graph is used.
- Stop the orchestration when tests finish to avoid orphaned resources.
- For Aspire testing (AppHost-driven E2E), remember defaults: dashboard is disabled and ports are randomized; set `DisableDashboard=false` and `DcpPublisher:RandomizePorts=false` when tests require visibility or stable ports.

## Parallel worktrees and isolation

When users need to run multiple AppHost instances simultaneously (git worktrees, parallel AI agent development, multi-feature testing), use the comprehensive isolation guidance in [references/aspire-isolation.md](references/aspire-isolation.md).

**Quick summary:**
- Multiple instances cause port conflicts by default (dashboard, OTLP, resource service, MCP all share ports)
- Solution: management scripts (start-apphost/kill-apphost) that auto-allocate ports and update settings
- Use `GitFolderResolver` pattern for worktree-specific dashboard naming
- Keep endpoints portless (`WithHttpEndpoint(name: "http")`) for random allocation
- Optional MCP proxy layer provides fixed AI agent configuration with dynamic port discovery

**When to use:**
- User mentions "parallel worktrees", "multiple instances", "concurrent development"
- AI agents need to test in isolated environments
- Multi-worktree git workflows with Aspire orchestration
- Avoiding port conflicts in development

**Progressive guidance:**
1. First, explain the port conflict problem
2. Reference [aspire-isolation.md](references/aspire-isolation.md) for implementation patterns
3. Discuss MCP proxy architecture only if AI agent integration is mentioned
4. Highlight distributed testing as alternative for test-focused isolation

## Troubleshooting guidance

- `aspire run` fails to find AppHost → move to the AppHost directory or a parent folder and retry.
- Resource-dependent commands fail → verify the AppHost builds and resources exist, then re-run.
- Weird template or package behavior → clear cache with `aspire cache clear` and retry `aspire new` or `aspire update`.
- Upgrading issues → run `aspire update --self` first, then `aspire update` in the project.

## Guardrails

- Prefer interactive-first `aspire new` and `aspire init` guidance unless automation is requested.
- Require .NET SDK 10.0.100+ for Aspire 13.x CLI usage.
- MCP commands (`aspire mcp init`) are now included when explicitly requested; the skill description has been updated to reflect this.
- When users mention Azure Redis, note the breaking change: `AddAzureRedisEnterprise` renamed to `AddAzureManagedRedis` in 13.1.
- Channel selection (`--channel`) persists globally after `aspire update --self` in 13.1.

## Aspire 13.1 new features

### MCP for AI coding agents

Aspire 13.1 introduces `aspire mcp init` for configuring AI coding agents:

```bash
aspire mcp init
```

This command:
- Detects your development environment
- Configures MCP servers for VS Code, GitHub Copilot CLI, Claude Code, or Open Code
- Optionally creates an agent instructions file (AGENTS.md)
- Optionally configures Playwright MCP server

### CLI enhancements

- **Channel persistence**: When you run `aspire update --self` and select a channel, your selection is saved to `~/.aspire/globalsettings.json` and becomes the default for future `aspire new` and `aspire init` commands.
- **Automatic instance detection**: Running `aspire run` when an instance is already running now automatically terminates the previous instance.
- **Installation path option**: Install scripts support `--skip-path` to install without modifying PATH.

### Azure Managed Redis (breaking change)

`AddAzureRedisEnterprise` has been renamed to `AddAzureManagedRedis`:

```csharp
// Before (Aspire 13.0)
var redis = builder.AddAzureRedisEnterprise("cache");

// After (Aspire 13.1)
var redis = builder.AddAzureManagedRedis("cache");
```

`AddAzureRedis` is now obsolete. Migrate to `AddAzureManagedRedis` for new projects.

### Container registry resource

New `ContainerRegistryResource` for general-purpose container registries:

```csharp
var registry = builder.AddContainerRegistry("myregistry", "registry.example.com");
var api = builder.AddProject<Projects.Api>("api")
    .WithContainerRegistry(registry);
```

The deployment pipeline now includes a `push` step: `aspire do push`.

## Reference files

- Use [CLI commands overview](references/cli-commands.md) for command selection, brief descriptions, and examples.
- Use [Aspire 13.1 CLI changes](references/aspire-13.1-cli.md) for channel persistence, instance detection, and installation options.
- Use [Debugging + E2E testing notes](references/debugging-e2e-testing.md) for research-backed guidance on diagnosing issues and orchestrating tests.
- Use [Aspire isolation for parallel worktrees](references/aspire-isolation.md) for comprehensive guidance on running multiple AppHost instances simultaneously: port allocation scripts, MCP proxy architecture, GitFolderResolver pattern, distributed testing, and complete troubleshooting workflows. Essential for git worktrees and multi-agent AI development.
