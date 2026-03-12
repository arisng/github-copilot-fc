# Playwright CLI Commands Reference

All available commands organized by category.

## Table of Contents
- [Core](#core)
- [Navigation](#navigation)
- [Keyboard](#keyboard)
- [Mouse](#mouse)
- [Save As](#save-as)
- [Tabs](#tabs)
- [Sessions](#sessions)
- [DevTools](#devtools)
- [Configuration](#configuration)

## Core

Fundamental interactions with page elements.

```bash
playwright-cli open https://example.com/
playwright-cli close
playwright-cli type "search query"
playwright-cli click e3
playwright-cli dblclick e7
playwright-cli fill e5 "user@example.com"
playwright-cli drag e2 e8
playwright-cli hover e4
playwright-cli select e9 "option-value"
playwright-cli upload ./document.pdf
playwright-cli check e12
playwright-cli uncheck e12
playwright-cli snapshot
playwright-cli eval "document.title"
playwright-cli eval "el => el.textContent" e5
playwright-cli dialog-accept
playwright-cli dialog-accept "confirmation text"
playwright-cli dialog-dismiss
playwright-cli resize 1920 1080
```

## Navigation

Page navigation commands.

```bash
playwright-cli go-back
playwright-cli go-forward
playwright-cli reload
```

## Keyboard

Keyboard interactions.

```bash
playwright-cli press Enter
playwright-cli press ArrowDown
playwright-cli press ArrowUp
playwright-cli press Escape
playwright-cli keydown Shift
playwright-cli keyup Shift
```

## Mouse

Mouse interactions and positioning.

```bash
playwright-cli mousemove 150 300
playwright-cli mousedown
playwright-cli mousedown right
playwright-cli mouseup
playwright-cli mouseup right
playwright-cli mousewheel 0 100
```

## Save As

Capturing and saving content.

```bash
playwright-cli screenshot
playwright-cli screenshot e5
playwright-cli pdf
```

## Tabs

Multi-tab management.

```bash
playwright-cli tab-list
playwright-cli tab-new
playwright-cli tab-new https://example.com/page
playwright-cli tab-close
playwright-cli tab-close 2
playwright-cli tab-select 0
```

## Sessions

Session management for persistent state.

```bash
playwright-cli --session=mysession open example.com
playwright-cli --session=mysession click e6
playwright-cli session-list
playwright-cli session-stop mysession
playwright-cli session-stop-all
playwright-cli session-delete
playwright-cli session-delete mysession
```

## DevTools

Debugging and inspection tools.

```bash
playwright-cli console
playwright-cli console warning
playwright-cli network
playwright-cli run-code "async page => await page.context().grantPermissions(['geolocation'])"
playwright-cli tracing-start
playwright-cli tracing-stop
```

## Configuration

Session and browser setup.

```bash
# Configure the session
playwright-cli config my-config.json

# Configure named session
playwright-cli --session=mysession config my-config.json

# Start with configured session
playwright-cli open --config=my-config.json

# Preferred default for agents (profile-first)
playwright-cli open --config=profiles/chromium.json
```
