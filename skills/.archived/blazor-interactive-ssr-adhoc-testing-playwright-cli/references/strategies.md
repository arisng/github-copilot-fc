# Blazor Interactive SSR — Ad-Hoc Testing Strategies

## Strategy 1: Connection Establishment and Initial Load

Verify SignalR connection and initial component rendering.

```bash
playwright-cli open https://localhost:5001
playwright-cli eval "window.Blazor !== undefined && window.Blazor.start !== undefined"
playwright-cli eval "document.querySelector('blazor-error-boundary') === null"
playwright-cli snapshot initial-load

# Verify SignalR connection
playwright-cli network
playwright-cli eval "window.Blazor._internal.dotNetObject !== undefined"
```

## Strategy 2: Component Interaction and State Changes

Test user interactions that trigger server-side state updates.

```bash
playwright-cli open https://localhost:5001/counter
playwright-cli snapshot baseline

playwright-cli click e5           # Counter increment button
playwright-cli eval "document.querySelector('.counter-value').textContent.includes('1')"
playwright-cli snapshot after-click

playwright-cli click e5
playwright-cli eval "document.querySelector('.counter-value').textContent.includes('2')"
```

## Strategy 3: Real-Time Data Synchronization

Validate that UI updates correctly with server-pushed data.

```bash
playwright-cli open https://localhost:5001/dashboard
playwright-cli snapshot initial-data

# Trigger server data change in another terminal/session, then:
playwright-cli eval "document.querySelector('.live-data').textContent"
playwright-cli wait 2000
playwright-cli eval "document.querySelector('.live-data').textContent !== initialValue"
playwright-cli snapshot updated-data
```

## Strategy 4: Form Submission and Validation

Test form interactions, client/server validation, and submission handling.

```bash
playwright-cli open https://localhost:5001/contact-form
playwright-cli snapshot form-initial

# Valid submission
playwright-cli fill e2 "user@example.com"
playwright-cli fill e3 "Test message"
playwright-cli click e4
playwright-cli eval "document.querySelector('.success-message') !== null"
playwright-cli snapshot form-success

# Validation errors
playwright-cli reload
playwright-cli fill e2 "invalid-email"
playwright-cli click e4
playwright-cli eval "document.querySelector('.validation-error').textContent.includes('email')"
playwright-cli snapshot form-error
```

## Strategy 5: Error Scenarios and Recovery

Test circuit disconnections, error boundaries, and recovery mechanisms.

```bash
playwright-cli open https://localhost:5001
playwright-cli eval "window.Blazor !== undefined"

# Simulate disconnection
playwright-cli run-code "page.evaluate(() => window.Blazor._internal.forceCloseConnection?.())"
playwright-cli eval "document.querySelector('.reconnecting') !== null"
playwright-cli wait 5000
playwright-cli eval "document.querySelector('.reconnected') !== null || window.Blazor._internal.connectionState === 'Connected'"
```

## Strategy 6: Visual Regression Verification

Verify visual rendering consistency via snapshot and DOM-based checks.

```bash
playwright-cli open https://localhost:5001/component-page
playwright-cli eval "window.Blazor !== undefined"
playwright-cli snapshot baseline-visual

playwright-cli click e5            # Toggle theme, expand section, etc.
playwright-cli eval "document.querySelector('.visual-element').classList.contains('changed')"
playwright-cli snapshot after-visual-change

# DOM checks for specific style properties
playwright-cli eval "getComputedStyle(document.querySelector('.element')).color === 'rgb(255, 0, 0)'"
playwright-cli eval "document.querySelector('.layout-element').offsetWidth > 100"

# Responsive check
playwright-cli resize 768 1024
playwright-cli snapshot tablet-layout
playwright-cli eval "document.querySelector('.responsive-element').offsetWidth < 768"
```

## Strategy 7: Basic Performance Assessment

Assess rendering performance and responsiveness.

```bash
playwright-cli open https://localhost:5001/data-grid
playwright-cli tracing-start

playwright-cli click e10           # Sort button
playwright-cli wait 1000
playwright-cli click e11           # Filter button
playwright-cli wait 1000
playwright-cli fill e12 "search term"
playwright-cli tracing-stop

playwright-cli console
playwright-cli eval "performance.getEntriesByType('measure').length > 0"
```
