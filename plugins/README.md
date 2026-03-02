# Plugins

Plugins are self-contained bundles of GitHub Copilot customization artifacts (agents, instructions, skills, hooks, tools) distributed as a single unit via the Copilot plugin system.

## Directory Layout

```
plugins/
  <name>/
    plugin.json          # Plugin manifest (required)
    agents/              # Agent files (optional)
    instructions/        # Instruction files (optional)
    skills/              # Skill directories (optional)
    hooks/               # Hook configs (optional)
    tools/               # Tool definitions (optional)
    config/              # Configuration files (optional)
    system.md            # System prompt (optional)
```

Each plugin lives in its own subdirectory under `plugins/`. The directory name should match the `name` field in `plugin.json`.

## plugin.json Schema

| Field | Required | Description |
|-------|----------|-------------|
| `name` | **Yes** | Plugin identifier (lowercase, hyphenated) |
| `description` | No | Human-readable description |
| `version` | No | Semantic version string |
| `author` | No | Author name or organization |
| `agents` | No | Relative path to agent files directory |
| `tools` | No | Relative path to tool definitions directory |
| `instructions` | No | Relative path to instruction files directory |
| `hooks` | No | Relative path to hooks directory |
| `config` | No | Relative path to configuration directory |
| `system` | No | Relative path to system prompt file |

Component path fields (`agents`, `tools`, `instructions`, `hooks`, `config`, `system`) use paths relative to the plugin directory.

## Installation

Install a plugin from a local directory:

```bash
copilot plugin install ./plugins/<name>
```

## Loading Precedence

When multiple sources define the same artifact, the first-found-wins rule applies:

1. **User-level** (`~/.copilot/`) — highest priority
2. **Project-level** (`.github/`) — repository-specific
3. **Parent directories** — walked upward from cwd

Plugins installed at the user level take precedence over project-level plugins.

## Relationship with Publish Scripts

Plugins **supplement** the existing publish-script workflow — they do not replace it.

- **Publish scripts** (`scripts/publish/publish-*.ps1`) remain the source of truth for distributing individual artifacts (agents, skills, instructions, hooks) to their standard platform-specific locations.
- **Plugins** bundle multiple artifacts into a single installable unit for distribution to other users or machines.

Use publish scripts for local development iteration. Use plugins for packaging and sharing complete workflows.

## Marketplace Publishing

Marketplace publishing for plugins is **deferred** to a future iteration. Currently, plugins are installed from local directories only.
