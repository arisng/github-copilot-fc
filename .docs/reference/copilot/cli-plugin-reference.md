# CLI Plugin Reference

> **Last verified**: GA v0.0.420 (February 2026)
> **Related**: [About CLI Plugins](../../explanation/copilot/about-cli-plugins.md) · [How to Create a CLI Plugin](../../how-to/copilot/how-to-create-cli-plugin.md) · [Customization Matrix](copilot-cli-customization-matrix.md)

This reference documents the `plugin.json` manifest schema, CLI commands, installation spec patterns, directory conventions, and loading precedence for GitHub Copilot CLI plugins.

---

## References (Official Documentation)

Periodically verify against the official documentation to ensure accuracy, as the CLI is rapidly evolving and may have discrepancies or silent changes:
([GitHub Copilot CLI plugin reference](https://docs.github.com/en/copilot/reference/cli-plugin-reference))

## Directory Conventions

### Workspace Layout

Plugins are authored in the workspace under runtime-scoped roots at the repository root:

```
plugins/
  cli/
    .build/              # Runtime-scoped bundle output
    <name>/
      plugin.json        # CLI plugin manifest (required)
  vscode/
    .build/              # Runtime-scoped bundle output
    <name>/
      plugin.json        # VS Code plugin manifest (required)
```

The directory name should match the `name` field in `plugin.json`. Build and publish scripts emit per-plugin bundles under `plugins/<runtime>/.build/<name>/`; that child directory is the publish unit.

### File Locations

`plugin.json` can be placed at three locations within a repository:

| Location | Use Case |
|----------|----------|
| `plugins/cli/<name>/plugin.json` | Workspace-authored CLI plugins |
| `plugins/vscode/<name>/plugin.json` | Workspace-authored VS Code plugins |
| `.github/plugin/plugin.json` | Repository-level plugin for marketplace listing |
| `.claude-plugin/plugin.json` | Alternative convention (Claude-origin) |

For workspace plugins, use the runtime-scoped `plugins/<runtime>/<name>/plugin.json` convention. The `.github/plugin/` convention is for repositories that ARE plugin marketplaces.

---

## plugin.json Schema

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Plugin identifier. Must be lowercase, hyphenated (kebab-case), max 64 characters. |

### Optional Metadata Fields

| Field | Type | Description |
|-------|------|-------------|
| `description` | string | Human-readable description of the plugin's purpose. |
| `version` | string | Semantic version string (e.g., `"1.0.0"`). |
| `author` | string \| object | Author name or `{ "name": "...", "email": "...", "url": "..." }`. |
| `license` | string | SPDX license identifier (e.g., `"MIT"`). |
| `homepage` | string | URL to the plugin's homepage or documentation. |
| `bugs` | string \| object | URL or `{ "url": "...", "email": "..." }` for bug reports. |
| `repository` | string \| object | URL or `{ "type": "git", "url": "..." }` for the source repository. |
| `keywords` | array | Array of strings for searchability (e.g., `["orchestration", "agents"]`). |
| `strict` | boolean | If `true` (default), plugin validation rejects unknown fields in `plugin.json`. Set to `false` to allow forward-compatible metadata. Default: `true`. |

### Component Path Fields

Component paths are relative to the plugin directory and point to the resources the plugin bundles:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `agents` | string | `"agents/"` | Path to `.agent.md` files. |
| `skills` | string | `"skills/"` | Path to skill directories. |
| `commands` | string | `"commands/"` | Path to command tool definitions. |
| `hooks` | string | `"hooks/"` | Path to hooks configuration file or directory. |
| `mcpServers` | string | `"mcpServers/"` | Path to MCP server definitions. |
| `lspServers` | string | `"lspServers/"` | Path to LSP server definitions. |

> **Note:** Component paths can point outside the plugin directory using relative paths (e.g., `"../../agents/ralph-v2/cli/"`) for workspace-internal plugins that reference existing artifacts. For distributed plugins, all components should be self-contained within the plugin directory.
>
> **Instruction delivery limitation:** `instructions` is NOT an official component path field. Plugins cannot deliver `.instructions.md` files through the plugin loading mechanism. For instruction delivery strategies, see [About CLI Plugins](../../explanation/copilot/about-cli-plugins.md).

### Example: Minimal Manifest

```json
{
  "name": "my-plugin"
}
```

### Example: Full Manifest

```json
{
  "name": "ralph-v2",
  "description": "Multi-agent session orchestration system for Copilot CLI",
  "version": "1.0.0",
  "author": "github-copilot-fc",
  "license": "MIT",
  "keywords": ["orchestration", "agents", "multi-agent"],
  "agents": "agents/",
  "skills": "skills/",
  "hooks": "hooks/"
}
```

See the workspace pilot plugin at [plugins/cli/ralph-v2/plugin.json](../../../plugins/cli/ralph-v2/plugin.json) for a real-world example.

---

## CLI Commands

All plugin commands use `copilot plugin` from the shell.

### Installation & Management

| Command | Description |
|---------|-------------|
| `copilot plugin install <spec>` | Install a plugin from a local path, GitHub URL, or marketplace. See [Install Spec Patterns](#install-spec-patterns). |
| `copilot plugin uninstall <name>` | Remove an installed plugin and its components. |
| `copilot plugin list` | List all installed plugins and their status (enabled/disabled). |
| `copilot plugin update <name>` | Update a plugin to the latest version from its original source. |
| `copilot plugin enable <name>` | Re-enable a previously disabled plugin. |
| `copilot plugin disable <name>` | Temporarily disable a plugin without uninstalling it. Components are not loaded until re-enabled. |

### Marketplace Subcommands

| Command | Description |
|---------|-------------|
| `copilot plugin marketplace add <repo>` | Register a plugin marketplace repository. |
| `copilot plugin marketplace remove <name>` | Unregister a marketplace. |
| `copilot plugin marketplace list` | List registered marketplaces. |
| `copilot plugin marketplace browse <name>` | Browse plugins available in a marketplace. |

> **Commands that do NOT exist:** `validate`, `create`, `publish`, `show`, `search` are not official `copilot plugin` subcommands. Do not reference them.

### Shell Examples

```bash
copilot plugin install ./plugins/cli/ralph-v2
copilot plugin list
copilot plugin uninstall ralph-v2
copilot plugin marketplace list
```

---

## Install Spec Patterns

The `copilot plugin install` command accepts multiple source formats:

| Pattern | Example | Description |
|---------|---------|-------------|
| Local path | `./plugins/cli/ralph-v2` | Install from a local directory containing `plugin.json`. |
| GitHub URL | `github.com/owner/repo:plugins/cli/name` | Install directly from a GitHub repository path. |
| `@owner/name` | `@copilot-fc/ralph-v2` | Install from a registered marketplace. |
| `@owner/name@version` | `@copilot-fc/ralph-v2@1.0.0` | Install a specific version from marketplace. |

Additional marketplaces can be registered via `copilot plugin marketplace add`.

> **Note:** Marketplace publishing is **deferred** to a future iteration. Currently, local path and GitHub URL installs are the primary distribution methods. See [About CLI Plugins](../../explanation/copilot/about-cli-plugins.md) for marketplace ecosystem status.

---

## Install Paths

Plugin files are **copied** (cached) on install — not symlinked. To pick up local changes, reinstall with `copilot plugin install`.

| Source | Install Path |
|--------|--------------|
| Direct install (reference page) | `~/.copilot/state/installed-plugins/<NAME>/` |
| Direct install (how-to page) | `~/.copilot/installed-plugins/_direct/<NAME>/` |
| Marketplace install | `~/.copilot/state/installed-plugins/<MARKETPLACE>/<NAME>/` |
| Marketplace cache | `~/.copilot/state/marketplace-cache/` |

> **⚠️ Documented inconsistency:** The [CLI Plugin Reference](https://docs.github.com/en/copilot/reference/cli-plugin-reference#file-locations) page uses `~/.copilot/state/installed-plugins/<NAME>/` for direct installs, while the [How-to: Finding and Installing Plugins](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-finding-installing#where-plugins-are-stored) page uses `~/.copilot/installed-plugins/_direct/<NAME>/`. Key differences: the `state/` prefix (reference has it, how-to doesn't) and the `_direct/` subdirectory (how-to has it, reference doesn't). Verify paths on your local filesystem.

On Windows, `~` resolves to `%USERPROFILE%` (e.g., `C:\Users\<username>\.copilot\...`).

> **Workspace publish caveat:** `scripts/publish/publish-plugins.ps1` uses the `_direct/<NAME>` path for CLI publishing, copies the prepared bundle from `plugins/cli/.build/<NAME>/`, and verifies that `plugin.json` exists at the destination. Local probes still have not proven that raw `_direct` copies are always discovered the same way as `copilot plugin install`.

---

## Loading Precedence

When multiple sources define the same artifact (e.g., an agent with the same name), the CLI uses a **user > project > parent dirs > plugin > remote/org** precedence model:

| Priority | Source | Example Path |
|----------|--------|-------------|
| 1 (highest) | User-level | `~/.copilot/agents/`, `~/.copilot/skills/` |
| 2 | Project-level | `.github/agents/`, `.github/instructions/` |
| 3 | Parent directories | Walked upward from CWD |
| 4 | Plugin components | Installed plugin agent/skill directories |
| 5 (lowest) | Remote/org agents | Organization or enterprise-configured agents |

> **MCP exception:** MCP server definitions use **last-wins** precedence (opposite of agents/skills).
>
> **Instruction limitation:** The official loading order diagram shows agents, skills, and MCP servers loaded from plugins, but **NOT instructions**. Instructions have no plugin loading path.

### Implications for Publish Scripts

User-level agents in `~/.copilot/agents/` (placed by `publish-agents.ps1`) take precedence over plugin agents. If the same agent exists both as a user-level file and inside a plugin, the user-level copy wins. **Recommendation**: Use one distribution channel per artifact — publish scripts for local development, plugins for team distribution.

See [publish-plugins.ps1](../../../scripts/publish/publish-plugins.ps1) for the workspace's plugin installation automation.

---

## Publish Script Reference

The workspace provides `scripts/publish/publish-plugins.ps1` for runtime-scoped bundle publishing:

```powershell
# Publish all workspace plugins
pwsh -NoProfile -File scripts/publish/publish-plugins.ps1

# Publish a specific CLI plugin
pwsh -NoProfile -File scripts/publish/publish-plugins.ps1 -Runtime cli -Plugins ralph-v2

# Force remains accepted for compatibility
pwsh -NoProfile -File scripts/publish/publish-plugins.ps1 -Force

# Register a VS Code plugin bundle path
pwsh -NoProfile -File scripts/publish/publish-plugins.ps1 -Runtime vscode -Plugins ralph-v2

# Skip WSL installation for CLI publish
pwsh -NoProfile -File scripts/publish/publish-plugins.ps1 -SkipWSL
```

The script discovers plugins in `plugins/cli/` and `plugins/vscode/`, builds runtime-scoped bundles under `plugins/<runtime>/.build/<name>/`, then publishes by runtime: CLI bundles are copied directly into `_direct/<name>` and VS Code bundles are registered in `chat.plugins.paths`. See [How to Publish Customizations for Copilot CLI](../../how-to/copilot/how-to-publish-customizations-for-copilot-cli.md) for the broader publish workflow.
