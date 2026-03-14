# How to Create a CLI Plugin

This guide walks you through creating a Copilot CLI plugin from scratch — from directory setup through manifest authoring to the supported local install-and-verify flow.

## When to use this guide

Use this if you want to:

- Bundle multiple customization artifacts (agents, skills, hooks, MCP servers) into a single installable unit
- Distribute a complete workflow to other machines or team members
- Create a reusable, versioned package of Copilot customizations

For individual artifact authoring (agents, skills, instructions, hooks), use the existing publish scripts instead. See [About CLI Plugins](../../explanation/copilot/about-cli-plugins.md) for guidance on when to use plugins vs. manual configuration.

## Before you start

- **Copilot CLI installed**: GA v0.0.420+ (`copilot --version` to verify)
- **Workspace cloned**: The `plugins/` directory should exist at the workspace root
- **Artifacts to bundle**: At minimum, one component (agent, skill, hook, command, MCP server, or LSP server)

---

## Step 1: Create the plugin directory

Create a new CLI plugin directory under `plugins/cli/` named after your plugin:

```powershell
mkdir plugins/cli/my-plugin
```

The directory name should be lowercase, hyphenated (kebab-case), and match the `name` field you'll set in `plugin.json`.

## Step 2: Write plugin.json

Create a `plugin.json` file in the plugin directory with at minimum a `name` field:

```json
{
  "name": "my-plugin",
  "description": "Short description of what this plugin provides",
  "version": "1.0.0"
}
```

Add component path fields to declare which artifacts the plugin bundles:

```json
{
  "name": "my-plugin",
  "description": "Custom workflow with agents and skills",
  "version": "1.0.0",
  "author": "your-org",
  "agents": "agents/",
  "skills": "skills/",
  "hooks": "hooks/"
}
```

The six official component path fields are: `agents`, `skills`, `commands`, `hooks`, `mcpServers`, `lspServers`. See the [CLI Plugin Reference](../../reference/copilot/cli-plugin-reference.md) for the complete `plugin.json` schema.

## Step 3: Add components

Place your customization files in the directories declared by the component paths.

### Self-contained layout (for distribution)

```
plugins/cli/my-plugin/
  plugin.json
  agents/
    my-agent.agent.md
  skills/
    my-skill/
      SKILL.md
  hooks/
    my-hooks.hooks.json
```

### Relative-path layout (for workspace-internal use)

For workspace plugins that reference existing artifacts, use relative paths in `plugin.json`:

```json
{
  "name": "ralph-v2",
  "description": "Ralph v2 orchestration system",
  "version": "0.5.0",
  "agents": "../../agents/ralph-v2/cli/",
  "hooks": "../../hooks/",
  "skills": [
    "../../skills/diataxis/",
    "../../skills/git-atomic-commit/",
    "../../skills/openspec-sdd/"
  ]
}
```

This is the approach used by the workspace's pilot plugin at [plugins/cli/ralph-v2/plugin.json](../../../plugins/cli/ralph-v2/plugin.json). For team distribution, run `publish-plugins.ps1` to create a self-contained bundle — bundling is the default behavior. Use `-SkipBundle` only for development/debugging.

## Step 4: Build a bundle when your plugin uses workspace-relative paths

If your plugin already has a self-contained directory layout, you can install that directory directly.

If your `plugin.json` points at workspace-relative paths such as `../../agents/...` or `../../skills/...`, build the bundle first:

```powershell
pwsh -NoProfile -File scripts/publish/publish-plugins.ps1 -Runtime cli -Plugins my-plugin
```

That command builds a self-contained bundle at `plugins/cli/.build/my-plugin/`.

Use this as your practical contract for local CLI installs:

1. Start with either the self-contained plugin directory or the built bundle directory.
2. Run `copilot plugin install <path>`.
3. Run `copilot plugin list` to confirm discovery.

This matches the supported GitHub Copilot CLI workflow documented in [Creating a plugin for GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-creating) and the [CLI plugin reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-plugin-reference).

## Step 5: Install with `copilot plugin install`

Install the plugin from the plugin directory or built bundle directory:

```bash
copilot plugin install ./plugins/cli/my-plugin
```

If you built a bundle in step 4, install the bundle instead:

```bash
copilot plugin install ./plugins/cli/.build/my-plugin
```

## Step 6: Verify with `copilot plugin list`

Verify the installation:

```bash
copilot plugin list
```

The plugin's agents, skills, and other components are now available in your Copilot CLI sessions.

If you want to use the workspace publish automation as a fallback instead of installing the source directory directly, use it to rebuild the runtime-scoped bundle and then install that local bundle with the supported CLI flow:

```powershell
pwsh -NoProfile -File scripts/publish/publish-plugins.ps1 -Runtime cli -Plugins my-plugin
```

```bash
copilot plugin install ./plugins/cli/.build/my-plugin
```

That workflow keeps `plugins/cli/.build/my-plugin/` as the handoff point. If you inspect Copilot CLI's cache after the install, current local runs may still materialize the payload under `_direct/my-plugin`, but that is storage observation only — not the supported Copilot CLI installation contract.

---

## Working Example: ralph-v2 Pilot Plugin

The workspace includes a pilot plugin at `plugins/cli/ralph-v2/` that demonstrates the relative-path pattern for bundling existing workspace artifacts:

1. **Directory**: `plugins/cli/ralph-v2/`
2. **Manifest**: `plugins/cli/ralph-v2/plugin.json` — references CLI agents, hooks, and selected skills via relative paths
3. **Build for distribution**: `scripts/publish/publish-plugins.ps1 -Runtime cli -Plugins ralph-v2` creates `plugins/cli/.build/ralph-v2/`
4. **Install**: `copilot plugin install ./plugins/cli/.build/ralph-v2`
5. **Verify**: `copilot plugin list`

If you inspect the cache after installing the built bundle, you may still see `_direct/ralph-v2`, but treat that as post-install storage observation rather than the canonical Copilot CLI method.

See [plugins/README.md](../../../plugins/README.md) for the full directory documentation.

---

## Common Tasks

### Install a plugin from a GitHub repository

```bash
copilot plugin install github.com/owner/repo:plugins/cli/plugin-name
```

### Install a specific version from a marketplace

```bash
copilot plugin install @owner/plugin-name@1.0.0
```

### Force reinstall a plugin

```bash
copilot plugin uninstall my-plugin
copilot plugin install ./plugins/cli/my-plugin
```

Or rebuild the bundle and reinstall it:

```powershell
pwsh -NoProfile -File scripts/publish/publish-plugins.ps1 -Plugins my-plugin -Force
```

```bash
copilot plugin install ./plugins/cli/.build/my-plugin
```

> **Note:** Bundling is the default behavior. Use `-SkipBundle` only for development when you want to skip the bundle build step. After any rebuild, re-run `copilot plugin install <path>` and then `copilot plugin list` to verify the updated plugin is the one Copilot CLI sees.

### Temporarily disable a plugin

```bash
copilot plugin disable my-plugin
# Re-enable later:
copilot plugin enable my-plugin
```

### Publish all workspace plugins

```powershell
pwsh -NoProfile -File scripts/publish/publish-plugins.ps1
```

See [publish-plugins.ps1](../../../scripts/publish/publish-plugins.ps1) for all available parameters.

---

## Instruction delivery

Plugins cannot deliver instruction files via `plugin.json` — the `instructions` field does not exist in the schema, and the CLI does not load instructions from installed plugin directories.

The recommended solution is **instruction embedding**: agent source files include `<!-- EMBED: filename -->` markers that are resolved at bundle time by `Merge-AgentInstructions`. This inlines instruction content directly into the agent body, producing self-contained agent files that carry their full workflow, rules, and signal protocol.

```powershell
# Publish the CLI plugin (bundling + embedding is default)
pwsh -NoProfile -File scripts/publish/publish-plugins.ps1 -Runtime cli -Plugins my-plugin
```

For agents that are not embedded (e.g., due to size constraints), deliver instruction files separately:

```powershell
pwsh -NoProfile -File scripts/publish/publish-instructions.ps1
```

See [plugins/README.md](../../../plugins/README.md#instruction-embedding) for the full embedding architecture details.

## Marketplace publishing

Publishing to marketplaces requires marketplace registration. Marketplace infrastructure is **deferred** to a future iteration — plugins are currently distributed via local paths and direct GitHub URL installs.

See the [CLI Plugin Reference](../../reference/copilot/cli-plugin-reference.md#install-spec-patterns) for all install spec patterns.
