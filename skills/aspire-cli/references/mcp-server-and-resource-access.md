# Aspire MCP server and resource access (13.x)

Sources:
- https://aspire.dev/reference/cli/commands/aspire-mcp/
- https://aspire.dev/reference/cli/commands/aspire-mcp-init/
- https://aspire.dev/reference/cli/commands/aspire-mcp-start/
- https://aspire.dev/reference/cli/commands/aspire-run/
- https://aspire.dev/reference/cli/commands/aspire-exec/
- https://aspire.dev/dashboard/explore/
- https://aspire.dev/testing/write-your-first-test/
- https://aspire.dev/testing/accessing-resources/
- https://learn.microsoft.com/dotnet/api/aspire.hosting.testing
- DeepWiki: dotnet/aspire (verified March 2026)

---

## 1. `aspire run` terminal output format

The `aspire run` command prints the following to stdout after startup:

```
aspire run
🔍 Finding apphosts...
apphost.cs
🗄 Created settings file at '.aspire/settings.json'.
AppHost: apphost.cs
Dashboard: https://localhost:17213/login?t=2b4a2ebc362b7fef9b5ccf73e702647b
 Logs: $HOME/.aspire/cli/logs/apphost-27732-2025-10-31-19-21-27.log
 Press CTRL+C to stop the apphost and exit.
```

Key facts:
- **Dashboard URL** with auth token (`?t=<token>`) is printed on startup.
- **Log file path** for the AppHost process is printed.
- **No structured resource list** is printed to the terminal — resources, endpoint URLs, and ports are discovered via the Dashboard UI or MCP tools.
- The dashboard token is a browser persistent cookie valid for 3 days.
- To avoid the interactive login, AI agents should use the MCP server (not scrape the terminal).

---

## 2. Aspire MCP server architecture

There are **two distinct MCP server layers**:

### Layer 1: `aspire mcp start` (stdio server — AI coding agent entry point)
- Transport: **stdio** (`StdioServerTransport`)
- Started independently from `aspire run`; not part of the `aspire run` process.
- AI tools (VS Code, Copilot CLI, Claude Code) launch it via `aspire mcp start` as a spawned stdio process.
- Acts as a **router/proxy**: for dashboard-backed tools, it connects to the Dashboard's HTTP MCP endpoint using the `McpInfo` from the running AppHost connection.
- Connects to the AppHost via an **auxiliary backchannel** (`IAuxiliaryBackchannelMonitor`).

### Layer 2: Dashboard MCP server (HTTP server — internal)
- Hosted inside the Dashboard process.
- Transport: **HTTP** (accessible via `DOTNET_DASHBOARD_MCP_ENDPOINT_URL`).
- Implements `AspireResourceMcpTools` and `AspireTelemetryMcpTools`.
- `AspireResourceMcpTools` only active when a resource service is configured (i.e., AppHost is running).

---

## 3. `aspire mcp init` configuration output

`aspire mcp init` auto-detects agent environments and writes config files:

### VS Code → `.vscode/mcp.json`
```json
{
  "servers": {
    "aspire": {
      "type": "stdio",
      "command": "aspire",
      "args": ["mcp", "start"]
    }
  }
}
```

### GitHub Copilot CLI → `~/.copilot/mcp-config.json`
```json
{
  "mcpServers": {
    "aspire": {
      "type": "local",
      "command": "aspire",
      "args": ["mcp", "start"],
      "env": { "DOTNET_ROOT": "${DOTNET_ROOT}" },
      "tools": ["*"]
    }
  }
}
```

### Claude Code → `.mcp.json` (repo root)
```json
{
  "mcpServers": {
    "aspire": {
      "command": "aspire",
      "args": ["mcp", "start"]
    }
  }
}
```

### Open Code → `opencode.jsonc`
```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "aspire": {
      "type": "local",
      "command": ["aspire", "mcp", "start"],
      "enabled": true
    }
  }
}
```

Note: `aspire mcp init` also optionally adds Playwright MCP configuration and an `AGENTS.md` instructions file.

---

## 4. Complete MCP tool list (available via `aspire mcp start`)

### Known (always-available) tools — CLI-backed

| Tool | Parameters | Description |
|---|---|---|
| `list_resources` | none | Lists all app resources with type, state, source, HTTP endpoints, health status, commands, env vars, relationships |
| `list_console_logs` | `resourceName: string` | Returns stdout/stderr console log output for a named resource as plaintext |
| `execute_resource_command` | `resourceName: string`, `commandName: string` | Executes a command (e.g., restart, start, stop) on a resource |
| `list_structured_logs` | `resourceName: string` (optional) | Returns structured (OTLP) log data in JSON; omit resourceName for all resources |
| `list_traces` | (varies) | Lists distributed traces with trace IDs, involved resources, duration, error status |
| `list_trace_structured_logs` | `traceId: string` | Returns logs associated with a specific trace |
| `select_apphost` | (apphost identifier) | Selects which AppHost to target when multiple are running |
| `list_apphosts` | none | Lists all active AppHosts, notes which are in the working directory scope |
| `list_integrations` | none | Lists available Aspire integration packages and versions |
| `get_integration_docs` | `integrationName: string` | Fetches documentation for a specific integration |
| `doctor` | none | Checks environment setup and prerequisites |
| `refresh_tools` | none | Refreshes available tools (useful after AppHost selection change) |

### Resource-specific tools — dynamic, AppHost-backed

- Registered per-resource when the AppHost exposes MCP-enabled resources.
- Named with pattern `<resource-name>_<tool-name>`.
- Discovered dynamically via `TryListToolsAsync` in `AuxiliaryBackchannelRpcTarget`.

---

## 5. `list_resources` return format

Returns JSON with `resourceGraphData` including:
- **Resource type** (Project, Container, Executable)
- **Running state**
- **Source** (project path / image)
- **HTTP endpoints** — includes full URLs with scheme, host, and **port numbers**
- **Health status**
- **Available commands** (start, stop, restart, custom)
- **Environment variables** (configured values injected into the resource)
- **Relationships** (dependencies between resources)

This is the primary programmatic way for an AI agent to discover endpoint URLs and ports for named resources.

---

## 6. Port discovery patterns

### Via MCP (recommended for AI agents)
Call `list_resources` after `aspire run` is started. The returned JSON includes the full URL (scheme + host + port) for each resource endpoint.

### Via Dashboard UI
The **Resources page** shows each resource's endpoints as clickable URLs (port included). This is visual-only.

### Via `DistributedApplication.GetEndpoint()` (in tests)
```csharp
// Get full URI for a named resource's default endpoint
Uri endpoint = app.GetEndpoint("apiservice");
// With specific endpoint name (e.g., "https")
Uri endpoint = app.GetEndpoint("apiservice", "https");
```
- Throws `ArgumentException` if resource not found or endpoint name ambiguous.
- Throws `InvalidOperationException` if the resource has no endpoints.
- From `Aspire.Hosting.Testing` v13.1.0, namespace `Aspire.Hosting.Testing`.

### Via `CreateHttpClient()` (in tests)
```csharp
var httpClient = app.CreateHttpClient("webfrontend");
// Routes requests to the named resource's default endpoint
// Also supports optional endpointName parameter
```

---

## 7. Resource console logs — access methods

| Method | Context | Details |
|---|---|---|
| `list_console_logs` MCP tool | AI agent / MCP client | Returns stdout+stderr for a named resource; best for AI consumption |
| Dashboard Console logs page | Browser UI | Real-time streaming logs per resource; click "Console logs" in the Actions column |
| `DistributedApplication` (tests) | Test code | All resource logs are redirected to `DistributedApplication` by default; configure logging with `builder.Services.AddLogging(...)` |
| `aspire exec --resource <name>` | Terminal / CI | NOT for reading logs; runs a command *in* the resource context (inherits env vars) |

**Important**: `aspire exec` runs a *new command* in the resource's environment — it does NOT pipe existing resource process logs.

---

## 8. `aspire exec` command

- **Status**: Preview / feature-flagged — disabled by default.
- **Enable**: `aspire config set features.execCommandEnabled true`
- **Purpose**: Run an arbitrary command that inherits a resource's configuration (env vars, connection strings, working directory).
- **Use case**: EF Core migrations, database seeding, diagnostic tooling — anything that needs the same env as a running resource.
- **Does NOT**: pipe logs from the running resource process; does NOT start the resource itself (unless `--start-resource` is used).

### Syntax
```bash
aspire exec --resource <resource-name> -- <command> [args...]
# or
aspire exec --start-resource <resource-name> -- <command> [args...]
# or with explicit AppHost
aspire exec --project ./MyApp.AppHost.csproj --resource api -- dotnet ef migrations add Init
```

### Options
| Option | Description |
|---|---|
| `--resource` / `-r` | Name of the target resource (must already be running) |
| `--start-resource` / `-s` | Name of resource to start before running the command |
| `--project` | Path to the AppHost .csproj (optional; auto-detected if omitted) |
| `-d`, `--debug` | Enable CLI debug logging |
| `--wait-for-debugger` | Wait for debugger to attach before running |

---

## 9. Aspire Dashboard — programmatic endpoints

The Aspire Dashboard does **not** expose a general-purpose REST API. Programmatic access is via:

| Endpoint | Env Variable | Protocol | Purpose |
|---|---|---|---|
| OTLP gRPC | `DOTNET_DASHBOARD_OTLP_ENDPOINT_URL` | gRPC | Receive telemetry (logs, traces, metrics) |
| OTLP HTTP | `DOTNET_DASHBOARD_OTLP_HTTP_ENDPOINT_URL` | HTTP/Protobuf | Receive telemetry via HTTP |
| MCP HTTP | `DOTNET_DASHBOARD_MCP_ENDPOINT_URL` | HTTP | Internal MCP endpoint (used by `aspire mcp start`, not for direct external access) |
| Resource gRPC | Internal (DashboardServiceHost) | gRPC | `WatchResources`, `WatchConsoleLogs`, `ExecuteResourceCommand` — internal use only |

The AppHost auto-sets `OTEL_EXPORTER_OTLP_ENDPOINT` for all project resources, pointing them to the Dashboard's OTLP gRPC endpoint.

**Practical implication**: AI agents should NOT try to call Dashboard HTTP/gRPC directly. Use the `aspire mcp start` stdio interface instead — it proxies calls to the dashboard's internal MCP server.

---

## 10. `DistributedApplicationTestingBuilder` — port discovery and E2E testing

### Package
`Aspire.Hosting.Testing` v13.1.0 — NuGet ref `Aspire.Hosting.Testing.dll`

### Default behavior (ports randomized)
```csharp
var appHost = await DistributedApplicationTestingBuilder
    .CreateAsync<Projects.MyAppHost>();
await using var app = await appHost.BuildAsync();
await app.StartAsync();
```
- Dashboard is **disabled** by default in tests.
- Ports are **randomized** to allow parallel test runs.

### Disable port randomization (stable endpoints)
```csharp
var appHost = await DistributedApplicationTestingBuilder
    .CreateAsync<Projects.MyAppHost>(["DcpPublisher:RandomizePorts=false"]);
```

### Get the full endpoint URL for a resource (port included)
```csharp
// Extension method: DistributedApplicationHostingTestingExtensions.GetEndpoint
Uri endpoint = app.GetEndpoint("apiservice");                     // default endpoint
Uri endpoint = app.GetEndpoint("apiservice", "https");            // named endpoint
Uri endpoint = app.GetEndpointForNetwork("apiservice", networkId, "https"); // with network
```

### Create an HttpClient routed to a resource
```csharp
var httpClient = app.CreateHttpClient("webfrontend");             // default endpoint
var httpClient = app.CreateHttpClient("webfrontend", "http");     // named endpoint
```

### Wait for resource health
```csharp
// Wait for resource to be in Running state
await app.ResourceNotifications.WaitForResourceAsync(
    "webfrontend", KnownResourceStates.Running, cts.Token);

// Wait for health checks to pass (recommended before sending HTTP requests)
await app.ResourceNotifications.WaitForResourceHealthyAsync("webfrontend", cts.Token);
```

### Start / stop resources programmatically
```csharp
await app.ResourceCommands.ExecuteCommandAsync("webfrontend", KnownResourceCommands.StartCommand, cts.Token);
await app.ResourceCommands.ExecuteCommandAsync("webfrontend", KnownResourceCommands.StopCommand, cts.Token);
```

### Assert environment variables (unresolved binding expressions)
```csharp
var builder = await DistributedApplicationTestingBuilder.CreateAsync<Projects.MyAppHost>();
var frontend = builder.CreateResourceBuilder<ProjectResource>("webfrontend");
var execConfig = await ExecutionConfigurationBuilder.Create(frontend.Resource)
    .WithEnvironmentVariablesConfig()
    .BuildAsync(new(DistributedApplicationOperation.Publish), NullLogger.Instance, CancellationToken.None);
var envVars = execConfig.EnvironmentVariables.ToDictionary();
// envVars["APISERVICE_HTTPS"] == "{apiservice.bindings.https.url}"
```

### DistributedApplicationFactory (advanced lifecycle control)
```csharp
public class TestingAspireAppHost() : DistributedApplicationFactory(typeof(Projects.AspireApp_AppHost))
{
    protected override void OnBuilderCreating(DistributedApplicationOptions appOptions, HostApplicationBuilderSettings hostOptions)
    {
        hostOptions.Configuration ??= new();
        hostOptions.Configuration["AZURE_SUBSCRIPTION_ID"] = "...";
    }
    protected override void OnBuilderCreated(DistributedApplicationBuilder appBuilder)
    {
        appBuilder.Services.ConfigureHttpClientDefaults(c => c.AddStandardResilienceHandler());
    }
}
```
Lifecycle hooks: `OnBuilderCreating`, `OnBuilderCreated`, `OnBuilding`, `OnBuilt`.

---

## 11. Aspire 9.x → 13.x resource management improvements

| Feature | Added in | Notes |
|---|---|---|
| `WaitForResourceAsync` / `WaitForResourceHealthyAsync` | Aspire 9 | Waits for resource health before tests send requests |
| `aspire mcp init` / `aspire mcp start` | Aspire 13.1 | Full MCP server with `list_resources`, `list_console_logs`, traces, etc. |
| Running-instance detection | 13.1 | Re-running `aspire run` auto-terminates previous instance |
| `ResourceNotificationService` | 9+ | Streaming resource state changes |
| `KnownResourceStates`, `KnownResourceCommands` | 9+ | Constants for state/command names |
| GitHub Copilot in Dashboard | 13.x | "Ask GitHub Copilot" available in resource context menus (VS Code/VS with Copilot subscription) |
