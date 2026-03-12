# Plugins

Plugins are self-contained bundles of GitHub Copilot CLI customization artifacts (agents, skills, commands, hooks, MCP servers, LSP servers) distributed as a single installable unit via the `copilot plugin` system.

## References

Plugin in Copilot CLI - https://docs.github.com/en/copilot/reference/cli-plugin-reference
Plugin in Copilot VS Code - https://code.visualstudio.com/docs/copilot/customization/agent-plugins

## Directory Layout

```
plugins/
  cli/                   # Plugins targeting GitHub Copilot CLI runtime
             .build/              # Shared bundle output for stable and beta publishes
    <name>/
      plugin.json        # Plugin manifest (required)
         README.md          # Optional consumer guide copied into bundles when present
  vscode/                # Plugins targeting VS Code Copilot runtime
             .build/              # Shared bundle output for stable and beta publishes
    <name>/
      plugin.json        # Plugin manifest (required)
         README.md          # Optional consumer guide copied into bundles when present
```

Plugins are organized into runtime-specific subdirectories:
- `cli/` — plugins for the GitHub Copilot CLI runtime (`target: github-copilot`)
- `vscode/` — plugins for the VS Code Copilot runtime (`target: vscode`)

Each plugin lives in its own subdirectory under the respective runtime folder. The directory name should match the `name` field in `plugin.json`.

Each plugin should also carry a concise consumer-facing `README.md`. When present, the bundle builder copies that file into the root of the built plugin directory next to `plugin.json` for both stable and beta outputs.

Build and publish scripts never publish from the source directory directly. They first produce a runtime-scoped bundle under `plugins/<runtime>/.build/`. Stable bundles use `plugins/<runtime>/.build/<name>/`. Beta bundles use the same `.build/` root but suffix the plugin name: `plugins/<runtime>/.build/<name>-beta/`. This allows stable and beta bundles to coexist in parallel.

## plugin.json Schema

### Metadata Fields

| Field         | Required | Default | Description                               |
| ------------- | -------- | ------- | ----------------------------------------- |
| `name`        | **Yes**  | —       | Plugin identifier (lowercase, hyphenated) |
| `description` | No       | —       | Human-readable description                |
| `version`     | No       | —       | Semantic version string                   |
| `author`      | No       | —       | Author name or organization               |
| `license`     | No       | —       | License identifier (e.g. `MIT`)           |
| `homepage`    | No       | —       | URL to plugin homepage                    |
| `bugs`        | No       | —       | URL for issue reporting                   |
| `repository`  | No       | —       | URL to source repository                  |
| `keywords`    | No       | —       | Array of keyword strings for discovery    |

> **Note:** `strict` is NOT a `plugin.json` field. It only appears in `marketplace.json` plugin entries (where it controls schema validation per-plugin). Do not add `strict` to `plugin.json` files.

### Component Path Fields

| Field        | Type               | Description                                  |
| ------------ | ------------------ | -------------------------------------------- |
| `agents`     | string or string[] | Relative path(s) to agent files              |
| `skills`     | string or string[] | Relative path(s) to skill directories        |
| `commands`   | string or string[] | Relative path(s) to command tool definitions |
| `hooks`      | string or string[] | Relative path(s) to hook configurations      |
| `mcpServers` | string or string[] | Relative path(s) to MCP server definitions   |
| `lspServers` | string or string[] | Relative path(s) to LSP server definitions   |

All component paths are relative to the plugin directory. These are the **only** 6 official component fields in the plugin.json schema.

> **Note:** `instructions` is NOT a plugin.json component field. Instruction files cannot be delivered via plugins. Use `scripts/publish/publish-instructions.ps1` for instruction distribution instead.

## Installation

Install a CLI plugin from a local source directory with the official Copilot CLI flow:

```bash
copilot plugin install ./plugins/cli/<name>
```

For workspace publishing, use the runtime-specific publish flow instead of the raw source directory:

- CLI: `publish-plugins.ps1` defaults to beta, building `plugins/cli/.build/<name>-beta/` and copying that bundle directly into `~/.copilot/installed-plugins/_direct/<name>-beta/` on Windows and WSL/Linux. The target is replaced exactly. No `.install/` staging directory is used.
- VS Code: `publish-plugins.ps1` defaults to beta, building `plugins/vscode/.build/<name>-beta/` and registering that bundle path in `chat.plugins.paths`.
- Stable publish or promotion: use `-Channel stable` for an explicit stable publish, or `-Promote` to promote the current beta flow to stable. Stable outputs use `plugins/<runtime>/.build/<name>/`, CLI installs to `_direct/<name>/`, and VS Code registration points at `.build/<name>/`.

The CLI **copies** (caches) plugin contents — it does not create a symlink. To pick up local changes after editing, rerun `copilot plugin install` for the official CLI flow or rerun `publish-plugins.ps1` for the workspace publish flow.

## Where Plugins Are Stored

After installation, plugin files are cached on the local machine.

| Source                                                                                                                                      | Direct Install Path                            | Marketplace Install Path                                   |
| ------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------- | ---------------------------------------------------------- |
| [How-to docs](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-finding-installing#where-plugins-are-stored) | `~/.copilot/installed-plugins/_direct/<NAME>/` | `~/.copilot/installed-plugins/<MARKETPLACE>/<NAME>/`       |

Marketplace cache (reference docs): `~/.copilot/marketplace-cache/`

> **⚠️** These paths are documented as-is from official GitHub docs (March 2026). The inconsistency has not been resolved upstream. Verify against your local installation if exact paths matter.

> **Workspace publish accepted limitation:** this repository's CLI publish script copies bundles directly into `_direct/<NAME>` for stable or `_direct/<NAME>-beta` for beta and verifies the copied payload, but local probes still have not proven that a raw `_direct` copy is always discovered the same way as `copilot plugin install`. Keep the caveat documented, but treat it as an accepted limitation of the workspace publish shortcut rather than an active defect; use `copilot plugin install` when you need the officially validated discovery path.

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
- **Bundling is built into the publish flow**: `publish-plugins.ps1` emits self-contained bundles under `plugins/<runtime>/.build/`, using `<name>-beta` for beta or `<name>` for stable, so both channels can exist side by side.
- **CLI publish is a direct copy**: the prepared CLI beta bundle is copied straight into Copilot's `_direct/<name>-beta` install root with exact replacement semantics, without `.install/` staging. Explicit stable publish uses `_direct/<name>`.
- **VS Code publish is registration-only**: the prepared VS Code beta bundle path is written into `chat.plugins.paths` as `.build/<name>-beta`; explicit stable publish registers `.build/<name>`. VS Code does not use the CLI `_direct` install flow.
- **Stable is an explicit promotion path**: use `publish-plugins.ps1 -Promote` after a beta build is ready, or pass `-Channel stable` when you intentionally want a stable publish.
- **Hook scripts travel with the plugin bundle**: when a plugin declares `hooks`, the build pipeline copies each hook's `hooks/<name>/scripts/` folder into the bundled hook tree so bundled hook manifests can invoke their companion scripts in other workspaces.

Use publish scripts for local development iteration. Use plugins for packaging and sharing complete workflows.

## Instruction Embedding

The `instructions` field is **not** part of the `plugin.json` schema, and the Copilot CLI does not load instruction files from installed plugins at runtime. To solve this, the publish pipeline **embeds** instruction content directly into agent files at bundle time.
This instruction embedding process is a custom solution of current workspace to the problem of distributing agent instructions alongside their source files in a way that ensures they are always available at runtime without relying on external file paths or manual publishing steps. By embedding instructions directly into agent markdown files during the build process, we can guarantee that all necessary information travels with the agent itself as part of the plugin bundle.
Copilot does not have a native concept of instruction embedding, so this is implemented as a custom build step in our `Build-PluginBundle` function that processes agent files for special EMBED markers and inlines the referenced instruction content before finalizing the plugin bundle. This allows us to maintain a clean separation of source files during development while ensuring a seamless experience for end users who install the plugin without needing to worry about separate instruction file management.

### How it works

1. **EMBED markers** — Agent source files contain a placeholder comment where instruction content should be inlined:

   ```markdown
   <!-- EMBED: ralph-v2-executor.instructions.md -->
   ```

2. **`Merge-AgentInstructions`** — During `Build-PluginBundle`, this function scans `plugins/<runtime>/.build/<name>-beta/agents/` for EMBED markers during the default beta flow (or `.build/<name>/agents/` for stable) and resolves them:
   - Reads the referenced file from `instructions/`
   - Strips the instruction file's YAML frontmatter and first H1 header
   - Replaces the marker line with the stripped content
   - Preserves the agent's own YAML frontmatter verbatim (including `mcp-servers:`)

3. **Validation** — After merging, the function:
   - Checks the merged body length is ≤ 30,000 characters (copilot-cli limit — applies to markdown body only, not YAML frontmatter)
   - Warns if required section markers (`<persona>`, `<rules>`, signal protocol, `<contract>`) are missing

### Build pipeline flow

```
Copy (source → plugins/<runtime>/.build/<name>-beta/ by default) → Merge (resolve EMBED markers) → Bundle hook scripts when present → Validate (paths + char limits)
```

### Instruction file sizing

All embedded instruction files are compressed to fit within the 30K body limit where the runtime requires it. Deep reference material that should not live in the agent body is better moved into plugin-bundled skills and loaded on demand.

## Instruction Delivery (Legacy)

Only workflows that intentionally choose not to embed instruction content still need separate instruction publishing via `publish-instructions.ps1`:

```powershell
# Deliver instruction files to standard CLI paths
pwsh -NoProfile -File scripts/publish/publish-instructions.ps1
```

The CLI resolves always-on instructions from `AGENTS.md`, `~/.copilot/copilot-instructions.md`, `COPILOT_CUSTOM_INSTRUCTIONS_DIRS`, and project `.github/copilot-instructions.md` — but embedded agent bodies are already self-contained once bundled into the plugin.

## Marketplace Publishing

Marketplace publishing for plugins is **deferred** to a future iteration. Currently, plugins are installed from local directories only.
