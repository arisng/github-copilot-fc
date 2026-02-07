# Aspire CLI debugging + E2E testing research notes (13.x)

Sources:
- https://aspire.dev/reference/cli/overview/
- https://aspire.dev/reference/cli/commands/aspire-run/
- https://aspire.dev/reference/cli/commands/aspire-exec/
- https://aspire.dev/reference/cli/commands/aspire-do/
- https://aspire.dev/reference/cli/commands/aspire-config/
- https://aspire.dev/testing/overview/
- https://aspire.dev/get-started/pipelines/
- https://aspire.dev/testing/write-your-first-test/
- https://aspire.dev/testing/manage-app-host/
- https://aspire.dev/testing/accessing-resources/

## Debugging-oriented CLI behaviors

### `aspire run` (AppHost dev mode)
- Runs the AppHost in development mode and orchestrates resources.
- Steps: verify/installs local hosting certs, builds AppHost/resources, starts resources, launches the dashboard, prints endpoints and log paths.
- AppHost selection resolution order: `--project`, `.aspire/settings.json` `appHostPath`, search current dir and subdirs. A discovered AppHost is stored in `.aspire/settings.json`.
- Debug-specific options:
  - `-d, --debug` enables debug logging about CLI operations.
  - `--wait-for-debugger` pauses before running so a debugger can attach.

### `aspire exec` (run commands in resource context)
- Executes a command in the context of a resource defined by AppHost; requires `--resource` or `--start-resource` and `--` delimiter for args.
- Inherits resource configuration (env vars, connection strings, working dir) for the command.
- Feature toggle: the command is disabled by default; enable via `aspire config set features.execCommandEnabled true`.
- Supports `-d, --debug` and `--wait-for-debugger` for CLI diagnostics.

### `aspire do` (pipeline step execution)
- Executes a named pipeline step and its dependencies for fine-grained orchestration control.
- Useful for targeted debugging of deployment/build stages and for selectively re-running steps.
- `aspire do diagnostics` lists steps, dependencies, and ordering.
- Options include `--log-level`, `--include-exception-details`, `--environment`, `-d, --debug`, `--wait-for-debugger`, and `--` for AppHost args.

## E2E testing implications (Aspire testing)

### When to use Aspire testing

Use Aspire testing when you want to:
- Verify end-to-end functionality of your distributed application
- Ensure interactions between multiple services and resources (databases, caches) behave correctly in realistic conditions
- Confirm data persistence and integration with real external dependencies like PostgreSQL

Use `WebApplicationFactory<T>` instead when testing a single project in isolation, running components in-memory, or mocking external dependencies.

### Testing architecture

Aspire tests run your application as separate processes—you don't have direct access to internal services or components from test code. The test project starts the AppHost, which orchestrates all dependent resources.

Test flow:
1. Test project starts the AppHost
2. AppHost process starts
3. AppHost runs Database, API, Front end applications
4. Test project sends HTTP requests to applications
5. Successful requests confirm service-to-service communication works

### Configuration options

**Default behavior:**
- Dashboard is disabled
- Ports are randomized for concurrent test runs
- Uses Aspire service discovery for endpoint resolution

**Disable port randomization:**
```csharp
var builder = await DistributedApplicationTestingBuilder
    .CreateAsync<Projects.MyAppHost>(
        ["DcpPublisher:RandomizePorts=false"]);
```

**Enable the dashboard:**
```csharp
var builder = await DistributedApplicationTestingBuilder
    .CreateAsync<Projects.MyAppHost>(
        args: [],
        configureBuilder: (appOptions, hostSettings) =>
        {
            appOptions.DisableDashboard = false;
        });
```

### Aspire.Hosting.Testing package

The `Aspire.Hosting.Testing` NuGet package provides `DistributedApplicationTestingBuilder`:
- Creates a test host for your application
- Launches AppHost in a background thread
- Manages application lifecycle
- Allows controlling and manipulating application resources
- Cleans up resources when disposed

## Pipeline behaviors relevant to testing workflows
- Pipelines are step-based with dependencies; use `aspire do <step>` to run only required steps.
- Selective step execution is intended for fast iterations and retrying failed steps without re-running the entire pipeline.
- `aspire do diagnostics` helps identify steps available and their dependency graph.

## Practical best-practice takeaways (to use in skill guidance)
- Use `aspire run` for local debug sessions; capture dashboard URL and log file path output for troubleshooting.
- Use `--wait-for-debugger` and `--debug` for CLI-level diagnostics when AppHost startup is flaky.
- Use `aspire exec --resource <name> -- <command>` to run migrations/tools in the same resource context; remember to enable `features.execCommandEnabled`.
- Use `aspire do diagnostics` to discover available steps and `aspire do <step>` to isolate pipeline phases during failures.
- For E2E tests, rely on Aspire testing to spin up the full app; enable the dashboard and disable port randomization when tests need stable ports or visibility.
