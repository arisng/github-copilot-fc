# Agentic development with Aspire

Sources:
- https://devblogs.microsoft.com/aspire/agentic-dev-aspirations/
- https://devblogs.microsoft.com/aspire/aspire-docs-in-your-terminal/
- https://aspire.dev/get-started/ai-coding-agents/
- https://aspire.dev/reference/cli/overview/
- https://aspire.dev/reference/cli/commands/aspire-docs/
- https://aspire.dev/whats-new/aspire-13-2/

## Why Aspire helps coding agents

Aspire gives agents three things they struggle to reconstruct from ad hoc scripts and markdown alone:

1. a code-first AppHost the agent can read
2. a compiler-backed orchestration model
3. a runtime with inspectable resources, logs, and telemetry

This means the agent can discover topology from source, start the whole stack with one command, and diagnose failures without asking the user to manually copy logs or screenshots into chat.

## Recommended agent loop

1. Run `aspire doctor` if the environment might be broken.
2. Read the AppHost source to understand resources, references, parameters, and startup order.
3. Run `aspire agent init` if the repo is not already configured for coding agents.
4. Before changing the AppHost for an unfamiliar integration, custom command, or API:
   - use `aspire docs list` when the page or slug is unclear
   - use `aspire docs search <topic>` and then `aspire docs get <slug>` to confirm the documented pattern
5. Start the app:
   - `aspire run` for an attached local loop
   - `aspire start --format Json` for background or delegated sessions
   - add `--isolated` for worktrees, parallel agents, or side-by-side runs
6. Wait for readiness with `aspire wait <resource>`.
7. Inspect live state with `aspire describe`, `aspire logs`, `aspire otel`, or MCP runtime tools.
8. Change code. Use `aspire add <name-or-id>` or AppHost edits only after docs confirm the supported pattern, restart only the affected resource if possible, and inspect again.
9. Pair with `playwright-cli` or a browser agent for UI validation against the live endpoint discovered by Aspire.

## Source-of-truth rules

- Read the AppHost before guessing how the stack is wired together.
- Use `aspire docs list` when you need to browse the available doc set.
- Use `aspire docs search` and `aspire docs get` before `aspire add` or AppHost edits when the Aspire pattern is unfamiliar.
- Prefer Aspire parameters and user secrets over committing local secrets to repo `.env` files.
- Treat the AppHost, official docs, compiler, and telemetry as the deterministic gates in the loop.

## CLI and MCP together

Use the CLI when you need to:

- browse, search, or read official Aspire docs from the terminal
- start or stop the AppHost
- validate the environment
- inspect resources or logs from the terminal
- drive automation with `--format Json`

Use MCP when the agent already has Aspire MCP access and needs structured runtime tools such as:

- docs lookup
- resource discovery
- console logs
- structured logs
- traces
- resource commands

The common pattern is:

1. use Aspire CLI to configure and start the AppHost
2. use MCP tools to inspect the live system from the agent session
3. use browser automation only after Aspire tells you the real endpoint

## Guardrails

- Do not turn the agent into a manual process manager for many separate dev servers if an AppHost already exists.
- Do not scrape the dashboard when CLI or MCP already exposes the same data more reliably.
- Do not guess integration names or unfamiliar AppHost APIs when official Aspire docs are one lookup away.
- Do not hardcode ports; use Aspire discovery.
- Prefer `--isolated` when multiple copies of the same AppHost may run.
- Use telemetry to close the loop: build -> start -> observe -> browser-check -> fix -> restart -> retest.
