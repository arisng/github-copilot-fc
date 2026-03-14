# CLI Plugin Reference

> **Last verified**: GitHub Docs (March 2026) and local GitHub Copilot CLI 1.0.4 observations on this machine
> **Related**: [About CLI Plugins](../../explanation/copilot/about-cli-plugins.md) · [How to Create a CLI Plugin](../../how-to/copilot/how-to-create-cli-plugin.md) · [Customization Matrix](copilot-cli-customization-matrix.md)

This reference documents the `plugin.json` manifest schema, CLI commands, installation spec patterns, directory conventions, and loading precedence for GitHub Copilot CLI plugins.

---

## References (Official Documentation)

Periodically verify against the official documentation to ensure accuracy, as the CLI is rapidly evolving and may have discrepancies or silent changes:

- [GitHub Copilot CLI plugin reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-plugin-reference)
- [Finding and installing plugins for GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-finding-installing)
- [Creating a plugin for GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-creating)

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

The directory name should match the `name` field in `plugin.json`. Build and publish scripts emit per-plugin bundles under `plugins/<runtime>/.build/<name>/`; that child directory is the runtime-scoped build output and publish input.

For VS Code workspace publishing, the `.build/` bundle is not the final user-facing destination. The publish flow builds under `plugins/vscode/.build/<name>/`, then copies that bundle into VS Code's Windows user-data `agentPlugins` directory and registers the published location in `chat.plugins.paths`. One concrete Windows Insiders root is `C:\Users\ADMIN\AppData\Roaming\Code - Insiders\agentPlugins\`.

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
| `copilot plugin install <spec>` | Official plugin installation entrypoint. Web docs document local path, GitHub URL/path, and marketplace specs. See [Install Spec Patterns](#install-spec-patterns). |
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

> **Help/docs drift:** Current web docs document local-path installs, including `copilot plugin install ./my-plugin`, but the local `copilot plugin install --help` output observed in CLI 1.0.4 omits local-path examples and parsing guidance. Treat that omission as help-text drift, not as a stronger contract than the published docs.

> **Note:** Marketplace publishing is **deferred** to a future iteration. Currently, local path and GitHub URL installs are the primary distribution methods. See [About CLI Plugins](../../explanation/copilot/about-cli-plugins.md) for marketplace ecosystem status.

---

## Installation Contract and File Locations

Plugin files are copied on install; they are not linked back to the source directory. The documented contract is the install command itself, not a guaranteed on-disk path layout.

| Topic | Documented / official | Observed on this machine | Notes |
|-------|------------------------|--------------------------|-------|
| Install entrypoint | `copilot plugin install <source>` | Local-path installs succeeded with `copilot plugin install <local_plugin_path>` in local CLI 1.0.4. | Treat the command as the stable contract. |
| Direct install storage | `~/.copilot/state/installed-plugins/<NAME>/` | `%USERPROFILE%\.copilot\installed-plugins\_direct\<NAME>\` | Current docs and local runtime behavior differ. |
| Marketplace install storage | `~/.copilot/state/installed-plugins/<MARKETPLACE>/<NAME>/` | Not re-verified in the local runtime check. | This page preserves the current docs claim. |
| Marketplace cache | `~/.copilot/state/marketplace-cache/` | Not re-verified in the local runtime check. | Docs-only statement in this page. |
| Local-path guidance | Web docs explicitly document local-path installs. | Local `copilot plugin install --help` omitted local-path examples and parsing order. | Help/docs drift exists in local CLI 1.0.4. |
| `--config-dir` behavior | No plugin-specific storage guarantee was located in the official references above. | In the local runtime check, the temporary config root remained empty while installs appeared under the global `%USERPROFILE%\.copilot\installed-plugins\_direct\...` tree. | Evidence is limited to the observed CLI 1.0.4 behavior on this machine; do not generalize beyond that. |

> **Evidence note:** The documented/observed distinctions above are based on the official docs linked in [References](#references-official-documentation) and the local research summary at `C:\Users\ADMIN\.copilot\session-state\24d7a4e4-9149-4ac6-a5c4-5cade4d9db90\research\double-check-method-to-install-plugins-created-in-.md` (especially lines 5-8, 25, 39-48, 64-82, 169-173).

On Windows, `~` resolves to `%USERPROFILE%` (e.g., `C:\Users\<username>\.copilot\...`).

> **Workspace local-flow note:** in this repository, treat the built bundle under `plugins/cli/.build/` as the local installable unit and run `copilot plugin install <local_plugin_path>`. If you inspect the cache after install, current local runs may still materialize files under `_direct/<NAME>`, but that is observational storage rather than the supported contract.

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

# Publish a VS Code plugin bundle
pwsh -NoProfile -File scripts/publish/publish-plugins.ps1 -Runtime vscode -Plugins ralph-v2

# Skip WSL installation for CLI publish
pwsh -NoProfile -File scripts/publish/publish-plugins.ps1 -SkipWSL
```

For local CLI installs from this workspace, treat the built CLI bundle as the handoff point:

```bash
copilot plugin install <local_plugin_path>
```

The script discovers plugins in `plugins/cli/` and `plugins/vscode/`, builds runtime-scoped bundles under `plugins/<runtime>/.build/<name>/`, then publishes by runtime: CLI bundles are intended to be installed from that local bundle path with `copilot plugin install <local_plugin_path>`, while VS Code bundles are copied into the Windows user-data `agentPlugins` directory and the published copy is registered in `chat.plugins.paths`. If you inspect the CLI cache after install, current local runtimes may still materialize the payload under `_direct/<name>`. See [How to Publish Customizations for Copilot CLI](../../how-to/copilot/how-to-publish-customizations-for-copilot-cli.md) for the broader publish workflow.
