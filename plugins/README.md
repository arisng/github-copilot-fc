# Plugins

Plugins are self-contained bundles of GitHub Copilot CLI customization artifacts (agents, skills, commands, hooks, MCP servers, LSP servers) distributed as a single installable unit via the `copilot plugin` system.

## Directory Layout

```
plugins/
  <name>/
    plugin.json          # Plugin manifest (required)
    agents/              # Agent files (optional)
    skills/              # Skill directories (optional)
    commands/            # Command tool definitions (optional)
    hooks/               # Hook configs (optional)
```

Each plugin lives in its own subdirectory under `plugins/`. The directory name should match the `name` field in `plugin.json`.

## plugin.json Schema

### Metadata Fields

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `name` | **Yes** | — | Plugin identifier (lowercase, hyphenated) |
| `description` | No | — | Human-readable description |
| `version` | No | — | Semantic version string |
| `author` | No | — | Author name or organization |
| `license` | No | — | License identifier (e.g. `MIT`) |
| `homepage` | No | — | URL to plugin homepage |
| `bugs` | No | — | URL for issue reporting |
| `repository` | No | — | URL to source repository |
| `keywords` | No | — | Array of keyword strings for discovery |
| `strict` | No | `true` | Schema validation strictness — when `true`, unrecognized fields cause validation errors; when `false`, they are silently ignored |

### Component Path Fields

| Field | Type | Description |
|-------|------|-------------|
| `agents` | string or string[] | Relative path(s) to agent files |
| `skills` | string or string[] | Relative path(s) to skill directories |
| `commands` | string or string[] | Relative path(s) to command tool definitions |
| `hooks` | string or string[] | Relative path(s) to hook configurations |
| `mcpServers` | string or string[] | Relative path(s) to MCP server definitions |
| `lspServers` | string or string[] | Relative path(s) to LSP server definitions |

All component paths are relative to the plugin directory. These are the **only** 6 official component fields in the plugin.json schema.

> **Note:** `instructions` is NOT a plugin.json component field. Instruction files cannot be delivered via plugins. Use `scripts/publish/publish-instructions.ps1` for instruction distribution instead.

## Installation

Install a plugin from a local directory:

```bash
copilot plugin install ./plugins/<name>
```

The CLI **copies** (caches) the plugin contents — it does not create a symlink. To pick up local changes after editing, you must run `copilot plugin install` again.

## Where Plugins Are Stored

After installation, plugin files are cached on the local machine. The official documentation provides two slightly different path conventions:

| Source | Direct Install Path | Marketplace Install Path |
|--------|---------------------|--------------------------|
| [Reference docs](https://docs.github.com/en/copilot/reference/cli-plugin-reference#file-locations) | `~/.copilot/state/installed-plugins/<NAME>/` | `~/.copilot/state/installed-plugins/<MARKETPLACE>/<NAME>/` |
| [How-to docs](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-finding-installing#where-plugins-are-stored) | `~/.copilot/installed-plugins/_direct/<NAME>/` | `~/.copilot/installed-plugins/<MARKETPLACE>/<NAME>/` |

Key differences between the two official sources:
- **`state/` prefix**: Reference docs include it; how-to docs do not.
- **`_direct/` subdirectory**: How-to docs use it for direct installs; reference docs do not.

Marketplace cache (reference docs): `~/.copilot/state/marketplace-cache/`

> **⚠️** These paths are documented as-is from official GitHub docs (March 2026). The inconsistency has not been resolved upstream. Verify against your local installation if exact paths matter.

On Windows, `~` resolves to `%USERPROFILE%` (e.g. `C:\Users\<user>\.copilot\...`).

## Loading Precedence

When multiple sources define the same artifact, the loading order is:

1. **User-level** (`~/.copilot/`) — highest priority
2. **Project-level** (`.github/`) — repository-specific
3. **Parent directories** — walked upward from cwd
4. **Plugin components** — from installed plugins
5. **Remote/organization** — org-level policies

Plugins load after local user and project customizations, so local overrides always take precedence.

## Relationship with Publish Scripts

Plugins **supplement** the existing publish-script workflow — they do not replace it.

- **Publish scripts** (`scripts/publish/publish-*.ps1`) remain the source of truth for distributing individual artifacts (agents, skills, instructions, hooks) to their standard platform-specific locations.
- **Plugins** bundle multiple artifacts into a single installable unit for distribution to other users or machines.

Use publish scripts for local development iteration. Use plugins for packaging and sharing complete workflows.

## Instruction Delivery

The `instructions` field is **not** part of the `plugin.json` schema. The Copilot CLI has no plugin-based instruction loading path — the [loading order](https://docs.github.com/en/copilot/reference/cli-plugin-reference) resolves instructions from `AGENTS.md`, `~/.copilot/copilot-instructions.md`, `COPILOT_CUSTOM_INSTRUCTIONS_DIRS`, and project `.github/copilot-instructions.md`, but never from installed plugins.

**Implication:** If your plugin's agents rely on shared instruction files (e.g., `.instructions.md` files for orchestration logic), those instruction files must be delivered separately.

**Workaround:** Use `scripts/publish/publish-instructions.ps1` alongside `scripts/publish/publish-plugins.ps1` to distribute instruction files to the standard CLI instruction paths.

For workspace plugins like `ralph-v2`, this means the publish workflow is:

1. `publish-plugins.ps1 -Bundle` — bundles and installs agent/skill/hook components
2. `publish-instructions.ps1` — copies instruction files to `~/.copilot/` or the configured instruction directory

## Marketplace Publishing

Marketplace publishing for plugins is **deferred** to a future iteration. Currently, plugins are installed from local directories only.
