# Aspire agent integration and resource access (13.2)

Sources:
- https://aspire.dev/get-started/ai-coding-agents/
- https://aspire.dev/reference/cli/commands/aspire-agent/
- https://aspire.dev/reference/cli/commands/aspire-agent-init/
- https://aspire.dev/reference/cli/commands/aspire-agent-mcp/
- https://aspire.dev/reference/cli/commands/aspire-docs/
- https://aspire.dev/reference/cli/commands/aspire-run/
- https://aspire.dev/reference/cli/commands/aspire-start/
- https://aspire.dev/reference/cli/commands/aspire-describe/
- https://aspire.dev/reference/cli/commands/aspire-logs/
- https://aspire.dev/reference/cli/commands/aspire-resource/
- https://aspire.dev/reference/cli/commands/aspire-wait/
- https://aspire.dev/whats-new/aspire-13-2/

## Command surface

Use these commands together:

- `aspire agent init` configures supported coding-agent environments and installs the Aspire skill file.
- `aspire agent mcp` starts the Aspire MCP server when you need a manual stdio entry point.
- `aspire docs list`, `aspire docs search`, and `aspire docs get` cover CLI-first official docs lookup when MCP is not already connected.
- `aspire run` or `aspire start` launches the AppHost.
- `aspire describe`, `aspire logs`, `aspire otel`, `aspire wait`, and `aspire resource` cover most CLI-first runtime inspection and control.

## What `aspire agent init` configures

`aspire agent init` detects supported assistants and can set up:

- Aspire skill files
- Aspire MCP server configuration
- Playwright CLI integration

Supported assistants include:

- VS Code with GitHub Copilot
- Copilot CLI
- Claude Code
- OpenCode

The Aspire docs also describe skill-file paths such as:

- `.github\skills\aspire\SKILL.md`
- `.claude\skills\aspire\SKILL.md`

## What the MCP server exposes

The Aspire MCP server is the agent-friendly runtime view of a running AppHost. Common tools include:

- `list_docs`
- `search_docs`
- `get_doc`
- `list_resources`
- `list_console_logs`
- `list_structured_logs`
- `list_traces`
- `list_trace_structured_logs`
- `execute_resource_command`
- `list_apphosts`
- `select_apphost`
- `list_integrations`
- `get_integration_docs`
- `doctor`

Use `list_resources` for endpoint and port discovery. It returns resource names, types, health, commands, and full endpoint URLs.

Use `search_docs` to find slugs and `get_doc` to read the selected page when the agent needs current Aspire guidance without leaving the session.

## CLI and MCP docs parity

| Need | CLI | MCP |
| --- | --- | --- |
| Browse available docs pages | `aspire docs list` | `list_docs` |
| Search the docs set | `aspire docs search <topic>` | `search_docs` |
| Read the selected page | `aspire docs get <slug>` | `get_doc` |

## Preferred workflow

1. Run `aspire agent init` if the workspace is not already configured.
2. Start the AppHost with `aspire start --format Json` or `aspire run`.
3. Add `--isolated` when multiple copies of the same AppHost may run.
4. Let the coding agent connect through `aspire agent mcp`.
5. Use CLI docs commands or MCP docs tools before editing unfamiliar integrations, custom commands, or AppHost APIs.
6. Use MCP tools for resource discovery, logs, traces, docs, and resource commands.
7. Fall back to `aspire describe`, `aspire logs`, and `aspire wait` when CLI access is simpler than an MCP round-trip.

## Guardrails

- Do not scrape the dashboard to find endpoints or logs when CLI or MCP already exposes structured data.
- Do not use `aspire exec` to read existing logs; it runs a new command in a resource context.
- Do not guess Aspire API shapes when the CLI and MCP can both return current official docs.
- Do not hardcode ports; use `list_resources` or `aspire describe`.
- If multiple AppHosts are running, list or select the active AppHost before acting on resources.
