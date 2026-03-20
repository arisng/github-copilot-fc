# About CLI Plugins

> **Related**: [CLI Plugin Reference](../../../../reference/copilot/cli/cli-plugin-reference.md) · [How to Create a CLI Plugin](../../../../how-to/copilot/cli/how-to-create-cli-plugin.md) · [Customization Matrix](../../../../reference/copilot/cli/copilot-cli-customization-matrix.md)

This document explains what Copilot CLI plugins are, why they exist, and how they fit into the broader GitHub Copilot customization ecosystem. For step-by-step authoring instructions, see the linked how-to guide. For schema and command details, see the reference doc.

---

## What Are Plugins?

A plugin is a **self-contained bundle** of GitHub Copilot customization artifacts (primitives) — agents, skills, hooks, commands, MCP servers, and LSP servers — distributed as a single installable unit. Instead of manually copying individual `.agent.md` files, `SKILL.md` directories, and hook configs to their respective discovery paths, a plugin packages them together under one `plugin.json` manifest and installs them with a single command.

```bash
copilot plugin install ./plugins/cli/ralph-v2
```

This installs all the components declared in the plugin manifest in one step.

In this workspace, plugin authoring and plugin publishing are separate concerns: source manifests live under `plugins/<runtime>/<name>/`, while the publish scripts first materialize a runtime-scoped bundle under `plugins/<runtime>/.build/<name>/` and publish from that bundle. For VS Code, that publish step means copying the built bundle into the Windows user-data `agentPlugins` directory and registering the published location in `chat.plugins.paths`, rather than pointing VS Code directly at the workspace `.build` path. The important conceptual boundary is that GitHub documents plugin installation as a CLI command contract, while this workspace also has implementation-specific automation for local publishing.

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

## The Important Boundary: Contract vs. Automation

The most useful distinction is not "plugins versus publish scripts," but **upstream contract versus workspace automation**.

GitHub's public contract is command-oriented: the documented way to install a plugin is `copilot plugin install <source>`, where `<source>` can be a local path, repository location, or marketplace reference. That matters because the command is the stable abstraction boundary. It lets the CLI decide how to validate the manifest, where to cache files, and how to evolve its internal storage model without changing the user-facing installation story.

The workspace's bundle-first local plugin flow serves a different purpose. It builds a local bundle and uses `copilot plugin install <local_plugin_path>` as the supported install step. If you inspect the cache after install, current local runs may materialize files under `_direct`, but that is a storage detail the public docs do not promise: directory names, cache layout, and any install-time bookkeeping the CLI may perform when it installs a plugin itself.

| Concern | Upstream contract | Workspace automation |
| ------- | ----------------- | -------------------- |
| Stable user-facing boundary | `copilot plugin install <source>` | Build bundle + `copilot plugin install <local_plugin_path>` |
| Backed by public GitHub docs | Yes | No |
| Depends on current on-disk layout | No | Yes |
| Suitable as explanation-level guidance | Yes | Only as a workspace implementation note |

### Coexistence Warning

Plugins and publish scripts can coexist, but be aware of **precedence conflicts**. User-level agents in `~/.copilot/agents/` (placed by `publish-agents.ps1`) take precedence over plugin agents due to the first-found-wins loading order. If the same agent exists in both locations, the user-level copy wins, which can cause version drift.

**Recommendation**: Choose one distribution channel per artifact. Use publish scripts during development, switch to plugin distribution for sharing.

---

## Why the Install Path Is Not the Contract

Plugin files are **copied** on install rather than symlinked, but the exact destination is where the current story becomes messy.

Recent local verification for this workspace found a three-way mismatch:

| Source of truth | What it suggests for local CLI plugin installs |
| ---------------- | ------------------------------------ |
| Current web docs | `~/.copilot/state/installed-plugins/<NAME>/` |
| Observed local Copilot CLI 1.0.4 post-install cache | `~/.copilot/installed-plugins/_direct/<NAME>/` |
| Supported workspace local flow | Build `plugins/cli/.build/<name>/` and run `copilot plugin install <local_plugin_path>` |

The mismatch is wider than one page disagreeing with another. The latest web docs explicitly support `copilot plugin install <local-path>`, while the local `copilot plugin install --help` output is narrower and omits local-path examples, even though the runtime still accepted local-path installs during verification. In other words, the docs, local help text, and observed filesystem behavior are not perfectly aligned.

That is exactly why the install directory should be treated as an implementation detail rather than as the conceptual model. If readers internalize "`_direct` is how plugins work," they are learning a volatile storage detail. If they internalize "`copilot plugin install <source>` is the supported contract," they are learning the boundary GitHub is actually documenting.

On Windows, `~` resolves to `%USERPROFILE%` (for example, `C:\Users\<username>\.copilot\...`).

---

## Workspace Publish Model

The repository's publish flow is runtime-scoped:

- Source manifests live under `plugins/cli/<name>/plugin.json` and `plugins/vscode/<name>/plugin.json`.
- Bundles are built under `plugins/cli/.build/<name>/` or `plugins/vscode/.build/<name>/`.
- CLI local publish/install uses the built bundle as the handoff point and installs it with `copilot plugin install <local_plugin_path>`.
- VS Code publish copies the built bundle into VS Code's Windows user-data `agentPlugins` directory (for example `C:\Users\ADMIN\AppData\Roaming\Code - Insiders\agentPlugins\`) and registers that published location in `chat.plugins.paths`.

The runtime-scoped `.build/` root is only a staging container. For CLI, it is the local install unit passed to `copilot plugin install`; the CLI then manages its own cache. If you inspect that cache today, you may still see `_direct`. For VS Code, the bundle is copied into `agentPlugins` and the published copy is registered there.

For explanation purposes, the important point is not that `_direct` exists, but **why the workspace keeps a bundle-first local flow at all**. The cache path reflects current local observations. It does **not** redefine the upstream model. If GitHub changes its install root, caching behavior, or install-time validation, the workspace publisher is the piece that must adapt; the conceptual contract remains `copilot plugin install <source>`.

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

## Distribution Perspectives

Plugins are most valuable when the unit of sharing is "the whole workflow" rather than an individual agent or skill. For a solo developer, that makes plugins a portable bundle across machines. For a team, it makes the repository path or marketplace reference the handoff point instead of a checklist of manual copy steps. For an organization, it creates a path toward curated distribution through marketplaces rather than through per-user filesystem conventions.

This workspace is intentionally in between those worlds. It authors plugins as first-class bundles, but it also keeps bundle-first local publish automation because active authoring benefits from fast local replacement. Marketplace distribution remains a later concern rather than the current baseline.

---

## Marketplace Ecosystem

The Copilot CLI plugin system includes a marketplace mechanism for discovering and distributing plugins.

Marketplace features include:

- `copilot plugin install @owner/name` — Install from marketplace
- `copilot plugin marketplace add <repo>` — Register additional marketplaces

### Current Status

Marketplace publishing is **deferred** to a future iteration of this workspace. The pilot plugin (`plugins/cli/ralph-v2/`) is distributed via local path and direct GitHub URL installs. Marketplace infrastructure (creating `marketplace.json`, hosting, versioning strategy) will be addressed when the plugin system matures.

For current installation methods, see the [How to Create a CLI Plugin](../../../../how-to/copilot/cli/how-to-create-cli-plugin.md) guide.

---

## Workspace Plugin Pilot

The workspace includes a pilot plugin at `plugins/cli/ralph-v2/` that bundles the ralph-v2 multi-agent orchestration system for Copilot CLI. This pilot demonstrates:

- `plugin.json` manifest with relative paths to existing workspace artifacts
- Integration with `publish-plugins.ps1` for automated runtime-scoped bundling and publish
- Coexistence with existing per-artifact publish scripts

See [plugins/README.md](../../../../../plugins/README.md) for directory layout documentation.
