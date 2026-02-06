# Aspire Isolation for Parallel Worktrees

Comprehensive guidance for running multiple Aspire AppHost instances simultaneously for parallel development workflows (git worktrees, multi-agent AI development). This solves the port conflict problem that prevents scaling to multiple instances.

## Table of Contents

1. [The Problem](#the-problem-port-conflicts)
2. [Solution Architecture](#solution-architecture)
3. [Implementation Guide](#implementation-guide)
4. [Script Patterns](#script-patterns)
5. [MCP Proxy Architecture](#mcp-proxy-architecture)
6. [Distributed Testing](#distributed-testing)
7. [Troubleshooting](#troubleshooting)

## The Problem: Port Conflicts

### What Happens

When running multiple AppHost instances (e.g., in separate git worktrees), they all attempt to bind to the same default ports:

- **Port 18888**: Aspire Dashboard
- **Port 18889**: OTLP (OpenTelemetry) endpoint
- **Port 18890**: Resource Service endpoint  
- **Port 4317**: MCP endpoint (if enabled)

The first instance starts successfully; subsequent instances fail with "port already in use" errors.

### Why Manual Workarounds Fail

- Requires remembering which ports are available
- Must manually set 3-4 environment variables per worktree
- Cleanup is error-prone (tracking which terminals use which ports)
- **Critical issue**: MCP client configuration needs to know the dynamic port and API key

The root problem: worktrees have isolated code but share port space.

## Solution Architecture

### Two-Layer Approach

**Layer 1: Automatic Port Allocation**
- Scripts find free ports using OS-level allocation
- Set environment variables for Aspire dashboard components
- Launch AppHost with unique ports
- Save configuration to `settings.json` for MCP proxy

**Layer 2: MCP Proxy (Optional)**
- Provides fixed MCP client configuration
- Reads `settings.json` dynamically to discover current AppHost
- Forwards MCP requests to the correct dynamic port
- Eliminates per-worktree MCP configuration

```
┌─────────────┐         ┌──────────────────┐         ┌─────────────────┐
│ AI Agent    │ stdio   │ aspire-mcp-proxy │  HTTP   │ Aspire AppHost  │
│             ├────────►│ (fixed config)   ├────────►│ (dynamic port)  │
│             │         │                  │         │                 │
└─────────────┘         └──────────────────┘         └─────────────────┘
                              ↓
                        reads from
                        scripts/settings.json
                        (updated by start-apphost)
```

## Implementation Guide

### Step 1: Configure AppHost for Worktree Detection

Detect the git folder name and customize the dashboard name:

```csharp
var gitFolderName = GitFolderResolver.GetGitFolderName();
var dashboardAppName = string.IsNullOrEmpty(gitFolderName)
    ? "MyApp"
    : $"MyApp-{gitFolderName}";

var builder = DistributedApplication.CreateBuilder(new DistributedApplicationOptions()
{
    Args = args,
    DashboardApplicationName = dashboardAppName,
});

var backend = builder.AddProject<Projects.Backend>("backend")
    .WithHttpEndpoint(name: "http")  // ✅ No port = random allocation
    .WithExternalHttpEndpoints();

builder.Build().Run();
```

**GitFolderResolver pattern:**

```csharp
public static class GitFolderResolver
{
    public static string GetGitFolderName()
    {
        try
        {
            var gitDir = FindGitDirectory(Directory.GetCurrentDirectory());
            if (gitDir == null) return string.Empty;
            
            // If .git is a file (worktree), read the worktree path
            if (File.Exists(gitDir))
            {
                var content = File.ReadAllText(gitDir);
                var match = Regex.Match(content, @"gitdir:\s*(.+)");
                if (match.Success)
                {
                    var worktreePath = match.Groups[1].Value.Trim();
                    return Path.GetFileName(Path.GetDirectoryName(worktreePath));
                }
            }
            
            return string.Empty;
        }
        catch
        {
            return string.Empty;
        }
    }

    private static string? FindGitDirectory(string path)
    {
        var current = new DirectoryInfo(path);
        while (current != null)
        {
            var gitPath = Path.Combine(current.FullName, ".git");
            if (Directory.Exists(gitPath) || File.Exists(gitPath))
                return gitPath;
            current = current.Parent;
        }
        return null;
    }
}
```

**Key benefits:**
- Dashboard shows `MyApp-feature-auth` for the feature-auth worktree
- Clear visual distinction in dashboard UI
- `WithHttpEndpoint()` without port enables random allocation

### Step 2: Start AppHost with Management Scripts

**Never run `dotnet run` directly.** Always use management scripts.

#### PowerShell (Windows)

```powershell
cd worktrees-example.worktrees\feature-auth
.\scripts\start-apphost.ps1

# Output shows:
# - Dashboard URL with unique port
# - MCP endpoint saved to settings.json
# - Process ID for cleanup
```

#### Bash (Linux/macOS/Git Bash)

```bash
cd worktrees-example.worktrees/feature-auth
./scripts/start-apphost.sh
```

### Step 3: Run Multiple Worktrees Simultaneously

Terminal 1 – Feature Auth:
```powershell
cd worktrees-example.worktrees\feature-auth
.\scripts\start-apphost.ps1
# Dashboard: https://localhost:54772
# MCP: port 54775 (saved to settings.json)
# Process ID: 12345
```

Terminal 2 – Feature Payments:
```powershell
cd worktrees-example.worktrees\feature-payments
.\scripts\start-apphost.ps1
# Dashboard: https://localhost:61447
# MCP: port 61450 (saved to settings.json)
# Process ID: 67890
```

All instances run simultaneously with zero conflicts!

### Step 4: Cleanup When Done

#### Quick Cleanup (Recommended)
```powershell
.\scripts\kill-apphost.ps1 -All
```

```bash
./scripts/kill-apphost.sh --all
```

Terminates all AppHost processes from your repository.

## Script Patterns

### start-apphost.ps1 / start-apphost.sh

**Responsibilities:**
1. Find 4 free ports using OS allocation
2. Set environment variables for Aspire dashboard
3. Update `scripts/settings.json` with MCP port and API key
4. Launch AppHost in the background
5. Display dashboard URL and process ID

**Environment variables set:**

```powershell
$env:ASPIRE_DASHBOARD_PORT = "54772"                              # Dynamic
$env:ASPIRE_DASHBOARD_OTLP_HTTP_ENDPOINT_URL = "http://localhost:54773"
$env:ASPIRE_RESOURCE_SERVICE_ENDPOINT_URL = "http://localhost:54774"
$env:ASPIRE_DASHBOARD_MCP_ENDPOINT_URL = "http://localhost:54775"
$env:AppHost__McpApiKey = "generated-api-key"                     # For Aspire MCP
```

**Output format:**
```
Starting AppHost with dynamic ports...
Dashboard: https://localhost:54772
MCP: http://localhost:54775
Process ID: 12345
Settings saved to: scripts/settings.json
```

**settings.json structure:**

```json
{
  "port": "54775",
  "apiKey": "abc123...",
  "lastUpdated": "2026-02-06T10:30:00Z"
}
```

### kill-apphost.ps1 / kill-apphost.sh

**Purpose:** Clean shutdown of AppHost instances.

**Flags:**
- `-All` / `--all`: Kill all AppHost processes from the repository
- `-ProcessId <id>` / `--pid <id>`: Kill a specific process

**Examples:**

```powershell
# Kill all from repo
.\scripts\kill-apphost.ps1 -All

# Kill specific instance
.\scripts\kill-apphost.ps1 -ProcessId 12345
```

## MCP Proxy Architecture

### When to Use MCP Proxy

Use the MCP proxy layer when:
- AI agents need to connect to Aspire MCP
- Multiple worktrees/instances run concurrently
- You want zero-configuration MCP client setup

### How the Proxy Works

The `aspire-mcp-proxy.cs` script is both:
1. **MCP Server (stdio)** – Exposes tools to AI agents via stdin/stdout
2. **MCP Client (HTTP)** – Connects to Aspire's MCP server

**Architecture:**

```
┌─────────────────────────────────────────────────────────────────┐
│ aspire-mcp-proxy.cs (single file, ~272 lines)                   │
│                                                                  │
│  ┌────────────────────┐         ┌─────────────────────┐         │
│  │ MCP Server (stdio) │◄────────┤ AI Agent            │         │
│  │ - Exposes tools    │         │ (sends tool calls)  │         │
│  └────────┬───────────┘         └─────────────────────┘         │
│           │                                                      │
│           ▼                                                      │
│  ┌────────────────────┐                                          │
│  │ ProxyTool          │  For each tool:                          │
│  │ - Reads settings   │  1. Read settings.json                   │
│  │ - Forwards calls   │  2. Create HTTP client                   │
│  └────────┬───────────┘  3. Forward to Aspire                    │
│           │              4. Return response                       │
│           ▼                                                      │
│  ┌────────────────────┐                                          │
│  │ MCP Client (HTTP)  │────────► Aspire Dashboard MCP            │
│  │ - Dynamic port     │         (from settings.json)             │
│  └────────────────────┘                                          │
└─────────────────────────────────────────────────────────────────┘
```

### Proxy Configuration

**AI Agent Configuration (e.g., `.roo/mcp.json`):**

```json
{
  "mcpServers": {
    "aspire-mcp": {
      "command": "dotnet",
      "args": ["scripts/aspire-mcp-proxy.cs", "--no-build"],
      "description": "Aspire Dashboard MCP stdio proxy",
      "alwaysAllow": [
        "list_resources",
        "execute_resource_command",
        "list_traces",
        "list_console_logs",
        "list_structured_logs"
      ]
    }
  }
}
```

**No ports to configure!** The proxy reads `scripts/settings.json` dynamically.

### Settings Resolution Priority

1. **Environment Variables** (highest priority):
   - `ASPIRE_MCP_PORT`
   - `ASPIRE_MCP_API_KEY`

2. **settings.json file** (default):
   - Updated by `start-apphost` scripts

This allows flexibility: override via environment variables if needed, but defaults to file-based discovery.

### Tool Caching for Offline Mode

When the proxy starts, it attempts to connect to Aspire and cache available tools. If Aspire isn't running, it uses cached tool metadata so the AI agent can still see available tools (though tool invocations fail until AppHost starts).

### Implementation with .NET 10 Single-File Scripts

The proxy uses .NET 10's single-file script capability:

```csharp
#:package ModelContextProtocol@0.4.1-preview.1
#:package Microsoft.Extensions.Hosting@10.0.0
#:package Microsoft.Extensions.Logging@10.0.0

// Complete proxy in one .cs file!
```

Run with: `dotnet run scripts/aspire-mcp-proxy.cs`

No project file needed; packages restore automatically.

## Distributed Testing

Aspire provides built-in distributed testing capabilities with automatic port isolation.

### DistributedApplicationTestingBuilder

Spin up the full application stack with randomized ports:

```csharp
var appHost = await DistributedApplicationTestingBuilder
    .CreateAsync<Projects.MyApp_AppHost>();

var app = await appHost.BuildAsync();
await app.StartAsync();

// Wait for resources
await app.ResourceNotifications.WaitForResourceHealthyAsync("frontend");

// Get dynamically allocated endpoints
var frontendUrl = app.GetEndpoint("frontend");
```

### End-to-End Testing with Playwright

Combine with Playwright for full-stack E2E tests:

```csharp
// Get the dynamically allocated frontend URL
var frontendUrl = app.GetEndpoint("frontend").ToString();

// Use Playwright to interact with the UI
var page = await browser.NewPageAsync();
await page.GotoAsync(frontendUrl);

// Test the actual UI with all dependencies running
await page.FillAsync("#title", "Test Task");
await page.ClickAsync("button[type='submit']");
await page.WaitForSelectorAsync(".task-item");
```

**Key benefits:**
- Dashboard disabled by default (set `DisableDashboard=false` if needed)
- Ports randomized automatically (set `DcpPublisher:RandomizePorts=false` for stable ports)
- Complete isolation per test run
- All backend services, databases, and dependencies orchestrated automatically

### AI Agent Autonomy

With distributed testing, AI agents can:
1. Modify code
2. Run the full test suite with all system dependencies
3. Validate changes end-to-end without manual intervention

## Troubleshooting

### AppHost fails to find instance

**Symptom:** `aspire run` can't locate AppHost project.

**Solution:**
- Move to the AppHost directory or a parent folder
- Or pass `--project <path-to-apphost.csproj>`

### Port conflicts persist

**Symptom:** Even with scripts, ports conflict.

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
