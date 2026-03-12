# Common Workflows & Examples

Practical examples for typical Playwright CLI workflows.

## Form Submission

Fill out and submit a form.

```bash
playwright-cli --config profiles/chromium.json open https://example.com/form
playwright-cli snapshot

playwright-cli fill e1 "user@example.com"
playwright-cli fill e2 "password123"
playwright-cli click e3
playwright-cli snapshot
```

### Tips

- Use `snapshot` after opening to identify element references
- `fill` works better than `type` for form fields
- Snapshot after submit to verify the result

## Multi-Tab Workflow

Work across multiple browser tabs.

```bash
playwright-cli --config profiles/chromium.json open https://example.com
playwright-cli snapshot

playwright-cli tab-new https://example.com/other
playwright-cli tab-list

playwright-cli tab-select 0
playwright-cli snapshot

playwright-cli tab-close 1
```

### Tips

- Use `tab-list` to see all open tabs
- Tab selection is 0-indexed
- Each tab maintains its own context and navigation history

## Debugging with DevTools

Inspect network requests, console output, and execution traces.

### Console Inspection

```bash
playwright-cli open https://example.com
playwright-cli click e4
playwright-cli fill e7 "test"
playwright-cli console              # View all console messages
playwright-cli console warning      # View only warnings
```

### Network Monitoring

```bash
playwright-cli open https://example.com
playwright-cli network              # View network activity
playwright-cli click e4             # Trigger network request
```

### Execution Tracing

```bash
playwright-cli open https://example.com
playwright-cli tracing-start
playwright-cli click e4
playwright-cli fill e7 "test"
playwright-cli tracing-stop
```

Traces capture detailed network and execution information useful for debugging flaky tests or understanding app behavior.

## Data Extraction

Extract information from the page using evaluation.

```bash
# Get page title
playwright-cli eval "document.title"

# Get element text content
playwright-cli eval "el => el.textContent" e5

# Get multiple values
playwright-cli eval "() => Array.from(document.querySelectorAll('[data-testid]')).map(el => el.textContent)"
```

### Tips

- Use `eval` for JavaScript execution in page context
- Pass element references like `e5` to inspect specific elements
- Complex queries should be wrapped in arrow functions

## Screenshot & PDF Capture

Save visual artifacts for documentation or reporting.

```bash
# Full page screenshot
playwright-cli screenshot

# Element-specific screenshot
playwright-cli screenshot e5

# PDF export
playwright-cli pdf
```

### Tips

- Useful for visual regression testing
- PDFs help with documentation and archiving
- Screenshots are saved to the working directory by default

## Responsive UI Testing (Mobile-First Strategy)

Validate responsive layouts and mobile interactions using device profiles.

### Desktop → Mobile Testing Sequence

**Step 1: Start with mobile baseline (mobile-first)**

```bash
playwright-cli --config profiles/iphone15.json open https://example.com
playwright-cli snapshot
playwright-cli click e3  # Tap hamburger menu on mobile
playwright-cli snapshot
```

**Step 2: Test touch interactions**

```bash
# Test touch-specific interactions on iPhone
playwright-cli --config profiles/iphone15.json open https://example.com
playwright-cli click e5  # Simulates tap (not hover)
playwright-cli hover e7  # Falls back to non-hover behavior on mobile
playwright-cli screenshot
```

**Step 3: Test Android variant (Pixel 7)**

```bash
playwright-cli --config profiles/pixel7.json open https://example.com
playwright-cli snapshot
playwright-cli click e3  # Verify Android-specific behavior
playwright-cli screenshot
```

**Step 4: Verify desktop expansion**

```bash
# Desktop should show full UI; mobile should show simplified layout
playwright-cli --config profiles/chromium.json open https://example.com
playwright-cli resize 1920 1080
playwright-cli snapshot
```

### Mobile-First Tips

- **Start with mobile**: Always begin responsive testing on mobile profiles first
- **Touch vs Hover**: Mobile profiles disable hover; test fallback interactions
- **Viewport accuracy**: Device profiles set precise viewports (e.g., 375x667 for iPhone)
- **User Agent detection**: Profiles include correct User Agents; test UA-gated code paths
- **Device pixel ratio**: Profiles simulate correct DPR for crisp rendering
- **Visual breakpoints**: Take screenshots at each breakpoint to verify layout shifts
- **Orientation testing**: Device profiles default to portrait; use `resize` for landscape

### Quick Cross-Device Validation

```bash
# Full responsive check: ~4 minutes across three platforms

# iPhone 15 (1-2 min)
playwright-cli --config profiles/iphone15.json open https://example.com
playwright-cli snapshot
playwright-cli click e3

# Pixel 7 (1 min)
playwright-cli --config profiles/pixel7.json open https://example.com
playwright-cli snapshot

# Desktop Chromium (1 min)
playwright-cli --config profiles/chromium.json open https://example.com
playwright-cli snapshot
```

## Dialog Handling

Interact with browser dialogs and alerts.

```bash
# Accept a confirmation dialog
playwright-cli dialog-accept

# Accept with specific text matching
playwright-cli dialog-accept "confirmation text"

# Dismiss a dialog
playwright-cli dialog-dismiss
```

### Tips

- Use when testing alert() or confirm() interactions
- Check console for dialog content before accepting/dismissing
