# Configuration Profiles & Setup

## Table of Contents

- [Configuration Profiles](#configuration-profiles)
- [Path Resolution](#path-resolution)
- [Available Profiles](#available-profiles)
- [HTTPS/SSL for localhost](#httpssl-for-localhost)
- [Sessions Management](#sessions-management)

## Configuration Profiles

Use the pre-defined profiles in the `profiles/` directory for common testing scenarios like cross-browser and cross-device coverage. These high-fidelity profiles simulate exact platforms and devices (User Agent, viewport, device pixel ratio, and touch support) so E2E runs match real environments and keep cross-browser and cross-platform testing consistent.

**Key Principle**: Always run Playwright CLI with an explicit profile from `profiles/`. For agent-driven workflows, default to `profiles/chromium.json` unless the user requests a specific browser or device.

### Tips for profiles

- **Mobile-first approach**: Start testing on mobile profiles (`iphone15`, `pixel7`) before desktop
- **Responsive validation**: Use device profiles to verify responsive layouts and breakpoints
- **Touch interactions**: Mobile profiles enable touch support; test tap alternatives to hover
- **UA-gated code**: Profiles include correct User Agents; verify code paths specific to browsers/devices
- **Viewport precision**: Device profiles set accurate viewports and device pixel ratios
- **Maintain consistency**: Reuse profiles between CLI and E2E scripts for matching environments

## Path Resolution

All configuration file paths (e.g., `profiles/chromium.json`) are resolved relative to the skill's root directory at runtime. This ensures that profiles work correctly regardless of where the skill is published (Windows personal folders or WSL).

When using the playwright-cli tool, paths are automatically resolved based on the tool's execution context.

## Available Profiles

```bash
# Desktop browsers
playwright-cli --config profiles/chromium.json open https://example.com    # Baseline
playwright-cli --config profiles/firefox.json open https://example.com    # Firefox compatibility
playwright-cli --config profiles/webkit.json open https://example.com     # Safari compatibility

# Mobile devices
playwright-cli --config profiles/iphone15.json open https://example.com    # iPhone 15
playwright-cli --config profiles/pixel7.json open https://example.com     # Pixel 7
```

### Available profiles

- **chromium** (default baseline)
- **firefox** (compatibility pass)
- **webkit** (Safari equivalent)
- **iphone15** (responsive + touch checks)
- **pixel7** (Android responsive + touch checks)

## HTTPS/SSL for localhost

If your app uses a self-signed certificate on `https://localhost`, handle SSL verification to avoid browser blocking.

### Option 1: Trust the localhost certificate (recommended)

```bash
dotnet dev-certs https --trust
```

This permanently trusts the local certificate and is the simplest approach for development.

### Option 2: Ignore HTTPS errors in Playwright

Use a config file and set `browser.contextOptions.ignoreHTTPSErrors: true`:

```json
{
  "browser": {
    "browserName": "chromium",
    "contextOptions": {
      "ignoreHTTPSErrors": true
    }
  }
}
```

Then run:

```bash
playwright-cli config my-config.json
playwright-cli open --config=my-config.json https://localhost:5001
```

**Note**: This approach only ignores SSL errors but doesn't validate the certificate. Use it if you can't trust the certificate locally.

## Sessions Management

Sessions provide isolated browser contexts for maintaining state across multiple commands.

```bash
# Start a named session
playwright-cli --session=mysession open example.com

# Use the session for subsequent commands
playwright-cli --session=mysession click e6
playwright-cli --session=mysession fill e5 "user@example.com"

# List all active sessions
playwright-cli session-list

# Stop a specific session
playwright-cli session-stop mysession

# Stop all sessions
playwright-cli session-stop-all

# Delete session data
playwright-cli session-delete mysession
```

### When to use sessions

- Multi-user testing scenarios
- Parallel testing with different user contexts
- Complex workflows requiring session state
- Testing session/auth interactions

## Config Manager Script

The `config_manager.py` script automates creation and validation of configuration files for complex workflows.

```bash
# Create a testing configuration
python scripts/config_manager.py create --type testing --output testing.json

# Validate an existing configuration
python scripts/config_manager.py validate --input my-config.json

# View available templates
python scripts/config_manager.py template
```

For detailed usage, see [**CONFIG_MANAGER.md**](CONFIG_MANAGER.md) with templates for default, session, testing, and screenshot workflows.

## Advanced Reference

For complete technical details, see:

- [**configuration-schema.md**](configuration-schema.md) - Full TypeScript schema for config file structure
- [**environment-variables.md**](environment-variables.md) - Complete environment variable reference (40+ options)
