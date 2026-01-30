# Config Manager Script

The `config_manager.py` script automates creation and validation of playwright-cli configuration files for complex automation workflows.

## Quick Start

```bash
# Create a testing configuration
python scripts/config_manager.py create --type testing --output my-config.json

# Validate an existing configuration
python scripts/config_manager.py validate --input my-config.json

# View available templates
python scripts/config_manager.py template
```

## Commands

### Create Configurations

Generate pre-configured JSON files optimized for specific workflows.

```bash
# Default basic configuration
python scripts/config_manager.py create --type default --output config.json

# Session-specific configuration
python scripts/config_manager.py create --type session --session-name=user1 --output user1-config.json

# Testing optimization (with video, console, network logging)
python scripts/config_manager.py create --type testing --output testing-config.json

# Screenshot optimization (high-resolution viewport)
python scripts/config_manager.py create --type screenshot --output screenshot-config.json
```

### Validate Configurations

Check existing configuration files for correctness.

```bash
# Validate a configuration file
python scripts/config_manager.py validate --input my-config.json
```

Returns:
- `Configuration is valid` → File is correct, ready to use
- `Configuration is invalid` → Error details printed for fixes

### View Templates

Display available configuration templates and usage examples.

```bash
python scripts/config_manager.py template
```

## Configuration Templates

### Default

Basic configuration for general CLI use.

```json
{
  "browser": {
    "browserName": "chromium",
    "isolated": false,
    "launchOptions": {
      "headless": true
    },
    "contextOptions": {
      "viewport": { "width": 1280, "height": 720 }
    }
  },
  "outputDir": "./output",
  "outputMode": "file",
  "timeouts": {
    "action": 5000,
    "navigation": 30000
  },
  "testIdAttribute": "data-testid"
}
```

### Session

Session-specific configuration for isolated browser contexts (multi-user testing).

```json
{
  // Inherits from default config
  // Customize with session-specific settings
  "sessionName": "user1",
  "outputDir": "./output/user1"
}
```

### Testing

Optimized for test automation with video, console, and network logging.

```json
{
  // Inherits from default config
  "saveVideo": { "width": 1280, "height": 720 },
  "console": { "level": "info" },
  "network": {
    "allowedOrigins": ["*"],
    "blockedOrigins": []
  }
}
```

**Use cases**:
- E2E test workflows with video recording
- Debugging network requests
- Capturing console errors

### Screenshot

Optimized for high-resolution screenshots (1920x1080).

```json
{
  "browser": {
    "browserName": "chromium",
    "launchOptions": {
      "headless": true,
      "args": ["--window-size=1920,1080"]
    },
    "contextOptions": {
      "viewport": { "width": 1920, "height": 1080 }
    }
  },
  "outputDir": "./screenshots"
}
```

**Use cases**:
- Full-page screenshots for documentation
- Visual regression testing
- Cross-browser layout validation

## Workflow Examples

### Quick Testing Setup

```bash
# Generate testing config
python scripts/config_manager.py create --type testing --output testing.json

# Validate it
python scripts/config_manager.py validate --input testing.json

# Use it with CLI
playwright-cli --config testing.json open https://example.com
playwright-cli tracing-start
playwright-cli click e3
playwright-cli tracing-stop
```

### Multi-Session Testing

```bash
# Create configs for multiple users
python scripts/config_manager.py create --type session --session-name=user1 --output user1.json
python scripts/config_manager.py create --type session --session-name=user2 --output user2.json

# Validate all configs
python scripts/config_manager.py validate --input user1.json
python scripts/config_manager.py validate --input user2.json

# Run parallel sessions
playwright-cli --session=user1 --config user1.json open https://example.com
playwright-cli --session=user2 --config user2.json open https://example.com
```

### Screenshot Batch Job

```bash
# Generate high-res config
python scripts/config_manager.py create --type screenshot --output hires.json

# Validate
python scripts/config_manager.py validate --input hires.json

# Take screenshots
playwright-cli --config hires.json open https://example.com/page1
playwright-cli screenshot
playwright-cli --config hires.json open https://example.com/page2
playwright-cli screenshot
```

## Validation Rules

The script validates configurations against these rules:

- **Required**: `browser` object must exist
- **Required**: `browser.browserName` must be specified
- **Valid values**: browserName must be one of: `chromium`, `firefox`, `webkit`
- **JSON format**: File must be valid JSON

Invalid configurations print specific error messages. Example:

```bash
$ python scripts/config_manager.py validate --input bad.json
Missing required key: browser
Configuration is invalid
```

## Integration with Playwright CLI

Use generated configs with playwright-cli:

```bash
# Generate config
python scripts/config_manager.py create --type testing --output my-config.json

# Pass to CLI commands
playwright-cli --config my-config.json open https://example.com
playwright-cli --config my-config.json click e5
playwright-cli --config my-config.json screenshot
```

## Tips

- **Validate before use**: Always run `validate` after creating or modifying configs
- **Version control**: Commit config files to your repository for team consistency
- **Reuse templates**: Create custom templates by copying/modifying generated files
- **Profiles vs configs**: Use `profiles/` for device profiles (iPhone, Pixel, etc.); use config files for session-specific options
