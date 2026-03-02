# How to Create a CLI Plugin

This guide walks you through creating a Copilot CLI plugin from scratch — from directory setup through manifest authoring to local installation and validation.

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

Create a new directory under `plugins/` named after your plugin:

```powershell
mkdir plugins/my-plugin
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
plugins/my-plugin/
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

This is the approach used by the workspace's pilot plugin at [plugins/ralph-v2/plugin.json](../../../plugins/ralph-v2/plugin.json). For team distribution, use `publish-plugins.ps1 -Bundle` to create a self-contained copy with all referenced files resolved into the plugin directory.

## Step 4: Install locally

Install the plugin from the local directory:

```bash
copilot plugin install ./plugins/my-plugin
```

Verify the installation:

```bash
copilot plugin list
```

The plugin's agents, skills, and other components are now available in your Copilot CLI sessions.

---

## Working Example: ralph-v2 Pilot Plugin

The workspace includes a pilot plugin at `plugins/ralph-v2/` that demonstrates the relative-path pattern for bundling existing workspace artifacts:

1. **Directory**: `plugins/ralph-v2/`
2. **Manifest**: `plugins/ralph-v2/plugin.json` — references CLI agents, hooks, and selected skills via relative paths
3. **Install**: `copilot plugin install ./plugins/ralph-v2`
4. **Publish script**: `scripts/publish/publish-plugins.ps1 -Plugins ralph-v2`

See [plugins/README.md](../../../plugins/README.md) for the full directory documentation.

---

## Common Tasks

### Install a plugin from a GitHub repository

```bash
copilot plugin install github.com/owner/repo:plugins/plugin-name
```

### Install a specific version from a marketplace

```bash
copilot plugin install @owner/plugin-name@1.0.0
```

### Force reinstall a plugin

```bash
copilot plugin uninstall my-plugin
copilot plugin install ./plugins/my-plugin
```

Or use the publish script with `-Force`:

```powershell
pwsh -NoProfile -File scripts/publish/publish-plugins.ps1 -Plugins my-plugin -Force
```

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

## Marketplace publishing

Publishing to marketplaces requires marketplace registration. Marketplace infrastructure is **deferred** to a future iteration — plugins are currently distributed via local paths and direct GitHub URL installs.

See the [CLI Plugin Reference](../../reference/copilot/cli-plugin-reference.md#install-spec-patterns) for all install spec patterns.
