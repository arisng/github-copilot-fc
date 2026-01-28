# Playwright E2E workflow (stability focused)

## Goal
Provide a repeatable, stable E2E workflow with Playwright CLI that minimizes flaky tests in Blazor Interactive Server apps.

## Pre-run checklist
- App is running locally and reachable at a stable base URL.
- Required test data is seeded.
- Feature flags are set for consistent behavior.
- Browser profile is isolated per environment.

## Profile strategy
- Create a dedicated Playwright CLI profile per app/environment.
- Store only necessary config (base URL, viewport, storage state).
- Avoid sharing profiles across unrelated suites.

## Selector strategy
- Prefer `data-testid` and automation IDs.
- Avoid selectors tied to layout or visual ordering.
- Use role-based selectors only when the UI is stable and accessible.

## Waiting strategy
- Wait on UI state changes, not timeouts.
- Gate flows on explicit readiness markers.
- Avoid `networkidle` for Blazor unless you fully understand background polling.

## Reliability practices
- Use retries sparingly for known transient transitions.
- Capture trace + screenshot on first failure.
- Keep each test scenario small and deterministic.

## Debugging and artifacts
- Keep traces, screenshots, and console logs per run.
- Include the profile name and timestamp in artifact folders.
- Re-run failures with the same profile to preserve session state.

## Flake triage checklist
- Confirm readiness signals were reached.
- Check for missing selectors or hydration delays.
- Review console errors and trace timeline.
- Stabilize the UI or add a test-only readiness marker if needed.
