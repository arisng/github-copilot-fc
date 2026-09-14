# Plugin Marketplace Guide

## What Are Marketplaces?

Marketplaces are GitHub repositories with a `.github/plugin/marketplace.json` file. They serve as registries where users can browse and install plugins.

## Creating a Marketplace

Create `.github/plugin/marketplace.json` in your repo:

```json
{
  "name": "my-marketplace",
  "owner": {
    "name": "Your Organization",
    "email": "plugins@example.com"
  },
  "metadata": {
    "description": "Curated plugins for our team",
    "version": "1.0.0"
  },
  "plugins": [
    {
      "name": "frontend-design",
      "description": "Create professional GUIs",
      "version": "2.1.0",
      "source": "./plugins/frontend-design"
    },
    {
      "name": "security-checks",
      "description": "Check for security vulnerabilities",
      "version": "1.3.0",
      "source": "./plugins/security-checks"
    }
  ]
}
```

### Marketplace Schema Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Marketplace identifier |
| `owner` | object | Yes | `{ name, email }` |
| `metadata` | object | Yes | `{ description, version }` |
| `plugins` | array | Yes | List of plugin entries |

### Plugin Entry Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Plugin name |
| `description` | string | No | Short description |
| `version` | string | Yes | SemVer version |
| `source` | string | Yes | Relative path to plugin directory |

## Built-in Marketplaces

| Marketplace | Repository |
|-------------|------------|
| `copilot-plugins` | [github/copilot-plugins](https://github.com/github/copilot-plugins) |
| `awesome-copilot` | [github/awesome-copilot](https://github.com/github/awesome-copilot) |

## CLI Commands

### Register a Marketplace

```bash
copilot plugin marketplace add OWNER/REPO
```

### List Registered Marketplaces

```bash
copilot plugin marketplace list
```

### Browse Marketplace Plugins

```bash
copilot plugin marketplace browse my-marketplace
```

### Refresh Marketplace Index

```bash
copilot plugin marketplace update my-marketplace
```

### Unregister a Marketplace

```bash
copilot plugin marketplace remove my-marketplace
```

## Installing from Marketplaces

```bash
# Install from a marketplace
copilot plugin install my-plugin@my-marketplace

# Install from GitHub repo
copilot plugin install OWNER/REPO

# Install from subdirectory in repo
copilot plugin install OWNER/REPO:PATH/TO/PLUGIN

# Install from Git URL
copilot plugin install https://github.com/o/r.git

# Install from local path
copilot plugin install ./my-plugin
```

## Distributing Your Plugin

1. **Add your plugin to a marketplace repo** (or create your own)
2. **Users register the marketplace:**
   ```bash
   copilot plugin marketplace add OWNER/REPO
   ```
3. **Users browse and install:**
   ```bash
   copilot plugin marketplace browse my-marketplace
   copilot plugin install my-plugin@my-marketplace
   ```

## Plugin Management Commands

| Command | Description |
|---------|-------------|
| `copilot plugin install SPECIFICATION` | Install a plugin |
| `copilot plugin uninstall NAME` | Remove a plugin |
| `copilot plugin list [--json]` | List installed plugins |
| `copilot plugin update NAME [--all]` | Update plugin(s) |
| `copilot plugin enable NAME` | Enable a disabled plugin |
| `copilot plugin disable NAME` | Disable without uninstall |

## In-Session Commands

| Command | Description |
|---------|-------------|
| `/plugin list` | View installed plugins |
| `/plugin install PLUGIN@MARKETPLACE` | Install from session |
| `/agent` | Check loaded agents |
| `/skills list` | View loaded skills |
