---
name: blazor-interactive-ssr-testing-with-playwright-cli
description: Specialized for ad-hoc testing Blazor web apps in interactive server render mode with SignalR using playwright-cli. Use when performing quick tests on Blazor components, real-time updates, forms, and UI interactions in server-rendered applications.
version: 1.0.0
---

# Blazor Interactive Server Testing with playwright-cli

This skill extends the `playwright-cli` skill for ad-hoc testing of Blazor web applications running in interactive server render mode with SignalR. It provides workflows for testing real-time updates, component interactions, and server-side rendering behaviors.

## Core Workflow

1. Launch the Blazor app in a playwright-cli session.
2. Wait for SignalR connection and initial render.
3. Perform interactions and verify real-time updates.
4. Capture snapshots or logs for validation.

## Testing Types and When to Use Them

This skill is designed for **ad-hoc testing** scenarios. Choose the appropriate testing type based on your needs:

- **POC/Exploratory**: Manual testing, debugging, form filling, data extraction. Use when you need to quickly explore app behavior, debug issues, or extract data without automation overhead.

- **Production**: Use E2E scripts instead (Playwright Test Framework). Recommended for CI/CD pipelines, regression testing, and scenarios requiring programmatic assertions and full test reporting.

- **Hybrid**: Explore with CLI, then convert to scripts for automation. Use this approach when you need repeatable E2E validations with automated CLI execution but manual verification is acceptable—ideal for prototyping, quick validations, or scenarios where full test framework setup is overkill but some automation is required (e.g., <30 min tasks, solo development, or pre-CI checks). Transition to production scripts if repeatability exceeds 3 runs or requires programmatic assertions.

## Key Considerations for Blazor Server Mode (interactive SSR)

- **SignalR Connection**: Always wait for the WebSocket connection to establish before testing interactions.
- **Server Rendering**: Elements may update asynchronously; use `eval` to check DOM state after actions.
- **Component Lifecycle**: Test component mounting, updates, and disposal.
- **Error Handling**: Monitor console for Blazor-specific errors (e.g., circuit disconnections).

## Pragmatic Strategies and Workflows

This section outlines practical testing strategies for Blazor interactive server apps, with concrete workflows using playwright-cli commands.

### Strategy 1: Connection Establishment and Initial Load

**Goal**: Verify SignalR connection and initial component rendering.

**Workflow**:

```bash
# Open the app and wait for Blazor to initialize
playwright-cli open https://localhost:5001
playwright-cli eval "window.Blazor !== undefined && window.Blazor.start !== undefined"
playwright-cli eval "document.querySelector('blazor-error-boundary') === null"  # No errors
playwright-cli snapshot initial-load

# Verify SignalR connection (check network tab for WebSocket)
playwright-cli network
playwright-cli eval "window.Blazor._internal.dotNetObject !== undefined"
```

### Strategy 2: Component Interaction and State Changes

**Goal**: Test user interactions that trigger server-side state updates.

**Workflow**:

```bash
# Navigate to component and take baseline snapshot
playwright-cli open https://localhost:5001/counter
playwright-cli snapshot baseline

# Perform interaction and wait for update
playwright-cli click e5  # Counter increment button
playwright-cli eval "document.querySelector('.counter-value').textContent.includes('1')"
playwright-cli snapshot after-click

# Verify state persistence across interactions
playwright-cli click e5
playwright-cli eval "document.querySelector('.counter-value').textContent.includes('2')"
```

### Strategy 3: Real-Time Data Synchronization

**Goal**: Validate that UI updates correctly with server-pushed data.

**Workflow**:

```bash
# Open real-time dashboard
playwright-cli open https://localhost:5001/dashboard
playwright-cli snapshot initial-data

# Simulate server data change (if possible via API or another session)
# In another terminal/session: trigger data update
playwright-cli eval "document.querySelector('.live-data').textContent"
playwright-cli wait 2000  # Wait for potential update
playwright-cli eval "document.querySelector('.live-data').textContent !== initialValue"
playwright-cli snapshot updated-data
```

### Strategy 4: Form Submission and Validation

**Goal**: Test form interactions, client/server validation, and submission handling.

**Workflow**:

```bash
# Navigate to form page
playwright-cli open https://localhost:5001/contact-form
playwright-cli snapshot form-initial

# Fill form with valid data
playwright-cli fill e2 "user@example.com"
playwright-cli fill e3 "Test message"
playwright-cli click e4  # Submit
playwright-cli eval "document.querySelector('.success-message') !== null"
playwright-cli snapshot form-success

# Test validation errors
playwright-cli reload
playwright-cli fill e2 "invalid-email"
playwright-cli click e4
playwright-cli eval "document.querySelector('.validation-error').textContent.includes('email')"
playwright-cli snapshot form-error
```

### Strategy 5: Error Scenarios and Recovery

**Goal**: Test circuit disconnections, error boundaries, and recovery mechanisms.

**Workflow**:

```bash
# Open app and establish connection
playwright-cli open https://localhost:5001
playwright-cli eval "window.Blazor !== undefined"

# Simulate disconnection (force close WebSocket if possible)
playwright-cli run-code "page.evaluate(() => window.Blazor._internal.forceCloseConnection?.())"
playwright-cli eval "document.querySelector('.reconnecting') !== null"
playwright-cli wait 5000  # Wait for reconnection attempt
playwright-cli eval "document.querySelector('.reconnected') !== null || window.Blazor._internal.connectionState === 'Connected'"
```

### Strategy 6: Performance and Load Testing

**Goal**: Assess rendering performance and responsiveness under load.

**Workflow**:

```bash
# Open performance-critical page
playwright-cli open https://localhost:5001/data-grid
playwright-cli tracing-start

# Perform rapid interactions to test responsiveness
playwright-cli click e10  # Sort button
playwright-cli wait 1000
playwright-cli click e11  # Filter button
playwright-cli wait 1000
playwright-cli fill e12 "search term"
playwright-cli tracing-stop

# Check for performance issues in console
playwright-cli console
playwright-cli eval "performance.getEntriesByType('measure').length > 0"
```

## Commands and Examples

### Setup and Navigation

```bash
playwright-cli open https://localhost:5001
playwright-cli eval "window.Blazor !== undefined"  # Wait for Blazor to load
playwright-cli snapshot
```

### Testing Real-Time Updates

```bash
# Interact with a component that triggers SignalR update
playwright-cli click e5  # Click a button that updates server state
playwright-cli eval "document.querySelector('.updated-element').textContent"  # Verify update
playwright-cli snapshot
```

### Form Testing with Validation

```bash
playwright-cli fill e2 "test@example.com"
playwright-cli click e3  # Submit form
playwright-cli eval "document.querySelector('.validation-error')"  # Check for errors
```

### Debugging SignalR Issues

```bash
playwright-cli console  # Monitor for connection errors
playwright-cli network  # Check WebSocket traffic
playwright-cli tracing-start
# Perform actions
playwright-cli tracing-stop
```

## Best Practices

- Start with the appropriate strategy from the Pragmatic Strategies section based on your testing goal.
- Use `eval` scripts to wait for Blazor-specific conditions (e.g., component rendered, SignalR connected).
- Combine with `snapshot` to capture UI state before/after SignalR events.
- For complex tests, chain commands in scripts for reproducibility.
- Monitor console and network tabs for Blazor-specific errors and WebSocket traffic.
- Reference `playwright-cli` skill for full command set and advanced features.

## References

Skill `playwright-cli` provides the foundational commands and workflows for browser automation. This skill builds on that foundation with Blazor-specific testing strategies.
