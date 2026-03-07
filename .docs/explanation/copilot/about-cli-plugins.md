# About CLI Plugins

> **Related**: [CLI Plugin Reference](../../reference/copilot/cli-plugin-reference.md) · [How to Create a CLI Plugin](../../how-to/copilot/how-to-create-cli-plugin.md) · [Customization Matrix](../../reference/copilot/copilot-cli-customization-matrix.md)

This document explains what Copilot CLI plugins are, why they exist, and how they fit into the broader GitHub Copilot customization ecosystem. For step-by-step authoring instructions, see the linked how-to guide. For schema and command details, see the reference doc.

---

## What Are Plugins?

A plugin is a **self-contained bundle** of GitHub Copilot customization artifacts (primitives) — agents, skills, hooks, commands, MCP servers, and LSP servers — distributed as a single installable unit. Instead of manually copying individual `.agent.md` files, `SKILL.md` directories, and hook configs to their respective discovery paths, a plugin packages them together under one `plugin.json` manifest and installs them with a single command.

```bash
copilot plugin install ./plugins/cli/ralph-v2
```

This installs all the components declared in the plugin manifest in one step.

In this workspace, plugin authoring and plugin publishing are separate concerns: source manifests live under `plugins/<runtime>/<name>/`, while the publish scripts first materialize a runtime-scoped bundle under `plugins/<runtime>/.build/<name>/` and publish from that bundle.

---

## Why Plugins Exist

### The Problem: Manual Configuration Overhead

Without plugins, setting up a complete Copilot workflow requires:

1. Copying agent files to `~/.copilot/agents/`
2. Copying skill directories to `~/.copilot/skills/`
3. Publishing hooks to `.github/hooks/`
4. Configuring MCP servers in `mcp-config.json`

Each step involves knowing the right discovery path, the right file format, and the right naming conventions. Sharing this setup with a teammate means documenting every step — and keeping those instructions updated as the workflow evolves.

### The Solution: Bundle and Distribute

Plugins solve this by:

- **Bundling**: All components are declared in one manifest (`plugin.json`) with relative paths to each artifact type.
- **Installing**: One command (`copilot plugin install`) handles discovery path resolution and component placement.
- **Versioning**: `plugin.json` includes a `version` field, enabling controlled updates via `copilot plugin update`.
- **Lifecycle management**: Plugins can be enabled, disabled, updated, and uninstalled cleanly.

---

## Plugins vs. Manual Configuration

Both approaches are valid. The right choice depends on your workflow:

| Factor                | Plugins                              | Manual Configuration (Publish Scripts)     |
| --------------------- | ------------------------------------ | ------------------------------------------ |
| **Setup speed**       | One command installs everything      | Multiple publish scripts per artifact type |
| **Best for**          | Distribution to other machines/teams | Local development iteration                |
| **Update workflow**   | `copilot plugin update <name>`       | Re-run publish scripts                     |
| **Granularity**       | All-or-nothing per plugin            | Individual artifact control                |
| **Temporary removal** | `copilot plugin disable <name>`      | Delete files from discovery paths          |
| **Audience**          | Team members, new machine setup      | Solo developer, active authoring           |

### When to Use Plugins

- **Setting up a new machine**: Install your complete workflow with one command instead of running multiple publish scripts
- **Sharing with teammates**: Distribute a tested, versioned bundle instead of setup instructions
- **Version-controlled distribution**: Pin a specific plugin version for consistency across a team
- **Clean separation**: Keep experimental workflows isolated — disable a plugin when not needed

### When to Use Manual Configuration

- **Active development**: Publish scripts provide faster iteration when editing individual agents or skills
- **Selective customization**: You only need some artifacts from a workflow, not the full bundle
- **VS Code primary**: VS Code plugins in this workspace are registration-based through `chat.plugins.paths`, not installed through the CLI `_direct` flow

### Coexistence Warning

Plugins and publish scripts can coexist, but be aware of **precedence conflicts**. User-level agents in `~/.copilot/agents/` (placed by `publish-agents.ps1`) take precedence over plugin agents due to the first-found-wins loading order. If the same agent exists in both locations, the user-level copy wins, which can cause version drift.

**Recommendation**: Choose one distribution channel per artifact. Use publish scripts during development, switch to plugin distribution for sharing.

---

## Where Plugins Are Installed

Plugin files are **copied** (cached) on install — not symlinked. To pick up local changes after editing a plugin, you must reinstall it with `copilot plugin install`.

| Source                          | Install Path                                               |
| ------------------------------- | ---------------------------------------------------------- |
| Direct install (reference page) | `~/.copilot/state/installed-plugins/<NAME>/`               |
| Direct install (how-to page)    | `~/.copilot/installed-plugins/_direct/<NAME>/`             |
| Marketplace install             | `~/.copilot/state/installed-plugins/<MARKETPLACE>/<NAME>/` |
| Marketplace cache               | `~/.copilot/state/marketplace-cache/`                      |

> **⚠️ Documented inconsistency:** Two official GitHub docs disagree on direct install paths. The [CLI Plugin Reference](https://docs.github.com/en/copilot/reference/cli-plugin-reference#file-locations) uses `~/.copilot/state/installed-plugins/<NAME>/`, while the [How-to: Finding and Installing Plugins](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-finding-installing#where-plugins-are-stored) uses `~/.copilot/installed-plugins/_direct/<NAME>/`. Key differences: the `state/` prefix (reference has it, how-to doesn't) and the `_direct/` subdirectory (how-to has it, reference doesn't). Verify the actual path on your local filesystem after installing a plugin.

On Windows, `~` resolves to `%USERPROFILE%` (e.g., `C:\Users\<username>\.copilot\...`).

This workspace currently uses the how-to page's `_direct/<NAME>` path for CLI publish automation. The publisher verifies that the copied bundle landed in the target directory, but local probes still have not proven that a raw `_direct` copy is always discovered the same way as `copilot plugin install`.

---

## Workspace Publish Model

The repository's publish flow is runtime-scoped:

- Source manifests live under `plugins/cli/<name>/plugin.json` and `plugins/vscode/<name>/plugin.json`.
- Bundles are built under `plugins/cli/.build/<name>/` or `plugins/vscode/.build/<name>/`.
- CLI publish copies the prepared bundle directly into `~/.copilot/installed-plugins/_direct/<name>/` with exact replacement semantics and no `.install/` staging.
- VS Code publish registers `plugins/vscode/.build/<name>/` in `chat.plugins.paths`.

The runtime-scoped `.build/` root is only a container. The actual publishable unit is the per-plugin bundle directory beneath it.

---

## Loading Precedence

The CLI resolves artifacts using a first-found-wins model (except MCP servers, which use last-wins):

1. **User-level** (`~/.copilot/`) — highest priority
2. **Project-level** (`.github/`) — repository-specific
3. **Parent directories** — walked upward from CWD
4. **Plugin components** — installed plugin directories
5. **Remote/organization** — enterprise-configured agents

This means a user-level agent with the same name as a plugin agent will shadow the plugin version. This is by design — it allows users to override plugin defaults — but it creates a version drift risk when both publish scripts and plugins target the same agents.

---

## Team Distribution Scenarios

### Scenario 1: Solo Developer, Multiple Machines

1. Author CLI plugins in the workspace (`plugins/cli/<name>/plugin.json`)
2. Push to GitHub
3. On a new machine: `copilot plugin install github.com/owner/repo:plugins/cli/<name>`

### Scenario 2: Team Sharing via Repository

1. Create a plugin with self-contained components (not relative paths)
2. Commit to a shared repository
3. Team members install: `copilot plugin install github.com/team/plugins-repo:plugins/cli/<name>`
4. Updates: `copilot plugin update <name>`

### Scenario 3: Organization-Wide Distribution

1. Publish plugins to a private marketplace
2. Register the marketplace: `copilot plugin marketplace add org/marketplace`
3. Team members install: `copilot plugin install @org/plugin-name`

> **Note:** Scenario 3 requires marketplace infrastructure, which is **deferred** to a future iteration.

---

## Marketplace Ecosystem

The Copilot CLI plugin system includes a marketplace mechanism for discovering and distributing plugins.

Marketplace features include:

- `copilot plugin install @owner/name` — Install from marketplace
- `copilot plugin marketplace add <repo>` — Register additional marketplaces

### Current Status

Marketplace publishing is **deferred** to a future iteration of this workspace. The pilot plugin (`plugins/cli/ralph-v2/`) is distributed via local path and direct GitHub URL installs. Marketplace infrastructure (creating `marketplace.json`, hosting, versioning strategy) will be addressed when the plugin system matures.

For current installation methods, see the [How to Create a CLI Plugin](../../how-to/copilot/how-to-create-cli-plugin.md) guide.

---

## Workspace Plugin Pilot

The workspace includes a pilot plugin at `plugins/cli/ralph-v2/` that bundles the ralph-v2 multi-agent orchestration system for Copilot CLI. This pilot demonstrates:

- `plugin.json` manifest with relative paths to existing workspace artifacts
- Integration with `publish-plugins.ps1` for automated runtime-scoped bundling and publish
- Coexistence with existing per-artifact publish scripts

See [plugins/README.md](../../../plugins/README.md) for directory layout documentation.
