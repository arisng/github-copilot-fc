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

## Incremental adoption workflow (adding Aspire to existing apps or Aspirify an existing app)

Use this 5-step pattern when helping users adopt Aspire in existing applications:

1. **Initialize Aspire support** → `aspire init`
   - Interactive mode by default
   - Analyzes solution structure and suggests projects to add
   - Creates `{SolutionName}.AppHost/` project with `AppHost.cs`
   - May offer to add ServiceDefaults project

2. **Add applications to AppHost** → Edit `AppHost.cs`
   - Use `AddProject<Projects.ProjectName>("resource-name")`
   - Chain `.WithHttpHealthCheck("/health")` for health monitoring
   - Chain `.WithReference(dependency)` for service-to-service communication
   - Chain `.WaitFor(dependency)` for startup ordering

3. **Configure telemetry** (optional) → `dotnet new aspire-servicedefaults`
   - Creates ServiceDefaults project for observability, resilience, health checks
   - Reference from service projects
   - Add `builder.AddServiceDefaults()` and `app.MapDefaultEndpoints()` in Program.cs

4. **Add integrations** (optional) → `aspire add <package-id>`
   - Adds hosting packages (Redis, PostgreSQL, etc.)
   - Configure in AppHost with `.WithReference(integration)`

5. **Run and verify** → `aspire run`
   - Builds AppHost/resources, starts dashboard
   - Dashboard URL appears in terminal output
   - Verify resources, logs, traces in dashboard

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

### When to use Aspire testing vs alternatives

Use **Aspire testing** (via `DistributedApplicationTestingBuilder`) when you want to:
- Verify end-to-end functionality of your distributed application
- Ensure interactions between multiple services and resources behave correctly in realistic conditions
- Confirm data persistence and integration with real external dependencies (PostgreSQL, Redis, etc.)

Use **`WebApplicationFactory<T>`** instead when you want to:
- Test a single project in isolation
- Run components in-memory
- Mock external dependencies

### Aspire testing characteristics

- **Closed-box**: Tests run as separate processes — no direct access to DI services from test code.
- **Influence via config**: Use env vars or config settings to affect behavior; internal state is encapsulated.
- **Real dependencies**: Tests use actual resources (databases, caches) orchestrated by the AppHost.

### Testing builder configuration patterns

Default test setup (dashboard disabled, ports randomized):

```csharp
var builder = await DistributedApplicationTestingBuilder
    .CreateAsync<Projects.MyAppHost>();
```

Enable dashboard for debugging tests:

```csharp
var builder = await DistributedApplicationTestingBuilder
    .CreateAsync<Projects.MyAppHost>(
        args: [],
        configureBuilder: (appOptions, hostSettings) =>
        {
            appOptions.DisableDashboard = false;
        });
```

Disable port randomization for stable endpoints:

```csharp
var builder = await DistributedApplicationTestingBuilder
    .CreateAsync<Projects.MyAppHost>(
        ["DcpPublisher:RandomizePorts=false"]);
```

Combined configuration (dashboard enabled + stable ports):

```csharp
var builder = await DistributedApplicationTestingBuilder
    .CreateAsync<Projects.MyAppHost>(
        ["DcpPublisher:RandomizePorts=false"],
        (appOptions, _) => { appOptions.DisableDashboard = false; });
```

### CLI-based E2E testing workflows

- Orchestrate dependencies before tests: run `aspire run` to start services, then call `list_resources` via MCP to get live endpoint URLs.
- **Port discovery**: use `list_resources` MCP tool — it returns full endpoint URLs with ports; never hardcode ports (randomized by default).
- Run setup steps as isolated pipeline steps (migrations, seeding, data reset): `aspire do <step>`.
- Execute tooling inside a resource context to inherit connection strings and env vars: `aspire exec --resource <name> -- <command>`.
- Keep the AppHost folder as the working directory to ensure the right resource graph is used.
- Stop the orchestration when tests finish to avoid orphaned resources.
- **For AI-driven ad-hoc testing**: combine `aspire run` + MCP resource/log tools + playwright-cli for browser automation. See [playwright-cli E2E testing](#playwright-cli-e2e-testing-browser-automation) for the full workflow.

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

## Code patterns for existing app adoption

### AppHost.cs patterns

Basic project registration with health checks and external endpoints:

```csharp
var builder = DistributedApplication.CreateBuilder(args);

var api = builder.AddProject<Projects.MyApi>("api")
    .WithHttpHealthCheck("/health");

var web = builder.AddProject<Projects.MyWeb>("web")
    .WithExternalHttpEndpoints()
    .WithReference(api)
    .WaitFor(api);

builder.Build().Run();
```

Adding Redis and sharing across services:

```csharp
var builder = DistributedApplication.CreateBuilder(args);

var cache = builder.AddRedis("cache");

var api = builder.AddProject<Projects.MyApi>("api")
    .WithReference(cache)
    .WithHttpHealthCheck("/health");

builder.Build().Run();
```

### ServiceDefaults configuration

Add to service project's `Program.cs`:

```csharp
var builder = WebApplication.CreateBuilder(args);

// Add Aspire ServiceDefaults for observability and resilience
builder.AddServiceDefaults();

// ... existing service configuration ...

var app = builder.Build();

// Map Aspire ServiceDefaults endpoints
app.MapDefaultEndpoints();

// ... existing middleware ...

app.Run();
```

Install ServiceDefaults project:

```bash
dotnet new aspire-servicedefaults -n MyProject.ServiceDefaults
dotnet sln add MyProject.ServiceDefaults
dotnet add MyProject reference MyProject.ServiceDefaults
```

### Polyglot orchestration

Aspire supports C#, Python, and JavaScript in the same AppHost via `AddPythonApp`, `AddNodeApp`, and `AddProject`. Aspire automatically injects environment variables (e.g., `CACHE_HOST`, `CACHE_PORT`) for each language when references are configured.

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

## Aspire 13.1 new features

### MCP for AI coding agents

Aspire 13.1 introduces first-class MCP support for AI coding agents via two commands:

```bash
# Configure MCP for your IDE/AI tool (one-time per project)
aspire mcp init

# Start the MCP server (stdio transport — IDE auto-starts this)
aspire mcp start
```

`aspire mcp init` detects your environment and writes config for VS Code, GitHub Copilot CLI, Claude Code, or Open Code. It optionally creates `AGENTS.md` and configures Playwright MCP.

`aspire mcp start` exposes a **12-tool MCP server** via stdio that lets AI agents manage a running AppHost: discover resources, read console logs, query structured logs and traces, and execute resource commands. See the [AI-native resource management](#ai-native-resource-management-mcp-first) section and [MCP server reference](references/mcp-server-and-resource-access.md) for the full tool catalog.

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

## AI-native resource management (MCP-first)

Aspire 13.1 ships a built-in MCP server that lets AI coding agents interact with a running AppHost via structured tools — no dashboard scraping or terminal parsing required.

### One-time MCP setup

```bash
# Run once per project to configure your AI tool (VS Code, Copilot CLI, Claude Code, Open Code)
aspire mcp init
```

This writes the appropriate config file (`.vscode/mcp.json`, `~/.copilot/mcp-config.json`, or `.mcp.json`) pointing your IDE's MCP client to `aspire mcp start`. The IDE auto-starts the stdio server as needed.

> `aspire mcp start` is started **separately from** `aspire run` — it acts as a stdio proxy to the dashboard's internal HTTP MCP endpoint.
> Tools like `list_integrations` and `doctor` work without an AppHost. Resource tools (`list_resources`, `list_console_logs`, etc.) require an AppHost to be running.

### AI resource management workflow

> MCP tools below are called by the AI agent through its MCP client — they are **not** shell commands.

```
1. [shell]  aspire run               → starts AppHost; prints dashboard URL + log file path
2. [MCP]    list_resources           → all resources: names, types, states, endpoint URLs+ports, health, env vars
3. [MCP]    list_console_logs "api" → stdout/stderr log output for the named resource
4. [MCP]    list_structured_logs     → OTLP JSON logs (per-resource or all)
5. [MCP]    list_traces              → distributed traces: IDs, resources, duration, error status
6. [MCP]    execute_resource_command "api" "restart" → restart/stop/start a resource
```

### MCP tool quick reference

| Tool | Key parameters | What it returns |
|---|---|---|
| `list_resources` | — | All resources: names, types, states, **full endpoint URLs+ports**, health, env vars, commands |
| `list_console_logs` | `resourceName` | stdout+stderr plaintext for a named resource |
| `list_structured_logs` | `resourceName` (optional) | OTLP structured logs in JSON (single resource or all) |
| `list_traces` | — | Distributed traces: IDs, resources, durations, errors |
| `list_trace_structured_logs` | `traceId` | Logs scoped to a specific trace |
| `execute_resource_command` | `resourceName`, `commandName` | Run start/stop/restart or custom command |
| `list_apphosts` | — | All active AppHosts (multi-instance mode) |
| `select_apphost` | apphost ID | Switch the active AppHost target |
| `list_integrations` | — | Available Aspire NuGet integrations |
| `get_integration_docs` | `integrationName` | Docs for a specific integration |
| `doctor` | — | Environment/prerequisites check |
| `refresh_tools` | — | Reload tools after AppHost change |

See [MCP server and resource access](references/mcp-server-and-resource-access.md) for full architecture detail and JSON response shapes.

### Port discovery

Always call `list_resources` after `aspire run` — ports are randomized per session by default (unless `DcpPublisher:RandomizePorts=false`).

```
[MCP] list_resources
# Returns resources array; each resource has an endpoints array with full URLs:
# { "name": "api", "endpoints": [{ "name": "http", "url": "http://localhost:5234" }] }
```

**Multi-AppHost**: If multiple AppHosts are running (e.g., worktrees), call `list_apphosts` first to see what's available, then `select_apphost <id>` to target the right one before calling resource tools.

### Resource console logs

```
list_console_logs "api"      → plaintext stdout/stderr for the "api" resource
list_console_logs "postgres" → container logs for the "postgres" resource
list_structured_logs "api"   → OTLP JSON logs (traceId, spanId, severity, message)
```

> **Important**: `aspire exec --resource <name> -- <command>` does NOT read running logs. Use `list_console_logs` or `list_structured_logs` via MCP instead.

---

## playwright-cli E2E testing (browser automation)

Combine Aspire MCP + playwright-cli for full-stack ad-hoc E2E testing. AI agents can drive complete human-like browser workflows without any test harness setup.

### Full-stack E2E workflow (AI agent pattern)

MCP tool calls (`[MCP]`) and shell commands (`[shell]`) are shown together to illustrate the combined workflow. The AI coding assistant invokes MCP tools through its MCP client; shell commands run in the terminal.

```bash
# Step 1 — Start Aspire [shell]
aspire run
# Prints: Dashboard: https://localhost:17213/login?t=<token>
# Ports are randomized — do NOT hardcode them; use list_resources

# Step 2 — Discover endpoints [MCP]
list_resources
# Response: "web" endpoint → http://localhost:5173
#           "api" endpoint → http://localhost:5234

# Step 3 — Browser automation [shell]
playwright-cli open http://localhost:5173
playwright-cli snapshot                      # inspect page structure + element refs
playwright-cli fill e3 "test@example.com"   # fill form field
playwright-cli fill e4 "password123"
playwright-cli click e5                      # submit
playwright-cli snapshot                      # verify post-action state
playwright-cli screenshot                    # capture evidence

# Step 4 — Validate backend effects [MCP]
list_console_logs "api"                      # stdout/stderr for the API resource
list_structured_logs "api"                   # OTLP JSON logs
list_traces                                  # trace the full request chain
```

### Session-based testing (maintain browser state)

```bash
playwright-cli --session=e2e open http://localhost:5173
playwright-cli --session=e2e fill e1 "user@example.com"
playwright-cli --session=e2e click e2
# Session persists cookies/auth across commands
playwright-cli session-stop e2e
```

### Essential playwright-cli commands for ad-hoc testing

```bash
playwright-cli snapshot                  # Get accessible element refs (e1, e5…)
playwright-cli fill e3 "text"           # Fill input/textarea
playwright-cli click e5                 # Click element
playwright-cli screenshot               # Capture current page state
playwright-cli screenshot e5            # Capture a specific element
playwright-cli console                  # Browser JS console logs
playwright-cli network                  # Network request log
playwright-cli eval "document.title"   # Evaluate JavaScript
playwright-cli video-start              # Start recording test session
playwright-cli video-stop video.webm    # Stop and save recording
```

> Load the `playwright-cli` skill for the full command reference and multi-tab workflows.

### Decision: Aspire MCP vs DistributedApplicationTestingBuilder

| Goal | Recommended approach |
|---|---|
| Ad-hoc/exploratory testing, AI-driven | `aspire run` + MCP + playwright-cli |
| Automated regression tests in CI | `DistributedApplicationTestingBuilder` + xUnit/NUnit |
| UI-only interaction testing | playwright-cli (no Aspire required) |
| Service integration (API + database) | `DistributedApplicationTestingBuilder` |
| Full-stack coverage (UI + backend) | Both, combined (see [aspire-vs-playwright-testing.md](references/aspire-vs-playwright-testing.md)) |

---

## Reference files

- Use [CLI commands overview](references/cli-commands.md) for command selection, brief descriptions, and examples.
- Use [Aspire 13.1 CLI changes](references/aspire-13.1-cli.md) for channel persistence, instance detection, and installation options.
- Use [HTTPS certificate management](references/https-cert-management.md) for manual trust commands, platform notes, and CI/CD patterns when auto-trust fails.
- Use [Debugging + E2E testing notes](references/debugging-e2e-testing.md) for research-backed guidance on diagnosing issues and orchestrating tests.
- Use [Aspire Testing vs Playwright-CLI](references/aspire-vs-playwright-testing.md) for comparative analysis when choosing testing tools or combining them for full-stack testing.
- Use [MCP server and resource access](references/mcp-server-and-resource-access.md) for the full 12-tool MCP catalog, two-layer architecture detail (stdio proxy + dashboard HTTP), JSON response shapes, port discovery, and console log access patterns. Load this when the user asks about resource discovery, reading logs, or using Aspire with AI agents.
- Use [Aspire isolation for parallel worktrees](references/aspire-isolation.md) for comprehensive guidance on running multiple AppHost instances simultaneously: port allocation scripts, MCP proxy architecture, GitFolderResolver pattern, distributed testing, and complete troubleshooting workflows. Essential for git worktrees and multi-agent AI development.
