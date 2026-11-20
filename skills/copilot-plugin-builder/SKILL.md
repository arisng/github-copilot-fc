---
name: copilot-plugin-builder
description: "Author, scaffold, test, and distribute GitHub Copilot plugins — portable Agent Plugins 1.0 packages (skills, MCP servers) plus Copilot agents, commands, rules, and hooks for the CLI, VS Code, the Copilot app, and the SDK. Use when creating or editing a plugin or its plugin.json, testing locally, distributing or installing via marketplace or Git, migrating a legacy plugin to Agent Plugins 1.0, syncing versions, or building plugins with @github/copilot-sdk. Not for Copilot CLI extensions (tools/commands/canvas via @github/copilot-sdk/extension) — use copilot-extension-builder instead."
metadata:
  version: 0.3.1
---

# Copilot Plugin Builder

Author GitHub Copilot plugins — packages of skills, agents, hooks, and MCP servers that install into Copilot CLI, VS Code (Agents Window), the GitHub Copilot desktop app, and the Copilot SDK.

Agent Plugins 1.0 went generally available on 2026-08-12 across VS Code, Copilot CLI, the Copilot SDK, and the Copilot app, on all Copilot plans. Build one package; compatible clients load the portable parts.

## Plugin Architecture

Plugins are **file-based** (markdown + JSON). No compilation required. Two Copilot formats:

| Format | Marker | Use |
|--------|--------|-----|
| **Agent Plugins 1.0** | `$schema: https://agent-plugins.org/schemas/1.0.0/plugin.schema.json` | Recommended — portable across Copilot runtimes and other Agent Plugins clients |
| **Legacy Copilot** | No `$schema` | Still supported (no migration required); use only when custom component paths are needed |

Always use **Agent Plugins 1.0** unless the user has a specific reason for the legacy format.

> Legacy **Copilot Extensions** (the GitHub App–based tools/commands/canvas platform) are a different artifact: sunset 2025-11-10, with plugins as the replacement.

### Portability model

| Component | Location (Agent Plugins 1.0) | Portable |
|-----------|------------------------------|----------|
| Skills | `skills/<name>/SKILL.md` | Yes — Agent Skills spec |
| MCP servers | `mcp.json` | Yes — MCP spec |
| Agents | `com.github.copilot/agents/*.agent.md` | No — Copilot namespace |
| Commands | `com.github.copilot/commands/` | No |
| Rules | `com.github.copilot/rules/` | No |
| Hooks | `com.github.copilot/hooks/hooks.json` | No |
| LSP servers | `com.github.copilot/lsp.json` | No |
| Automation templates | `automations/*.automation.md` (VS Code) | No |
| Canvases / other extensions | loaded by CLI and Copilot app | No |

Clients ignore namespaces they don't implement (for example `com.example.client/`), so Copilot-specific components never block portability.

## Repo Layout: One Plugin or Many

Decide the repo layout before scaffolding — it fixes where `plugin.json` lives, how users install, and what marketplace entries point at. Layout is independent of manifest format: Agent Plugins 1.0 and legacy both work in either layout.

**Single-plugin repo** — the plugin is the repo:

```text
my-plugin/                      ← repository root
├── plugin.json
├── skills/
└── com.github.copilot/
```

- `copilot plugin install OWNER/REPO` works directly — the repo root must be the plugin root.
- One manifest, one version, no catalog required. Default for a first plugin.

**Multi-plugin repo** — related plugins share one repo behind one catalog:

```text
skills-repo/                    ← repository root
├── .github/plugin/marketplace.json
└── plugins/
    ├── formatter/plugin.json
    └── linter/plugin.json
```

- Direct installs carry a path: `copilot plugin install OWNER/REPO:plugins/formatter`.
- The catalog gives each plugin a flat identity: an entry like `{ "name": "formatter", "version": "1.2.0", "source": "./plugins/formatter" }` lets users run `copilot plugin install formatter@my-marketplace`.
- Each plugin versions independently; adding one touches only its directory plus its catalog entry.
- The catalog may live in the same repo (relative `source` paths) or in a separate catalog repo (GitHub `source` objects).

Reach for multi-plugin only once a second plugin is planned or you want one register-and-browse catalog for a family of plugins — until then the root layout costs nothing. Real example: [dotnet/skills](https://github.com/dotnet/skills) keeps its domain plugins (ASP.NET Core, MAUI, test, upgrade, …) under `plugins/` behind a single catalog; a new skill joins the best-matching domain plugin, and a new plugin is created only when no domain fits. Moving an existing plugin out of the repo root changes every install path and catalog `source` — ship that as a breaking change.

## Plugin Directory Layout (Agent Plugins 1.0)

```text
my-plugin/
├── plugin.json                    # Required manifest (with Agent Plugins $schema)
├── skills/                        # Portable skills (immediate subdirectories only)
│   └── skill-name/
│       └── SKILL.md
├── mcp.json                       # Portable MCP server configs (fixed location)
├── automations/                   # VS Code automation templates (*.automation.md)
├── scripts/                       # Hook/MCP support files (referenced via ${PLUGIN_ROOT})
└── com.github.copilot/            # Copilot-specific components
    ├── agents/
    │   └── my-agent.agent.md
    ├── commands/
    ├── rules/
    ├── hooks/
    │   └── hooks.json
    └── lsp.json
```

Minimal plugin: just `plugin.json` + one component (for example a skill, agent, hook, command, MCP server, or LSP config).

## Workflow

### Phase 1: Gather Requirements

Ask the user these questions (one at a time, skip if already specified):

1. **What should the plugin do?** — Get a clear purpose statement
2. **Which components?** — Skills, agents, hooks, commands, MCP servers, or a combination
3. **Which runtimes?** — Copilot CLI, VS Code/Agents Window, Copilot app, SDK (drives the test matrix)
4. **Plugin name?** — 1–64 chars, lowercase ASCII letters, digits, hyphens, periods
5. **One plugin or a family?** — Repo Layout decides where it lives; default to single-plugin

If unsure about components, suggest the simplest approach: a single skill.

### Phase 2: Scaffold the Plugin

Place the plugin per **Repo Layout** above — repository root for a single-plugin repo, `plugins/<name>/` for a multi-plugin repo — then create its component structure with `plugin.json`:

```json
{
  "$schema": "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json",
  "name": "my-plugin",
  "version": "1.0.0",
  "description": "What this plugin does",
  "author": { "name": "Your Name" },
  "license": "MIT",
  "keywords": ["relevant", "tags"]
}
```

Rules:

- Allowed top-level fields: `$schema`, `name`, `version`, `description`, `author`, `homepage`, `repository`, `license`, `keywords`, `extensions`. Unknown fields are reported and ignored.
- `extensions` holds client-specific manifest data keyed by reverse-domain namespace (for example `"extensions": { "com.github.copilot": { ... } }`).
- In Agent Plugins 1.0, component locations are fixed — you cannot override them in `plugin.json`. Legacy format plugins may use component path fields instead.

Then author each component — see Phase 3 below.

### Phase 3: Author Components

#### Skills

Skills inject context/instructions into the agent via `SKILL.md`:

```markdown
---
name: my-skill
description: When and why to use this skill
---

# Instructions

Be concise. Use imperative form. Include only what the model doesn't already know.
```

Skills must be immediate subdirectories of `skills/`, and the directory name must match the frontmatter `name` (plain kebab-case, no namespace prefix — invalid names are silently skipped). Follow skill-creator patterns for scripts/, references/, assets/.

#### Custom Agents

Agents are scoped sub-agents with isolated tools and prompts. Define as `.agent.md` files in `com.github.copilot/agents/`:

```markdown
---
name: my-agent
displayName: My Agent
description: What this agent does (used by runtime for intent matching)
tools:
  - grep
  - glob
  - view
---

You are a specialized agent. Your role is to...
```

Or programmatically via the SDK — see `references/sdk-examples.md`.

#### Hooks

Hooks are client-specific and fire at lifecycle points. In Agent Plugins 1.0, create `com.github.copilot/hooks/hooks.json` (legacy format: `hooks.json` at the plugin root):

```json
{
  "version": 1,
  "hooks": {
    "sessionStart": [
      { "type": "command", "command": "./scripts/init.sh", "timeoutSec": 10 }
    ],
    "preToolUse": [
      { "type": "command", "command": "./scripts/validate.sh", "timeoutSec": 5 }
    ]
  }
}
```

Supported events: `agentStop`, `errorOccurred`, `notification`, `permissionRequest`, `postToolUse`, `postToolUseFailure`, `preCompact`, `preToolUse`, `sessionEnd`, `sessionStart`, `subagentStart`, `subagentStop`, `userPromptSubmitted`, `userPromptTransformed`. Use `timeoutSec` (default 30; `timeout` is an alias). For payloads, matchers, payload formats (camelCase vs PascalCase/VS Code-compatible), and SDK hook registration, see `references/hook-lifecycle.md`.

#### Automation templates (VS Code)

Reusable prompt + schedule templates in `automations/*.automation.md` with YAML frontmatter (`version`, `id`, `name`, `schedule`). Templates only seed the New Automation dialog — they cannot auto-start. Extra folders via `extensions.com.github.copilot.automations.paths`.

#### MCP Servers

External tool providers. Create `mcp.json` at plugin root:

```json
{
  "$schema": "https://agent-plugins.org/schemas/1.0.0/mcp.schema.json",
  "mcpServers": {
    "my-server": {
      "type": "stdio",
      "command": "node",
      "args": ["${PLUGIN_ROOT}/server/index.js"],
      "env": { "DATA_DIR": "${PLUGIN_DATA}" }
    }
  }
}
```

Transports: `stdio`, `streamable-http`, `sse` (deprecated). Variables: `${PLUGIN_ROOT}` (package root), `${PLUGIN_DATA}` (writable state that persists across updates). For `stdio`, Copilot CLI also provides these as environment variables.

### Phase 4: Install and Test

Test in every runtime the plugin targets. Hooks and MCP servers execute local code — review them before installing anything from a community marketplace.

**Copilot CLI:**

```bash
copilot plugin install ./my-plugin   # local install
copilot plugin list                  # verify loaded
```

Then in an interactive session: `/plugin list`, `/skills list`, `/agent`.

Components are cached — re-run `copilot plugin install ./my-plugin` after edits. Uninstall by the `name` field from `plugin.json`, not the directory path.

**VS Code / Agents Window:**

- Ensure `chat.plugins.enabled` is `true`.
- Install via Extensions view (`@agentPlugins`), Command Palette **Chat: Install Plugin From Source**, or the Agent Customizations editor's Plugins page.
- For local development, register the path with `chat.pluginLocations` (Experimental): `{ "/path/to/my-plugin": true }`.
- VS Code automatically discovers plugins installed by Copilot CLI from `~/.copilot/installed-plugins/` (marketplace subfolders plus a `_direct` bucket for Git-URL installs).
- Verify components appear: skills in **Configure Skills**, MCP servers in the tools list, agents in the picker, hooks fire on their events.

**Copilot app:** install from the `awesome-copilot` marketplace (registered by default).

**Copilot SDK:** load a plugin programmatically — see `references/sdk-examples.md`.

### Phase 5: Distribute

**Local development:**

```bash
copilot plugin install ./my-plugin
```

**From GitHub repo:**

```bash
copilot plugin install OWNER/REPO
copilot plugin install OWNER/REPO:PATH/TO/PLUGIN
```

**Via marketplace:** users register and browse with:

```bash
copilot plugin marketplace add OWNER/REPO      # or a local path / .git URL
copilot plugin marketplace browse my-marketplace
copilot plugin install my-plugin@my-marketplace
```

In VS Code, marketplaces are configured with `chat.plugins.marketplaces` (shorthand `owner/repo`, `.git` URL, SCP-style remote, or `file:` URI; pin with `#<ref>` or a full 40-character commit SHA). Organizations govern plugins with `enabledPlugins`, `extraKnownMarketplaces`, and `strictKnownMarketplaces` in `managed-settings.json` across VS Code, CLI, the Copilot app, and Copilot cloud agent.

### Maintain the Catalog

Nothing generates `marketplace.json` — it is a hand-maintained index of the repo's plugin directories. On any plugin addition, removal, rename, or description edit, land the catalog edit in the same commit, holding these invariants:

- Every plugin directory has exactly one entry, and every entry resolves to a plugin directory. An unlisted plugin is an **orphan**: invisible to `marketplace browse`, installable only by full path.
- Entry `name` and `description` mirror the plugin's `plugin.json`; `source` points at its directory.
- Entry `version`, when present, mirrors `plugin.json` (see Version Bump).

Verify the catalog against the repo:

```bash
python3 scripts/verify-version-sync.py <marketplace-dir>
```

The script exits non-zero on version or name drift and warns on orphans, description divergence, and unresolvable sources. For schema, source types, versioning, and multi-host catalogs (one catalog per host), see `references/marketplace-guide.md` → "Maintaining the Catalog".

### Version Bump

When bumping a plugin's version, **always update both files atomically**:

1. `plugin.json` → `version` (source of truth)
2. `marketplace.json` → `plugins[name=X].version` (when your entries carry `version`, it must mirror plugin.json)

When present, these MUST match. Drift causes users to miss updates or install unexpected versions. See `references/marketplace-guide.md` → "Bump Procedure" for the full checklist including verification and commit steps.

## Submission Review

**Trigger: use before shipping any plugin.** Run the sectioned PASS/FAIL checklist in
[references/submission-review.md](references/submission-review.md) — manifest validity,
cross-file consistency, component discoverability, frontmatter completeness, README
quality, and release readiness (stable bundle via `-OutputRoot`, marketplace version
parity, throwaway `COPILOT_HOME` install smoke). Report one
`[PASS]/[FAIL] <section>: <evidence>` line per section plus a prioritized fix list.

The plugin's root `README.md` must follow
[references/plugin-readme-template.md](references/plugin-readme-template.md)
(Installation / Quick start / How it works / Components / License) — the review's README
section grades against it.

## SDK Usage

The `@github/copilot-sdk` provides programmatic control via JSON-RPC. Supports 6 languages: TypeScript, Python, Go, .NET, Rust, Java. Agent Plugins 1.0 support is generally available in the SDK, and the SDK manages CLI process lifecycle automatically.

Quick start (TypeScript):

```typescript
import { CopilotClient, approveAll } from "@github/copilot-sdk";

const client = new CopilotClient();
await client.start();
const session = await client.createSession({
    model: "auto",
    onPermissionRequest: approveAll,
});
const response = await session.sendAndWait({ prompt: "Hello" });
console.log(response?.data.content);
await client.stop();
```

For SDK examples in all languages, custom tools, streaming, plugin loading, and MCP configuration, see `references/sdk-examples.md`.

## Authoritative Sources

- [Agent Plugins specification](https://agent-plugins.org/) — portable format, schemas, governance
- [Agent plugins in VS Code](https://code.visualstudio.com/docs/agent-customization/agent-plugins) — discovery, install, marketplaces, settings, troubleshooting
- [Agent plugin authoring reference](https://code.visualstudio.com/docs/agents/reference/agent-plugin-reference) — manifest fields, formats, hooks, automations, cross-tool compatibility
- [Agent Plugins 1.0 changelog (2026-08-12)](https://github.blog/changelog/2026-08-12-agent-plugins-1-0-in-vs-code-copilot-cli-and-the-copilot-app/) — GA scope, migration, enterprise settings
- [Finding and installing plugins (Copilot CLI)](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-finding-installing) — CLI install/marketplace commands
- [Creating a plugin (Copilot CLI)](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-creating) — format selection, structure, test loop
- [GitHub Copilot hooks reference](https://docs.github.com/en/copilot/reference/hooks-reference) — hook events, payloads, command-hook format

## References

- [references/plugin-manifest.md](references/plugin-manifest.md) — Full manifest schema, fields, and validation
- [references/sdk-examples.md](references/sdk-examples.md) — SDK usage in all 6 languages with custom tools, streaming, plugin loading, MCP
- [references/hook-lifecycle.md](references/hook-lifecycle.md) — All hook events with input/output signatures
- [references/marketplace-guide.md](references/marketplace-guide.md) — Marketplace schema, catalog maintenance, versioning, and distribution
- [references/submission-review.md](references/submission-review.md) — PASS/FAIL checklist to run before a plugin ships
- [references/plugin-readme-template.md](references/plugin-readme-template.md) — Consumer-facing README template (Installation, Quick start, Components, License)
