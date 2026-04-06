---
name: aspire-cli
description: Guidance for using the .NET Aspire CLI to create, initialize, run, update, publish, deploy, and manage Aspire AppHost projects. Use when selecting or explaining Aspire CLI commands, flags, or workflows (new/init/run/add/update/publish/deploy/do/exec/config/cache/mcp), or when upgrading to Aspire 13.1 CLI behaviors. Also covers AI-native resource management via the Aspire MCP server (resource discovery, port discovery, console log reading, structured logs, traces, and execute resource commands). Includes combined Aspire + playwright-cli workflows for ad-hoc E2E testing and browser automation—given an Aspire AppHost project, the AI coding assistant can fully orchestrate Aspire resources and drive browser tests like a human.
metadata:
  version: 2.0.0
  author: arisng
---

# Aspire CLI

Use this skill to pick the right Aspire CLI command, outline the workflow, provide MCP-based resource/log/port access for AI agents, and orchestrate combined Aspire + playwright-cli E2E testing.

## Quick workflow

1. Identify the user goal (create, initialize, run, update, publish, deploy, execute step, run resource command, configure CLI, clear cache, **or manage/test resources with AI**).
2. Determine the working directory (solution root vs AppHost folder) and whether an AppHost already exists.
3. Select the matching command from the CLI reference.
4. Call out required context (AppHost location, channel selection, SDK requirements).
5. Provide minimal example commands and flags.
6. Mention any Aspire 13.1 CLI behavior changes that affect the request.
7. **For AI testing goals**: use the [AI-native resource management](#ai-native-resource-management-mcp-first) workflow — MCP for resource/log/port discovery, playwright-cli for browser automation.

## Incremental adoption workflow (adding Aspire to existing apps)

`aspire init` → edit `AppHost.cs` → (optional) ServiceDefaults → (optional) `aspire add` → `aspire run`.

See [App adoption patterns](references/app-adoption.md) for the full 5-step workflow, AppHost.cs patterns (project registration, Redis, PostgreSQL, container registry), ServiceDefaults setup, and polyglot (Python/Node) orchestration.

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
- Start the MCP stdio server → `aspire mcp start` (usually auto-started by the IDE; exposes 12 tools for AI agents)

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

## HTTPS certificate handling

`aspire run` **automatically** trusts local hosting certificates on startup. No manual action is typically required. If you encounter HTTPS errors (browser warnings, `NET::ERR_CERT_AUTHORITY_INVALID`), see [HTTPS certificate management](references/https-cert-management.md) for manual trust commands (`dotnet dev-certs https --trust/--clean`), platform-specific notes, and CI/CD patterns.

## E2E testing facilitation

**Use Aspire testing** (`DistributedApplicationTestingBuilder`) for: full distributed app E2E, service-to-service interactions, real external dependencies (PostgreSQL, Redis).

**Use `WebApplicationFactory<T>`** for: single-project isolation, in-memory mocking.

Default setup: dashboard disabled, ports randomized. Load [Debugging + E2E testing notes](references/debugging-e2e-testing.md) for builder configuration patterns (enable dashboard, disable port randomization, combined config), `DistributedApplicationTestingBuilder` usage, and pipeline behaviors.

### CLI-based E2E workflows

- Orchestrate dependencies before tests: `aspire run` → `list_resources` via MCP to get live endpoint URLs.
- **Port discovery**: use `list_resources` MCP tool — never hardcode ports (randomized by default).
- Run setup steps as isolated pipeline steps: `aspire do <step>`.
- Execute tooling in resource context (inherits env vars/connection strings): `aspire exec --resource <name> -- <command>`.
- **For AI-driven ad-hoc testing**: combine `aspire run` + MCP tools + playwright-cli. See [playwright-cli E2E testing](#playwright-cli-e2e-testing-browser-automation) below.

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
- MCP commands (`aspire mcp init`, `aspire mcp start`) are fully supported and documented; always recommend `aspire mcp init` for AI coding agent setups.
- When users mention Azure Redis, note the breaking change: `AddAzureRedisEnterprise` renamed to `AddAzureManagedRedis` in 13.1.
- Channel selection (`--channel`) persists globally after `aspire update --self` in 13.1.
- **Do not use `aspire exec` to read running logs** — use `list_console_logs` via MCP. `aspire exec` runs a new command in a resource context; it does not stream existing logs.
- **Do not scrape the dashboard URL** for resource discovery — use `list_resources` via MCP which returns structured JSON with full endpoint URLs and ports.
- For AI agent port discovery, always call `list_resources` after `aspire run`; ports are randomized by default.

## Aspire 13.1 highlights

Key changes — load [Aspire 13.1 CLI changes](references/aspire-13.1-cli.md) for full detail, breaking change migration, and connection property renames:

- **MCP for AI agents**: `aspire mcp init` configures VS Code, Copilot CLI, Claude Code, or Open Code; `aspire mcp start` exposes a 12-tool MCP server.
- **Channel persistence**: `aspire update --self` saves channel choice to `~/.aspire/globalsettings.json`.
- **Auto instance detection**: `aspire run` when an instance is already running terminates the previous one automatically.
- **Azure Managed Redis (breaking)**: `AddAzureRedisEnterprise` renamed to `AddAzureManagedRedis`; `AddAzureRedis` is now obsolete.
- **Container registry**: new `AddContainerRegistry` + `aspire do push` pipeline step.
- **Install without PATH modification**: `--skip-path` flag on install scripts.

## AI-native resource management (MCP-first)

Aspire 13.1 ships a built-in MCP stdio server. Run `aspire mcp init` once per project — the IDE auto-starts `aspire mcp start` as needed.

> `aspire mcp start` is a stdio proxy to the dashboard's internal HTTP MCP endpoint.  
> `list_integrations` and `doctor` work without an AppHost; resource tools require an AppHost to be running.

### AI resource management workflow

```
1. [shell]  aspire run               → starts AppHost; prints dashboard URL + log file path
2. [MCP]    list_resources           → resources: names, types, states, full endpoint URLs+ports, health, env vars
3. [MCP]    list_console_logs "api"  → stdout/stderr for the named resource
4. [MCP]    list_structured_logs     → OTLP JSON logs (per-resource or all)
5. [MCP]    list_traces              → distributed traces: IDs, resources, duration, error status
6. [MCP]    execute_resource_command "api" "restart" → restart/stop/start a resource
```

### MCP tool quick reference

| Tool | Key parameters | What it returns |
|---|---|---|
| `list_resources` | — | Resources: names, types, states, **full endpoint URLs+ports**, health, env vars, commands |
| `list_console_logs` | `resourceName` | stdout+stderr for a named resource |
| `list_structured_logs` | `resourceName` (optional) | OTLP logs in JSON |
| `list_traces` | — | Distributed traces: IDs, resources, durations, errors |
| `list_trace_structured_logs` | `traceId` | Logs scoped to a specific trace |
| `execute_resource_command` | `resourceName`, `commandName` | Run start/stop/restart or custom command |
| `list_apphosts` | — | All active AppHosts (multi-instance) |
| `select_apphost` | apphost ID | Switch active AppHost target |
| `list_integrations` | — | Available Aspire NuGet integrations |
| `get_integration_docs` | `integrationName` | Docs for a specific integration |
| `doctor` | — | Environment/prerequisites check |
| `refresh_tools` | — | Reload tools after AppHost change |

**Multi-AppHost**: call `list_apphosts` first, then `select_apphost <id>` before resource tools.

**Port discovery**: always call `list_resources` after `aspire run` — ports are randomized per session by default.

See [MCP server and resource access](references/mcp-server-and-resource-access.md) for full architecture detail, two-layer proxy design, and JSON response shapes.

---

## playwright-cli E2E testing (browser automation)

Combine Aspire MCP + playwright-cli for full-stack ad-hoc E2E testing without any test harness setup.

### Full-stack E2E workflow (AI agent pattern)

```bash
# Step 1 — Start Aspire [shell]
aspire run
# Ports are randomized — do NOT hardcode them; use list_resources

# Step 2 — Discover endpoints [MCP]
list_resources
# Response: "web" endpoint → http://localhost:5173, "api" endpoint → http://localhost:5234

# Step 3 — Browser automation [shell]
playwright-cli open http://localhost:5173
playwright-cli snapshot                      # inspect page structure + element refs
playwright-cli fill e3 "test@example.com"
playwright-cli fill e4 "password123"
playwright-cli click e5                      # submit
playwright-cli snapshot                      # verify post-action state
playwright-cli screenshot                    # capture evidence

# Step 4 — Validate backend effects [MCP]
list_console_logs "api"                      # stdout/stderr for the API resource
list_structured_logs "api"                   # OTLP JSON logs
list_traces                                  # trace the full request chain
```

Load the `playwright-cli` skill for session-based testing, multi-tab workflows, video recording, and the full command reference.

### Decision: Aspire MCP vs DistributedApplicationTestingBuilder

| Goal | Recommended approach |
|---|---|
| Ad-hoc/exploratory testing, AI-driven | `aspire run` + MCP + playwright-cli |
| Automated regression tests in CI | `DistributedApplicationTestingBuilder` + xUnit/NUnit |
| UI-only interaction testing | playwright-cli (no Aspire required) |
| Service integration (API + database) | `DistributedApplicationTestingBuilder` |
| Full-stack coverage (UI + backend) | Both, combined — see [aspire-vs-playwright-testing.md](references/aspire-vs-playwright-testing.md) |

---

## Reference files

- Use [App adoption patterns](references/app-adoption.md) for the incremental adoption workflow, AppHost.cs registration patterns (Redis, PostgreSQL, container registry), ServiceDefaults setup, and polyglot orchestration.
- Use [CLI commands overview](references/cli-commands.md) for command selection, brief descriptions, and examples.
- Use [Aspire 13.1 CLI changes](references/aspire-13.1-cli.md) for channel persistence, instance detection, breaking changes (Azure Managed Redis, connection property renames), and upgrade path.
- Use [HTTPS certificate management](references/https-cert-management.md) for manual trust commands, platform notes, and CI/CD patterns when auto-trust fails.
- Use [Debugging + E2E testing notes](references/debugging-e2e-testing.md) for `DistributedApplicationTestingBuilder` patterns, `aspire run`/`exec`/`do` behaviors, and pipeline debugging.
- Use [Aspire Testing vs Playwright-CLI](references/aspire-vs-playwright-testing.md) for comparative analysis when choosing testing tools or combining them for full-stack testing.
- Use [MCP server and resource access](references/mcp-server-and-resource-access.md) for full 12-tool MCP catalog, two-layer architecture, JSON response shapes, and console log access patterns.
- Use [Aspire isolation for parallel worktrees](references/aspire-isolation.md) for running multiple AppHost instances simultaneously: port allocation scripts, MCP proxy, GitFolderResolver pattern, and troubleshooting.
