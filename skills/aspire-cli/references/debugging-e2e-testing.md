# Aspire CLI debugging + E2E testing research notes (13.x)

Sources:
- https://aspire.dev/reference/cli/overview/
- https://aspire.dev/reference/cli/commands/aspire-run/
- https://aspire.dev/reference/cli/commands/aspire-exec/
- https://aspire.dev/reference/cli/commands/aspire-do/
- https://aspire.dev/reference/cli/commands/aspire-config/
- https://aspire.dev/testing/overview/
- https://aspire.dev/get-started/pipelines/

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
- Aspire testing is designed for closed-box integration/E2E testing of the full distributed application.
- Testing runs AppHost and resources as separate processes; test code can only influence behavior via configuration/environment, not internal DI services.
- Defaults: dashboard disabled; ports randomized for concurrent runs.
- Testing builder can disable port randomization via `DcpPublisher:RandomizePorts=false`.
- Testing builder can enable the dashboard by setting `DisableDashboard=false`.

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
