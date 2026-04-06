# Aspire app adoption reference

Load this file when the user asks about:
- Adding Aspire to an existing solution (incremental adoption)
- AppHost.cs patterns with `AddProject`, `WithReference`, `WaitFor`
- ServiceDefaults configuration
- Polyglot (Python/Node) orchestration

## Table of contents

1. [Incremental adoption workflow](#incremental-adoption-workflow)
2. [AppHost.cs patterns](#apphostcs-patterns)
3. [ServiceDefaults configuration](#servicedefaults-configuration)
4. [Polyglot orchestration](#polyglot-orchestration)

---

## Incremental adoption workflow

Use this 5-step pattern when helping users add Aspire to existing apps:

### Step 1 — Initialize Aspire support → `aspire init`

```bash
aspire init
```

- Interactive by default: analyzes solution structure and suggests projects to add
- Creates `{SolutionName}.AppHost/` with `AppHost.cs`
- Optionally adds a ServiceDefaults project

### Step 2 — Register projects in AppHost.cs

Edit `AppHost.cs` to wire up services:

```csharp
var api = builder.AddProject<Projects.MyApi>("api")
    .WithHttpHealthCheck("/health");

var web = builder.AddProject<Projects.MyWeb>("web")
    .WithExternalHttpEndpoints()
    .WithReference(api)
    .WaitFor(api);
```

**Key methods:**
- `AddProject<T>("name")` – register a .NET project as an Aspire resource
- `.WithHttpHealthCheck("/health")` – enable health monitoring
- `.WithReference(dep)` – inject discovery/connection info for a dependency
- `.WaitFor(dep)` – enforce startup ordering
- `.WithExternalHttpEndpoints()` – expose HTTP endpoints externally

### Step 3 — Configure telemetry (optional) → `dotnet new aspire-servicedefaults`

```bash
dotnet new aspire-servicedefaults -n MyProject.ServiceDefaults
dotnet sln add MyProject.ServiceDefaults
dotnet add MyProject.Api reference MyProject.ServiceDefaults
```

Provides: observability, resilience, health checks.

### Step 4 — Add integrations (optional) → `aspire add`

```bash
aspire add redis          # Redis cache
aspire add postgres       # PostgreSQL database
aspire add <package-id>   # Any official Aspire integration
```

Then configure in AppHost with `.WithReference(integration)`.

### Step 5 — Run and verify → `aspire run`

```bash
aspire run
```

- Builds AppHost + resources, starts the dashboard
- Dashboard URL appears in terminal output
- Verify resource status, logs, and traces in dashboard

---

## AppHost.cs patterns

### Basic setup with health checks and external endpoints

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

### Adding Redis and sharing across services

```csharp
var builder = DistributedApplication.CreateBuilder(args);

var cache = builder.AddRedis("cache");

var api = builder.AddProject<Projects.MyApi>("api")
    .WithReference(cache)
    .WithHttpHealthCheck("/health");

var worker = builder.AddProject<Projects.MyWorker>("worker")
    .WithReference(cache);

builder.Build().Run();
```

### Adding PostgreSQL with data volume persistence

```csharp
var postgres = builder.AddPostgres("postgres")
    .WithDataVolume();

var db = postgres.AddDatabase("mydb");

var api = builder.AddProject<Projects.MyApi>("api")
    .WithReference(db)
    .WaitFor(db);
```

### Container registry for deployments

```csharp
var registry = builder.AddContainerRegistry("myregistry", "registry.example.com");
var api = builder.AddProject<Projects.Api>("api")
    .WithContainerRegistry(registry);
```

(Adds a `push` step to the deployment pipeline: `aspire do push`.)

---

## ServiceDefaults configuration

Install and reference ServiceDefaults project:

```bash
dotnet new aspire-servicedefaults -n MyProject.ServiceDefaults
dotnet sln add MyProject.ServiceDefaults
dotnet add MyProject.Api reference MyProject.ServiceDefaults
```

Add to each service project's `Program.cs`:

```csharp
var builder = WebApplication.CreateBuilder(args);

// Adds observability (OTLP), resilience (Polly), health checks, service discovery
builder.AddServiceDefaults();

// ... existing service configuration ...

var app = builder.Build();

// Expose /health, /alive, /ready endpoints
app.MapDefaultEndpoints();

// ... existing middleware ...

app.Run();
```

---

## Polyglot orchestration

Aspire supports mixed C#, Python, and Node.js in the same AppHost:

```csharp
var builder = DistributedApplication.CreateBuilder(args);

var cache = builder.AddRedis("cache");

// Python app — injects CACHE_HOST and CACHE_PORT env vars automatically
var worker = builder.AddPythonApp("ml-worker", "../ml-worker", "app.py")
    .WithReference(cache);

// Node.js app
var frontend = builder.AddNodeApp("frontend", "../frontend", "npm start")
    .WithExternalHttpEndpoints()
    .WaitFor(worker);

builder.Build().Run();
```

Aspire injects environment variables (e.g., `CACHE_HOST`, `CACHE_PORT`) for each language when references are configured.
