---
name: blazor-playwright-e2e
description: End-to-end testing workflow for Blazor web apps using Interactive Server render mode with playwright-cli. Use when Claude needs to plan or run stable E2E tests, gate on Blazor readiness, manage browser profiles, or improve test reliability for Blazor Interactive Server.
---

# Blazor Interactive Server E2E (Playwright CLI)

## Quick start
- Use this workflow to validate Blazor Interactive Server apps end-to-end with immediate, repeatable steps.
- Use the Playwright command set from [skills/playwright-cli/SKILL.md](skills/playwright-cli/SKILL.md).
- Read [references/blazor-interactive-server.md](references/blazor-interactive-server.md) for readiness signals and hydration notes.
- Read [references/playwright-e2e-workflow.md](references/playwright-e2e-workflow.md) for stability checklists and retries.
- Scan official sources for render-mode rules and Playwright test setup: [references/blazor-official-docs.md](references/blazor-official-docs.md), [references/playwright-official-docs.md](references/playwright-official-docs.md).
- Use blog guidance for real-world patterns and pitfalls: [references/authoritative-blogs.md](references/authoritative-blogs.md).

## Immediate E2E runbook
1. Start the app and confirm a stable base URL.
2. Verify Interactive Server is enabled in `Program.cs` and applied via `@rendermode` (or global render mode).
3. Add or confirm stable selectors (`data-testid`, `pw-name`, or explicit automation IDs).
4. Create or reuse a Playwright CLI profile for the target environment.
5. Open the target route and wait for Blazor readiness signals before assertions.
6. Execute user flows with web-first `Expect` assertions and avoid sleeps.
7. On failure, capture trace/screenshot artifacts and store alongside run output.
8. Clean up or reset session state (cookies/storage) between tests as needed.

## Core workflow
1. Confirm the app is running locally and the test base URL is stable.
2. Initialize a Playwright CLI profile for the app (separate profile per environment).
3. Open the page and wait for Blazor readiness signals before assertions.
4. Execute user flows with stable selectors and minimal timing dependencies.
5. Capture traces or screenshots on failure and store artifacts with the run output.
6. Clean up sessions when the run completes.

## Blazor readiness gates (Interactive Server)
- Wait for the shell to render and the root element to be visible.
- Wait for the circuit to connect and interactive components to hydrate.
- Prefer app-provided readiness markers (data attributes or test IDs) over timeouts.
- Avoid assertions until the app is interactive and event handlers are attached.

## Playwright CLI profile usage
- Create a dedicated profile for each app/environment.
- Reuse the profile for session persistence and faster debugging.
- Keep profile configuration minimal and version controlled.

## Stability guidance
- Prefer `data-testid` or explicit automation IDs over CSS layout selectors.
- Avoid sleeps; use explicit waits tied to UI state changes.
- Use retries only for known flaky transitions and record a trace when they happen.

## References
- Blazor readiness and hydration: [references/blazor-interactive-server.md](references/blazor-interactive-server.md)
- Playwright E2E stability workflow: [references/playwright-e2e-workflow.md](references/playwright-e2e-workflow.md)
- Official Blazor render mode docs: [references/blazor-official-docs.md](references/blazor-official-docs.md)
- Official Playwright .NET docs: [references/playwright-official-docs.md](references/playwright-official-docs.md)
- Authoritative blog guidance: [references/authoritative-blogs.md](references/authoritative-blogs.md)
