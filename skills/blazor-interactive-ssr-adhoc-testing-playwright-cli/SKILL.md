---
name: blazor-interactive-ssr-adhoc-testing-playwright-cli
description: Specialized for ad-hoc testing Blazor web apps in interactive server render mode with SignalR using playwright-cli. Use when performing quick tests on Blazor components, real-time updates, forms, and UI interactions in server-rendered applications.
version: 1.1.0
---

# Blazor Interactive Server Ad-hoc Testing with playwright-cli

This skill extends the `playwright-cli` skill for ad-hoc testing of Blazor web applications running in interactive server render mode (interactive SSR) with SignalR. It provides workflows for testing quick ad-hoc UX/UI validation, real-time updates, component interactions, and server-side rendering behaviors.

## What is Ad-Hoc Testing?

**Ad-hoc testing** is informal, exploratory testing performed without predefined test cases or scripts. It focuses on:

- **Exploratory Discovery**: Uncovering unexpected behaviors, edge cases, and potential issues through manual interaction
- **Quick Validation**: Rapid verification of specific features or bug fixes without formal test planning
- **Debugging Support**: Interactive investigation of problems in development or staging environments
- **Data Extraction**: Manual collection of information from the application for analysis

### Ad-Hoc Testing vs. Alternatives

| Aspect            | Ad-Hoc Testing                       | Scripted/Automated Testing             | Formal Testing                  |
| ----------------- | ------------------------------------ | -------------------------------------- | ------------------------------- |
| **Planning**      | Minimal/none                         | Detailed test scripts                  | Comprehensive test plans        |
| **Documentation** | Informal notes                       | Test scripts as documentation          | Detailed test cases             |
| **Repeatability** | Low (manual steps)                   | High (automated execution)             | High (documented procedures)    |
| **Speed**         | Fast for single runs                 | Fast for multiple runs                 | Moderate (setup overhead)       |
| **Coverage**      | Broad but shallow                    | Deep but narrow                        | Systematic and comprehensive    |
| **Maintenance**   | None required                        | High (script updates)                  | Moderate (test case updates)    |
| **Tools**         | Manual + CLI tools                   | Test frameworks (Playwright, Selenium) | Test management systems         |
| **Best For**      | Exploration, debugging, quick checks | Regression, CI/CD, repetitive tasks    | Compliance, audits, large teams |

### When to Choose Ad-Hoc Testing

- **During Development**: Quick verification of new features or bug fixes
- **Debugging Sessions**: Interactive investigation of reported issues
- **Exploratory Testing**: Discovering unknown behaviors or edge cases
- **Prototyping**: Testing early implementations before formal testing
- **Data Collection**: Manual extraction of information for analysis
- **Short Tasks**: When automation setup would exceed the task duration

### Alternatives to Ad-Hoc Testing

- **Automated E2E Testing**: Use Playwright Test Framework for repeatable, CI/CD-integrated tests
- **Unit Testing**: Test individual components with xUnit/bUnit for fast feedback
- **Integration Testing**: Test component interactions with ASP.NET Core test framework
- **Manual Test Cases**: Follow documented test procedures for consistency
- **Performance Testing**: Use specialized tools like k6 or Lighthouse for load/performance analysis

## Scope and Coverage

### What This Skill Covers

This skill provides ad-hoc UI testing capabilities for Blazor interactive server applications using playwright-cli. It focuses on:

- **Ad-hoc E2E Testing**: Manual, exploratory testing of complete user workflows without predefined scripts
- **Component Interaction Testing**: Ad-hoc testing of individual component behaviors and state changes
- **Real-time Update Validation**: Verifying SignalR-driven UI updates and data synchronization
- **Form and Validation Testing**: Manual testing of form submissions, client/server validation, and error handling
- **Basic Performance Assessment**: Simple responsiveness checks and performance monitoring
- **Basic Visual Regression Verification**: Basic snapshot-based or DOM-based (CSS selector) visual regression checks

**Recommended Approaches:**

- **POC/Exploratory**: Manual testing, debugging, form filling, data extraction. Use when you need to quickly explore app behavior, debug issues, or extract data without automation overhead.
- **Hybrid**: Explore with CLI, then convert to scripts for automation. Use this approach when you need repeatable E2E validations with automated CLI execution but manual verification is acceptable—ideal for prototyping, quick validations, or scenarios where full test framework setup is overkill but some automation is required (e.g., <30 min tasks, solo development, or pre-CI checks). Transition to production scripts if repeatability exceeds 3 runs or requires programmatic assertions.

### What This Skill Does Not Cover

This skill is specifically designed for ad-hoc, manual testing scenarios. It does not cover:

- **Automated Testing**: Use Playwright Test Framework for scripted, repeatable, CI/CD-integrated tests
- **Unit Testing**: Test individual components with xUnit/bUnit for fast feedback
- **Integration Testing**: Test component interactions with ASP.NET Core test framework
- **Load Testing**: Test app behavior under high concurrent user load with tools like k6, JMeter, or Azure Load Testing
- **Security Testing**: Test for vulnerabilities, authentication, and authorization with OWASP tools and security scanners
- **Accessibility Testing**: Ensure app meets WCAG standards with axe-core, WAVE, or Lighthouse accessibility audits
- **API Testing**: Test backend APIs independently with tools like Postman, REST Client, or xUnit integration tests
- **Production E2E Testing**: For production environments, use formal E2E test suites instead of ad-hoc CLI commands

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

### Strategy 6: Basic Visual Regression Verification

**Goal**: Verify visual rendering consistency and detect unintended visual changes through snapshot-based and DOM-based comparisons.

**Workflow**:

```bash
# Navigate to component/page and establish baseline
playwright-cli open https://localhost:5001/component-page
playwright-cli eval "window.Blazor !== undefined"  # Ensure Blazor is loaded
playwright-cli snapshot baseline-visual

# Perform action that might change visual appearance
playwright-cli click e5  # Toggle theme, expand section, etc.
playwright-cli eval "document.querySelector('.visual-element').classList.contains('changed')"
playwright-cli snapshot after-visual-change

# Verify specific visual elements with DOM checks
playwright-cli eval "getComputedStyle(document.querySelector('.element')).color === 'rgb(255, 0, 0)'"
playwright-cli eval "document.querySelector('.layout-element').offsetWidth > 100"

# Test responsive behavior if applicable
playwright-cli viewport 768 1024  # Tablet size
playwright-cli snapshot tablet-layout
playwright-cli eval "document.querySelector('.responsive-element').offsetWidth < 768"
```

### Strategy 7: Basic Performance Assessment

**Goal**: Assess basic rendering performance and responsiveness of UI interactions.

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
