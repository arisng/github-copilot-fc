---
name: playwright-cli
description: Automates browser interactions for web testing, form filling, screenshots, and data extraction. Use when the user needs to navigate websites, interact with web pages, fill forms, take screenshots, test web applications, or extract information from web pages.
allowed-tools: Bash(playwright-cli:*)
version: 2.0.0
---

# Browser Automation with playwright-cli

## Quick start

```bash
playwright-cli --config profiles/chromium.json open https://example.com
playwright-cli snapshot
playwright-cli click e3
playwright-cli fill e5 "user@example.com"
playwright-cli press Enter
```

**Note on Blazor apps**: For Interactive Server render mode, Playwright auto-waits for the SignalR circuit. The next command after an interaction (like click) will wait for the server to process. See [BLAZOR_TESTING.md](references/BLAZOR_TESTING.md) for timing strategies.

## Core workflow

1. **Navigate**: `playwright-cli --config profiles/chromium.json open https://example.com`
2. **Interact**: Use element references from the snapshot (e.g., `e3`, `e5`)
3. **Inspect**: Re-snapshot after significant changes to see the DOM
4. **Always profile-first**: Use explicit profiles from `profiles/` (default: `chromium.json`)
5. **Mobile-first testing**: Start with device profiles (`iphone15`, `pixel7`) for responsive validation

## When to use

- **POC/Exploratory**: Manual testing, debugging, form filling, data extraction
- **Production**: Use E2E scripts instead (Playwright Test Framework)
- **Hybrid**: Explore with CLI, then convert to scripts for automation

For detailed decision guidance, see [BOUNDARIES.md](references/BOUNDARIES.md).

## Command reference

All Playwright CLI commands organized by type:

- [**COMMANDS.md**](references/COMMANDS.md) - Core, navigation, keyboard, mouse, save, tabs, DevTools
- [**CONFIGURATION.md**](references/CONFIGURATION.md) - Profiles, HTTPS/SSL, sessions, config manager script
- [**WORKFLOWS.md**](references/WORKFLOWS.md) - Form submission, multi-tab, debugging, responsive testing examples
- [**BLAZOR_TESTING.md**](references/BLAZOR_TESTING.md) - Blazor Interactive Server with SignalR, readiness signals, best practices

## E2E scripts & integration

Playwright CLI complements code-based E2E test scripts. When to integrate:

- **Exploratory Testing**: Use CLI for manual flows before scripting
- **Debugging Failures**: Reproduce script issues interactively
- **Prototyping**: Quick validations or data setup
- **CI/CD**: Pre-checks or parallel sessions alongside suites

See [**INTEGRATION.md**](references/INTEGRATION.md) for 10 solid workflows, best practices, and hybrid approach patterns.

## Glossary & boundaries

- [**GLOSSARY.md**](references/GLOSSARY.md) - Domain terminology (assertions, E2E, flaky tests, etc.)
- [**BOUNDARIES.md**](references/BOUNDARIES.md) - POC vs Production decision matrix and rules
