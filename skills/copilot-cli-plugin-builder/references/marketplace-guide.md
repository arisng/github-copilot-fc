# Plugin Marketplace Guide

## What Are Marketplaces?

Marketplaces are registries of plugins for Copilot CLI. A marketplace is a GitHub repository (or local directory) with a `marketplace.json` file at `.github/plugin/marketplace.json`. Users register marketplaces with the CLI, then browse and install plugins from them.

> [!NOTE]
> The `marketplace.json` format is a **GitHub Copilot CLI-specific convention**. It is *not* part of the open [Agent Plugins 1.0 spec](https://agent-plugins.org) — that spec defines `plugin.json` and `mcp.json` but not marketplaces. The marketplace schema is documented exclusively in the [CLI plugin reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-plugin-reference#marketplacejson).

## File Location

| Location | Description |
|----------|-------------|
| `.github/plugin/marketplace.json` | **Canonical location** — recommended for all new marketplaces |
| `.claude-plugin/marketplace.json` | **Fallback** — also recognized by Copilot CLI for backward compatibility |

Both locations are equivalent. Use `.github/plugin/` for new marketplaces.

## Creating a Marketplace

Create `.github/plugin/marketplace.json` in your repo:

```json
{
  "name": "my-marketplace",
  "owner": {
    "name": "Your Organization",
    "email": "plugins@example.com"
  },
  "metadata": {
    "description": "Curated plugins for our team",
    "version": "1.0.0"
  },
  "plugins": [
    {
      "name": "frontend-design",
      "description": "Create professional GUIs",
      "version": "2.1.0",
      "source": "./plugins/frontend-design"
    },
    {
      "name": "security-checks",
      "description": "Check for security vulnerabilities",
      "version": "1.3.0",
      "source": {
        "source": "github",
        "repo": "my-org/security-tools",
        "ref": "v1.3.0",
        "path": "plugins/security-checks"
      }
    }
  ]
}
```

### Top-Level Schema Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | **Yes** | Kebab-case marketplace name. Max 64 chars. Dots accepted for Agent Plugins 1.0 (e.g., `acme.tools`). This becomes the registration key — there is no option to set a custom local name. |
| `owner` | object | **Yes** | Marketplace owner info: `{ name, email? }`. `email` is optional. |
| `plugins` | array | **Yes** | List of plugin entries (see below). |
| `metadata` | object | No | Optional metadata: `{ description?, version?, pluginRoot? }`. `pluginRoot` overrides the default plugin discovery root. |

### Plugin Entry Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | **Yes** | Kebab-case plugin name. Max 64 chars. Dots accepted for Agent Plugins 1.0. |
| `source` | string \| object | **Yes** | Where to fetch the plugin. See [Plugin Source Types](#plugin-source-types) below. |
| `description` | string | No | Plugin description. Max 1024 chars. |
| `version` | string | No | Plugin version. SemVer recommended. |
| `author` | object | No | Plugin author: `{ name, email?, url? }`. |
| `homepage` | string | No | Plugin homepage URL. |
| `repository` | string | No | Source repository URL. |
| `license` | string | No | License identifier (SPDX recommended). |
| `keywords` | string[] | No | Search and discovery keywords. |
| `category` | string | No | Plugin category (e.g., `"engineering"`, `"security"`). |
| `tags` | string[] | No | Additional tags. |
| `commands` | string \| string[] | No | Path(s) to command directories. |
| `agents` | string \| string[] | No | Path(s) to agent directories. |
| `skills` | string \| string[] | No | Path(s) to skill directories. |
| `hooks` | string \| object | No | Path to hooks config or inline hooks object. |
| `mcpServers` | string \| object | No | MCP server config — inline server map or path to JSON config. Used when the plugin source does not ship its own MCP configuration. |
| `lspServers` | string \| object | No | Path to LSP config or inline server definitions. |
| `strict` | boolean | No | When `true` (default), full schema validation. When `false`, relaxed validation for legacy or direct installs. |

### Plugin Source Types

The `source` field accepts a **relative path string** (relative to the marketplace repo root) or an **object** describing a GitHub or URL source:

#### Relative path (local to marketplace repo)

```json
{ "source": "./plugins/frontend-design" }
```

The `./` prefix is optional — `"plugins/frontend-design"` resolves identically.

#### GitHub source object

```json
{
  "source": {
    "source": "github",
    "repo": "owner/repo",
    "ref": "v1.0.0",
    "path": "plugins/my-plugin"
  }
}
```

#### Pinned commit SHA

```json
{
  "source": {
    "source": "github",
    "repo": "owner/repo",
    "sha": "a94a8fe5ccb19ba61c4c0873d391e987982fbbd3",
    "path": "plugins/my-plugin"
  }
}
```

`sha` must be a full 40-character commit SHA. Pin to a `sha` for reproducible installs immune to force-pushes or tag/branch moves.

## Versioning & Updates

### Three Version Fields, Two Logical Versions

A plugin distributed through a marketplace has **three version fields** across two files — but they represent only **two logical versions**:

```
plugin.json (inside the plugin directory)          marketplace.json (at the marketplace root)
├── version  ← SOURCE OF TRUTH for the plugin      ├── metadata.version  ← catalog version (independent)
                                                   └── plugins[]
                                                       └── version  ← must mirror plugin.json
```

| Field | File | Logical Version | Role |
|-------|------|-----------------|------|
| `plugin.json` → `version` | Plugin directory | **Plugin version** | **Source of truth.** Defines the plugin's own identity. |
| `marketplace.json` → `plugins[].version` | Marketplace root | **Plugin version** (mirror) | **Must match `plugin.json`.** The CLI compares this against the installed version to detect updates. |
| `marketplace.json` → `metadata.version` | Marketplace root | **Catalog version** | Independent. Tracks changes to the marketplace manifest itself (plugins added/removed). |

> [!CRITICAL]
> **`plugins[].version` and `plugin.json` → `version` MUST be kept in sync.** They describe the same plugin. When you bump one, you must bump the other. Drift between them (e.g., `plugin.json` at `0.1.4` while the marketplace entry still shows `0.1.3`) means users will either miss updates or install an unexpected version. This is the most common versioning mistake in multi-plugin marketplaces.

> [!IMPORTANT]
> **`metadata.version` is independent.** Bumping `plugins[].version` does NOT require bumping `metadata.version`, and vice versa. The CLI uses `plugins[].version` for update detection; `metadata.version` is purely informational for the catalog.

### When to Bump the Plugin Version (Both Files)

When you bump the plugin version, update **both** `plugin.json` and the corresponding `marketplace.json` entry:

| Change Type | Bump | SemVer Example | Why |
|-------------|------|----------------|-----|
| Bug fix in a skill, agent, hook, or MCP config | ✅ Patch | `1.0.0` → `1.0.1` | Users won't get the fix without a version bump |
| New feature or new component added | ✅ Minor | `1.0.0` → `1.1.0` | Backward-compatible addition |
| Breaking change (removed skill, renamed agent, changed hook signature) | ✅ Major | `1.0.0` → `2.0.0` | May break existing user workflows |
| Description, typo, or metadata-only edit | ⚠️ Optional | — | No behavioral change; bump only if you want to signal freshness |
| Change to `source` path or target (repo moved, ref changed) | ✅ Yes | Any bump | The install target changed — users need to re-fetch |
| No marketplace (direct local install) | ❌ Not needed | — | `copilot plugin install ./path` loads live from disk; edits take effect on `/restart` |

### Bump Procedure (Atomic, Two-File)

When bumping a plugin version, follow this exact sequence. Both files must be updated together — never one without the other.

1. **Decide the new version** — determine SemVer bump type (patch/minor/major) from the change type table above.
2. **Edit `plugin.json`** — update the `version` field. This is the source of truth.
3. **Edit `marketplace.json`** — update the matching `plugins[]` entry's `version` field to the same value.
4. **Verify alignment** — run the verification script:
   ```bash
   python3 scripts/verify-version-sync.py <marketplace-dir>
   ```
   This checks every `plugins[].version` against its `plugin.json` and exits non-zero on drift. If the script is unavailable, manually confirm both files show the same version string.
5. **Commit atomically** — stage and commit both files in a single commit. Never commit one without the other.

```diff
  # Step 2: plugin.json
- "version": "1.2.0"
+ "version": "1.2.1"

  # Step 3: marketplace.json → plugins[]
- { "name": "my-plugin", "version": "1.2.0", ... }
+ { "name": "my-plugin", "version": "1.2.1", ... }

  # Step 5: single atomic commit
  git add plugin.json .github/plugin/marketplace.json
  git commit -m "bump(my-plugin): 1.2.0 → 1.2.1"
```

### When to Bump the Catalog Version (`metadata.version`)

Bump the marketplace-level version **only** when the catalog structure changes — not when individual plugin source code changes:

| Change Type | Bump `metadata.version`? | Also bump `plugins[].version`? |
|-------------|--------------------------|-------------------------------|
| New plugin added to the marketplace | ✅ Yes | ❌ No (new plugin has its own `1.0.0`) |
| Plugin removed from the marketplace | ✅ Yes | ❌ No |
| Plugin entry metadata changed (description, keywords) | ⚠️ Optional | ⚠️ Optional |
| Plugin source code changed (bug fix, feature) | ❌ **No** | ✅ **Yes** (both `plugin.json` and `plugins[]`) |
| `metadata.description` text changed | ✅ Yes | ❌ No |

**SemVer for `metadata.version`:** Use **minor** bump for structural changes (plugin added/removed). Use **patch** for description-only updates. This version is informational — the CLI does not use it for update detection.

### Multi-Plugin Marketplace: Version Bump Examples

Consider a marketplace with three plugins, each with its own `plugin.json`:

```json
// marketplace.json
{
  "name": "my-tools",
  "metadata": { "description": "Our toolkit", "version": "1.0.0" },
  "plugins": [
    { "name": "formatter", "version": "1.2.0", "source": "./plugins/formatter" },
    { "name": "linter",    "version": "2.0.1", "source": "./plugins/linter" },
    { "name": "analyzer",  "version": "0.5.0", "source": "./plugins/analyzer" }
  ]
}
```

Each plugin's `plugin.json` has a matching version:
```
plugins/formatter/plugin.json  →  "version": "1.2.0"
plugins/linter/plugin.json     →  "version": "2.0.1"
plugins/analyzer/plugin.json   →  "version": "0.5.0"
```

---

**Scenario 1: Bug fix in `linter` only**

```diff
  # marketplace.json — only linter entry changes
  { "name": "linter", "version": "2.0.2", ... }   // ← bumped

  # plugins/linter/plugin.json — must also change
- "version": "2.0.1"
+ "version": "2.0.2"
```
- Only `linter` shows "Update available" for users
- `formatter` and `analyzer` untouched in both files
- `metadata.version` stays at `1.0.0` (catalog didn't change)

---

**Scenario 2: Add a new plugin `deployer` to the marketplace**

```diff
  # marketplace.json
- "metadata": { "version": "1.0.0" }
+ "metadata": { "version": "1.1.0" }           // ← bumped (catalog changed)
  "plugins": [
    ...,
+   { "name": "deployer", "version": "1.0.0", "source": "./plugins/deployer" }
  ]

  # New file: plugins/deployer/plugin.json
+ { "name": "deployer", "version": "1.0.0", ... }
```
- Existing plugins unchanged — no update triggered
- `metadata.version` bumped because the catalog gained a plugin
- `deployer` starts at `1.0.0` in both `plugin.json` and `marketplace.json`

---

**Scenario 3: Breaking change in `formatter` + bug fix in `analyzer`**

Only plugin versions change — no catalog structural change, so `metadata.version` stays at `1.0.0`:

```diff
  # marketplace.json — plugin entries only
  "metadata": { "version": "1.0.0" },           // ← unchanged (no catalog change)
  "plugins": [
-   { "name": "formatter", "version": "1.2.0", ... },
+   { "name": "formatter", "version": "2.0.0", ... },   // ← major bump
    { "name": "linter",    "version": "2.0.2", ... },
-   { "name": "analyzer",  "version": "0.5.0", ... }
+   { "name": "analyzer",  "version": "0.5.1", ... }     // ← patch bump
  ]

  # plugins/formatter/plugin.json — must match marketplace entry
- "version": "1.2.0"
+ "version": "2.0.0"

  # plugins/analyzer/plugin.json — must match marketplace entry
- "version": "0.5.0"
+ "version": "0.5.1"
```

### How Copilot CLI Detects Updates

1. **Marketplace refresh** — `copilot plugin marketplace update` (or `/plugin marketplace refresh`) re-fetches the `marketplace.json` catalog.
2. **Version comparison** — For each installed plugin, the CLI compares the installed version against `plugins[].version` in the refreshed catalog.
3. **Update available** — If the catalog version is newer, the `/plugin` dashboard shows an **Update** action, and `copilot plugin update NAME` pulls the new source.

> [!NOTE]
> Path-sourced plugins from a local marketplace load **live** from their real directory — editing one takes effect on `/restart` or in a new session, with no version bump or `copilot plugin update` needed.

### Auto-Update Behavior

| Marketplace Type | Auto-Update | Details |
|------------------|-------------|---------|
| **Built-in first-party** (`copilot-plugins`, `awesome-copilot`) | ✅ Enabled by default | Plugins auto-update at session start in trusted working directories. Disable with `autoUpdate: false` or `COPILOT_AUTO_UPDATE=false`. Skipped in CI by default. |
| **User-registered** | ❌ Disabled by default | Opt in via `extraKnownMarketplaces` with `"autoUpdate": true` in user settings. Only applies to interactive and `-p` sessions — SDK/server sessions don't auto-update. |
| **Repository-level setting** | ⚠️ Ignored for `autoUpdate` | A repo-level `autoUpdate` is accepted but ignored — it can't enable or redirect auto-update for a marketplace. |
| **Managed (MDM/server) settings** | Overrides user | A managed entry without `autoUpdate: true` removes the user's opt-in. |

## Built-in Marketplaces

| Marketplace | Repository |
|-------------|------------|
| `copilot-plugins` | [github/copilot-plugins](https://github.com/github/copilot-plugins) |
| `awesome-copilot` | [github/awesome-copilot](https://github.com/github/awesome-copilot) |

## CLI Commands

### Register a Marketplace

```bash
copilot plugin marketplace add OWNER/REPO
```

### List Registered Marketplaces

```bash
copilot plugin marketplace list
```

### Browse Marketplace Plugins

```bash
copilot plugin marketplace browse my-marketplace
```

### Refresh Marketplace Index

```bash
copilot plugin marketplace update my-marketplace
```

### Unregister a Marketplace

```bash
copilot plugin marketplace remove my-marketplace
```

## Installing from Marketplaces

```bash
# Install from a marketplace
copilot plugin install my-plugin@my-marketplace

# Install from GitHub repo
copilot plugin install OWNER/REPO

# Install from subdirectory in repo
copilot plugin install OWNER/REPO:PATH/TO/PLUGIN

# Install from Git URL
copilot plugin install https://github.com/o/r.git

# Install from local path
copilot plugin install ./my-plugin
```

## Distributing Your Plugin

1. **Add your plugin to a marketplace repo** (or create your own)
2. **Users register the marketplace:**
   ```bash
   copilot plugin marketplace add OWNER/REPO
   ```
3. **Users browse and install:**
   ```bash
   copilot plugin marketplace browse my-marketplace
   copilot plugin install my-plugin@my-marketplace
   ```

## Plugin Management Commands

| Command | Description |
|---------|-------------|
| `copilot plugin install SPECIFICATION` | Install a plugin |
| `copilot plugin uninstall NAME` | Remove a plugin |
| `copilot plugin list [--json]` | List installed plugins |
| `copilot plugin update NAME [--all]` | Update plugin(s) |
| `copilot plugin enable NAME` | Enable a disabled plugin |
| `copilot plugin disable NAME` | Disable without uninstall |

## In-Session Commands

| Command | Description |
|---------|-------------|
| `/plugin list` | View installed plugins |
| `/plugin install PLUGIN@MARKETPLACE` | Install from session |
| `/agent` | Check loaded agents |
| `/skills list` | View loaded skills |
