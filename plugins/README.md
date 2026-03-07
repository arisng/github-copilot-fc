# Plugins

Plugins are self-contained bundles of GitHub Copilot CLI customization artifacts (agents, skills, commands, hooks, MCP servers, LSP servers) distributed as a single installable unit via the `copilot plugin` system.

## References

Plugin in Copilot CLI - https://docs.github.com/en/copilot/reference/cli-plugin-reference
Plugin in Copilot VS Code - https://code.visualstudio.com/docs/copilot/customization/agent-plugins

## Directory Layout

```
plugins/
  cli/                   # Plugins targeting GitHub Copilot CLI runtime
    <name>/
      plugin.json        # Plugin manifest (required)
  vscode/                # Plugins targeting VS Code Copilot runtime
    <name>/
      plugin.json        # Plugin manifest (required)
```

Plugins are organized into runtime-specific subdirectories:
- `cli/` — plugins for the GitHub Copilot CLI runtime (`target: github-copilot`)
- `vscode/` — plugins for the VS Code Copilot runtime (`target: vscode`)

Each plugin lives in its own subdirectory under the respective runtime folder. The directory name should match the `name` field in `plugin.json`.

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

> **Note:** `strict` is NOT a `plugin.json` field. It only appears in `marketplace.json` plugin entries (where it controls schema validation per-plugin). Do not add `strict` to `plugin.json` files.

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
- **Bundling is default**: `publish-plugins.ps1` produces a self-contained `.build/` directory automatically. Use `-SkipBundle` only for development/debugging — it emits a warning because relative paths may not resolve correctly after `copilot plugin install`.

Use publish scripts for local development iteration. Use plugins for packaging and sharing complete workflows.

## Instruction Embedding

The `instructions` field is **not** part of the `plugin.json` schema, and the Copilot CLI does not load instruction files from installed plugins at runtime. To solve this, the publish pipeline **embeds** instruction content directly into agent files at bundle time.

### How it works

1. **EMBED markers** — Agent source files contain a placeholder comment where instruction content should be inlined:

   ```markdown
   <!-- EMBED: ralph-v2-executor.instructions.md -->
   ```

2. **`Merge-AgentInstructions`** — During `Build-PluginBundle`, this function scans `.build/agents/` for EMBED markers and resolves them:
   - Reads the referenced file from `instructions/`
   - Strips the instruction file's YAML frontmatter and first H1 header
   - Replaces the marker line with the stripped content
   - Preserves the agent's own YAML frontmatter verbatim (including `mcp-servers:`)

3. **Validation** — After merging, the function:
   - Checks the merged body length is ≤ 30,000 characters (copilot-cli limit — applies to markdown body only, not YAML frontmatter)
   - Warns if required section markers (`<persona>`, `<rules>`, signal protocol, `<contract>`) are missing

### Build pipeline flow

```
Copy (source → .build/) → Merge (resolve EMBED markers) → Validate (paths + char limits)
```

### Instruction file sizing

All embedded instruction files are compressed to fit within the 30K body limit. The Reviewer (26K) and Librarian (27K) instruction files were compressed in a previous iteration — redundant checklists, verbose examples, and duplicate reference sections were removed while preserving persona, rules, core workflow, signal protocol, and contract.

The Orchestrator agent is excluded from embedding (body + instructions exceed 46K). Its instruction file is delivered separately and loaded at runtime.

## Instruction Delivery (Legacy)

For agents that are **not** embedded, instruction files must still be delivered separately using `publish-instructions.ps1`:

```powershell
# Deliver instruction files to standard CLI paths
pwsh -NoProfile -File scripts/publish/publish-instructions.ps1
```

The CLI resolves instructions from `AGENTS.md`, `~/.copilot/copilot-instructions.md`, `COPILOT_CUSTOM_INSTRUCTIONS_DIRS`, and project `.github/copilot-instructions.md` — but never from installed plugin directories.

## Marketplace Publishing

Marketplace publishing for plugins is **deferred** to a future iteration. Currently, plugins are installed from local directories only.
