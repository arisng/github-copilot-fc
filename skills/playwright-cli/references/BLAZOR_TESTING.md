# Testing Blazor Apps with Interactive Server Render Mode

Playwright CLI testing for Blazor Interactive Server apps with SignalR requires understanding WebSocket connections, prerendering, and readiness signals.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Key Timing Challenges](#key-timing-challenges)
- [Readiness Signals](#readiness-signals)
- [Best Practices](#best-practices)
- [Workflow Examples](#workflow-examples)

## Architecture Overview

Blazor Interactive Server (`InteractiveServer` render mode):
- **Prerendering**: Content initially renders statically on the server (HTML sent immediately)
- **SignalR Circuit**: Real-time connection established after prerender (via WebSocket)
- **Interactivity**: UI interactions processed on server after circuit is active
- **Two phases**:
  1. **Prerender phase**: Static HTML rendered immediately (~100-500ms)
  2. **Interactive phase**: SignalR circuit established, event handlers active (~200-1000ms)

### Phases Visualization

```txt
Request → Prerender (Static HTML) → SignalR Circuit (WebSocket) → Fully Interactive
         ↓                          ↓                              ↓
    Page loads instantly    Click handlers ready           Complex interactions work
```

## Key Timing Challenges

### Challenge 1: Clicking Before Circuit Established

❌ **Problem**: Clicking element before SignalR circuit is ready causes interaction to fail silently or queue and fail.

```bash
# BAD: May click before circuit ready
playwright-cli --config profiles/chromium.json open https://example.com/blazor-page
playwright-cli click e3  # Fails if circuit not established yet
```

### Challenge 2: Form Submission on Static-Rendered Forms

❌ **Problem**: Forms rendered during prerender require `FormName` parameter and may not accept submissions until interactive.

```bash
# BAD: Form submission fails on prerendered form
playwright-cli fill e1 "test"
playwright-cli click e2  # Form submission may be lost
```

### Challenge 3: Dynamic Content Rendering

❌ **Problem**: Server-rendered content updates don't arrive immediately; must wait for signaling.

```bash
# BAD: Content may not appear immediately after action
playwright-cli click e3
playwright-cli snapshot  # DOM not yet updated
```

## Readiness Signals

### Strategy 1: Wait for Specific Elements (Recommended)

After clicking interactive elements, explicitly wait for expected changes in the DOM.

```bash
# GOOD: Wait for element to appear after interaction
playwright-cli --config profiles/chromium.json open https://example.com/blazor-page
playwright-cli snapshot  # Get baseline

# Wait for interactive circuit with element presence
playwright-cli click e3
# Playwright auto-waits for visibility in next command:
playwright-cli eval "el => el.textContent" e5  # Waits for e5 to be ready
```

### Strategy 2: Network Readiness

Monitor network activity to detect when SignalR connection is established.

```bash
# Check network for SignalR WebSocket establishment
playwright-cli network  # View WebSocket connections
# Look for: WebSocket to /blazor endpoint
```

### Strategy 3: Custom Readiness Indicators

If app includes readiness indicators, use them to signal interactivity.

```bash
# App may add data-interactive="true" or similar indicator
playwright-cli eval "document.querySelector('[data-interactive]')" 
# Returns element if interactive; null otherwise
```

## Best Practices

### 1. Always Wait After Page Load

Blazor Interactive Server pages need time for the SignalR circuit to establish after navigation.

```bash
# GOOD: Wait for page to fully load after navigation
playwright-cli --config profiles/chromium.json open https://example.com/blazor-page
playwright-cli snapshot

# Wait briefly for prerender + SignalR circuit (1-2 seconds typical)
# Use eval to detect readiness before interacting
playwright-cli eval "document.readyState"  # Waits for document ready
```

### 2. Prefer Element Visibility Over Time Delays

Instead of arbitrary delays, wait for elements to be ready.

```bash
# GOOD: Wait for specific interactive element
playwright-cli click e3
# Next command auto-waits for element to be interactive
playwright-cli fill e5 "input"  # Waits for e5 to be present/visible

# BAD: Arbitrary delay
# playwright-cli pause 2000
# (unpredictable, flaky, slow)
```

### 3. Test Circuit Reconnection

Blazor handles reconnection; test that interactions resume after temporary disconnection.

```bash
# Simulate slow/flaky connection with tracing
playwright-cli tracing-start
playwright-cli click e3  # May trigger reconnect if slow
playwright-cli fill e5 "test"  # Should complete after reconnect
playwright-cli tracing-stop
```

### 4. Validate Form Handling

Forms on prerendered pages require specific handling.

```bash
# Forms must include FormName parameter for submission
# Test typical form flow
playwright-cli snapshot  # See form fields

playwright-cli fill e1 "user@example.com"
playwright-cli fill e2 "password"
playwright-cli click e3  # Submit button
playwright-cli snapshot  # Verify success response
```

### 5. Test With Multiple Profiles

Blazor interactivity depends on client capabilities; test across profiles.

```bash
# Desktop (fast circuit establishment)
playwright-cli --config profiles/chromium.json open https://example.com

# Mobile (slower circuit, test touch)
playwright-cli --config profiles/iphone15.json open https://example.com

# Slow connection (test timeout/reconnect)
playwright-cli --config profiles/pixel7.json open https://example.com
```

## Workflow Examples

### Simple Click & Verify

```bash
# Navigate to Blazor page with interactive button
playwright-cli --config profiles/chromium.json open https://example.com/counter
playwright-cli snapshot

# Click button (waits for circuit + click processing)
playwright-cli click e3
playwright-cli snapshot  # Verify counter incremented
```

### Form Submission

```bash
# Navigate to form
playwright-cli --config profiles/chromium.json open https://example.com/form
playwright-cli snapshot

# Fill and submit form
playwright-cli fill e1 "user@example.com"
playwright-cli fill e2 "password"
playwright-cli click e3  # Submit

# Verify response page
playwright-cli snapshot
playwright-cli eval "document.body.innerText" | grep "success"
```

### Complex Interaction Chain

```bash
# Multi-step interactive workflow
playwright-cli --config profiles/chromium.json open https://example.com/app
playwright-cli snapshot

# Step 1: Click button (circuit may still establishing)
playwright-cli click e3
# Playwright waits for next command to auto-detect readiness

# Step 2: Verify result and continue
playwright-cli snapshot
playwright-cli click e5  # Next interaction

# Step 3: Fill dynamic form
playwright-cli fill e7 "input"
playwright-cli click e8  # Submit

# Step 4: Verify final state
playwright-cli snapshot
```

### Debugging Flaky Interactions

```bash
# If interactions fail intermittently:

# 1. Capture full trace
playwright-cli tracing-start
playwright-cli click e3
playwright-cli snapshot
playwright-cli tracing-stop

# 2. Check console for errors
playwright-cli console

# 3. Check network (WebSocket status)
playwright-cli network

# 4. Verify circuit is active
playwright-cli eval "window.Blazor"  # Should exist if Blazor JS loaded
```

## Timeout Recommendations

| Operation           | Timeout | Notes                     |
| ------------------- | ------- | ------------------------- |
| Page navigation     | 30s     | Normal web load           |
| Prerender + circuit | 2-3s    | Typical SignalR init      |
| Click processing    | 1-2s    | Server-side event handler |
| Form submission     | 3-5s    | Validation + processing   |
| Dynamic content     | 2-3s    | Network + rendering       |

**Default**: Playwright waits 30 seconds for visibility/stability. Blazor typically completes within 2-3 seconds, so defaults are safe.

## Common Issues & Solutions

| Issue                  | Cause                               | Solution                                       |
| ---------------------- | ----------------------------------- | ---------------------------------------------- |
| Click has no effect    | Circuit not ready                   | Verify element with eval before clicking       |
| Form submission fails  | Prerendered form + missing FormName | Check form has FormName parameter              |
| Content doesn't update | Waiting for network                 | Use next command to auto-detect; check tracing |
| Reconnection loops     | Connection issue                    | Check network in tracing; verify server health |
| Timeout on interaction | Slow server                         | Increase timeout or check server logs          |

## Resources

- [ASP.NET Core Blazor SignalR guidance](https://learn.microsoft.com/en-us/aspnet/core/blazor/fundamentals/signalr?view=aspnetcore-10.0)
- [Blazor render modes](https://learn.microsoft.com/en-us/aspnet/core/blazor/components/render-modes?view=aspnetcore-10.0)
- [Prerendering in Blazor](https://learn.microsoft.com/en-us/aspnet/core/blazor/components/prerender?view=aspnetcore-10.0)
