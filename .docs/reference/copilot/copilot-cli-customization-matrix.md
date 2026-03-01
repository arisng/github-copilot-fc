# Copilot-CLI Customization Support Matrix

> **Last verified**: GA v0.0.420 (February 2026)
> **Changelog**: [GitHub Copilot CLI — Generally Available](https://github.blog/changelog/2026-02-25-github-copilot-cli-is-now-generally-available/)
> **Minimum version**: v0.0.400+ (GA release, February 2026)

This reference maps the workspace's 6 artifact types against GitHub Copilot CLI support status, and maps the CLI's 8 customization features back to workspace equivalents.

---

## Workspace Artifacts → Copilot-CLI Equivalents

| Workspace Artifact | CLI Equivalent | CLI Discovery Path | Status | Publish Script | Action Items |
|--------------------|----------------|--------------------|--------|----------------|--------------|
| **Agents** (`agents/*.agent.md`) | Custom Agents | `~/.copilot/agents/*.agent.md` or `.github/agents/` | **Supported** | `publish-agents.ps1` — already targets `~/.copilot/agents/` ✓ | Frontmatter schema differs: no `agents:`, `argument-hint:`, `user-invocable:`; has `infer`, `model`, `mcpServers`. See [Schema Differences](#agent-frontmatter-schema-differences). |
| **Instructions** (`instructions/*.instructions.md`) | Custom Instructions | `$HOME/.copilot/copilot-instructions.md` (single file) or `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` | **Supported** (different path model) | `publish-instructions.ps1` — **GAP**: only targets VS Code dirs. Needs redesign for CLI's single-file or env-var model. | `~/.copilot/instructions/` is **NOT** a valid path. Options: (a) concatenate into single file, (b) use `COPILOT_CUSTOM_INSTRUCTIONS_DIRS`. |
| **Skills** (`skills/*/SKILL.md`) | Skills | `~/.copilot/skills/` | **Supported** | `publish-skills.ps1` — already targets `~/.copilot/skills/` ✓ | No changes needed. |
| **Prompts** (`prompts/*.prompt.md`) | — | Not documented | **Not documented** | `publish-prompts.ps1` — VS Code only | No CLI discovery for `.prompt.md` files. Skills largely replace prompts in CLI. |
| **Hooks** (`hooks/*.hooks.json`) | Hooks | CWD (repo-level) or via plugins | **Supported** (same JSON schema) | `publish-hooks.ps1` — publishes to `.github/hooks/` ✓ | Same `{ "version": 1, "hooks": { ... } }` JSON schema. Works in CLI if placed in CWD or packaged as plugin. |
| **Toolsets** (`toolsets/*.toolsets.jsonc`) | CLI flags + agent `tools:` + hooks | N/A (no file format) | **Not supported** as file format | `publish-toolsets.ps1` — VS Code only | Equivalent control via `--allow-tool`, `--deny-tool`, agent `tools:` filtering, and `preToolUse` hooks. See [Tool Restriction Mechanisms](#tool-restriction-mechanisms). |

---

## Copilot-CLI Features → Workspace Mapping

The [official comparison page](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/comparing-cli-features) lists 8 customization features.

| # | CLI Feature | Workspace Equivalent | Notes |
|---|-------------|---------------------|-------|
| 1 | **Custom Agents** | `agents/*.agent.md` | Schema overlap with differences. Agents are discoverable from `~/.copilot/agents/` and `.github/agents/`. |
| 2 | **Custom Instructions** | `instructions/*.instructions.md` | CLI uses single-file `$HOME/.copilot/copilot-instructions.md` or `COPILOT_CUSTOM_INSTRUCTIONS_DIRS`. Also loads `.github/copilot-instructions.md` and `.github/instructions/**/*.instructions.md` with `applyTo`. |
| 3 | **Skills** | `skills/*/SKILL.md` | Direct match. Same `~/.copilot/skills/` discovery path. |
| 4 | **Tools / MCP Servers** | `toolsets/*.toolsets.jsonc` (partial) | MCP servers configured in `~/.copilot/mcp-config.json` are auto-discovered. Agent `mcpServers` frontmatter bundles MCP servers per-agent. Toolsets have no direct file equivalent; use CLI flags and agent `tools:` filtering instead. |
| 5 | **Hooks** | `hooks/*.hooks.json` | Same JSON schema as VS Code. Supported lifecycle events: `sessionStart`, `sessionEnd`, `userPromptSubmitted`, `preToolUse`, `postToolUse`, `errorOccurred`. `preToolUse` can `deny`/`allow`/`ask`. |
| 6 | **Subagents** | `agents:` frontmatter key | **Different mechanism.** CLI uses `infer: true` + TaskTool auto-delegation, NOT the `agents:` array key. The `agents:` key is silently ignored in CLI. |
| 7 | **Custom Agents** (invocation) | Agent modes in VS Code | CLI: `/agent <name>` or `--agent <name>`. VS Code: `@agent` in chat. |
| 8 | **Plugins** | No workspace equivalent | CLI-only packaging system. Plugins bundle agents, skills, hooks, and MCP servers. Installed via `/plugin install`. |

---

## Agent Frontmatter Schema Differences

| Property | Type | Copilot-CLI | VS Code | Notes |
|----------|------|:-----------:|:-------:|-------|
| `name` | string | ✅ | ✅ | Derived from filename if omitted in CLI |
| `description` | string | ✅ | ✅ (required) | |
| `instructions` | string | ✅ | ✅ | Markdown body content |
| `tools` | array | ✅ | ✅ | Whitelist/blacklist filtering in CLI |
| `model` | string | ✅ | ❌ | CLI-only: override default model |
| `infer` | boolean | ✅ | ❌ | CLI-only: controls TaskTool visibility (default: `true`) |
| `mcpServers` | object | ✅ | ❌ | CLI-only: agent-bundled MCP servers |
| `agents` | array | ❌ | ✅ | VS Code-only: subagent declarations |
| `argument-hint` | string | ❌ | ✅ | VS Code-only |
| `user-invocable` | boolean | ❌ | ✅ | VS Code-only |

Unrecognized frontmatter fields are **silently ignored** in both platforms — agents degrade gracefully, not with errors.

---

## Tool Namespace Remapping

Built-in tools use different names across platforms.

| VS Code Tool | Copilot-CLI Tool | Notes |
|-------------|------------------|-------|
| `execute/runInTerminal` | `bash` (or PowerShell on Windows) | Shell command execution |
| `read/readFile` | `view` | File reading |
| `edit/editFiles` | `edit` | File editing |
| (file creation) | `create` | File creation |
| `search` | Built-in search | Codebase search |
| `agent` | `task` (TaskTool) | Subagent delegation |
| `web` | **No built-in equivalent** | Use MCP servers (Brave Search, etc.) or shell `curl` |
| `vscode/memory` | **No equivalent** | CLI has implicit memory (automatic, not programmatic) |
| `execute/testFailure` | **No equivalent** | Use shell-based test execution |
| `execute/runTests` | **No equivalent** | Use shell-based test execution |

Tool filtering in CLI uses glob patterns: `--allow-tool "shell(npm run test:*)"`, `--deny-tool "shell(rm *)"`.

---

## Tool Restriction Mechanisms

The CLI provides multiple tool restriction mechanisms that replace `.toolsets.jsonc`:

| Mechanism | Scope | Example |
|-----------|-------|---------|
| `--allow-tool` / `--deny-tool` | Session-wide (CLI flags) | `--deny-tool "shell(rm *)"` |
| `--available-tools` / `--excluded-tools` | Session-wide (CLI flags) | `--available-tools "edit,view"` |
| Agent `tools:` frontmatter | Per-agent (whitelist/blacklist) | `tools: [edit, view, -bash]` |
| `preToolUse` hooks | Per-invocation (programmatic) | Script returns `deny` / `allow` / `ask` |
| MCP server `tools:` config | Per-MCP-server | `"tools": ["search_*"]` |
| `--disable-mcp-server` | Session-wide | `--disable-mcp-server brave` |
| `--disable-builtin-mcps` | Session-wide | Disables built-in GitHub MCP |

Deny rules take precedence over allow rules (safe defaults).

---

## Hook Lifecycle Events

Both VS Code and Copilot-CLI support the same hook lifecycle events and JSON schema:

| Event | Trigger | Can Modify Behavior |
|-------|---------|:-------------------:|
| `sessionStart` | Session begins or resumes | No |
| `sessionEnd` | Session completes/terminates | No |
| `userPromptSubmitted` | User submits prompt | No |
| `preToolUse` | Before any tool execution | **Yes** (`deny` / `allow` / `ask`) |
| `postToolUse` | After tool execution | No |
| `errorOccurred` | Error during execution | No |

Hook config format: `{ "version": 1, "hooks": { "<event>": [{ "bash": "...", "powershell": "...", "cwd": "...", "timeout": ... }] } }`

---

## Version Requirements

| Feature | Minimum Version | Source |
|---------|-----------------|--------|
| Custom agents | October 2025 | [Changelog (2025-10-28)](https://github.blog/changelog/2025-10-28-github-copilot-cli-use-custom-agents-and-delegate-to-copilot-coding-agent/) |
| Skills | December 2025 | [Changelog (2025-12-18)](https://github.blog/changelog/2025-12-18-github-copilot-now-supports-agent-skills/) |
| Hooks (`preToolUse`) | February 2026 (GA) | [GA Announcement](https://github.blog/changelog/2026-02-25-github-copilot-cli-is-now-generally-available/) |
| All features | **v0.0.400+** (GA) | GA release, February 2026 |

---

## Configuration Override

The default configuration directory `~/.copilot/` can be overridden:

- **CLI flag**: `--config-dir <directory>`
- **Environment variable**: `XDG_CONFIG_HOME` (path becomes `$XDG_CONFIG_HOME/.copilot/`)
- **Config file**: `config-dir` key in `~/.copilot/config.json`

This redirects the entire `~/.copilot/` tree (agents, skills, MCP config, instructions, logs, sessions).

---

## Quick Reference Links

| Category | Document | Path |
|----------|----------|------|
| **How-to** | Publish customizations for Copilot CLI | `.docs/how-to/copilot/how-to-publish-customizations-for-copilot-cli.md` |
| **Explanation** | CLI vs VS Code customization differences | `.docs/explanation/copilot/copilot-cli-vs-vscode-customization.md` |
| **Explanation** | Ralph-v2 tool compatibility | `.docs/explanation/copilot/copilot-cli-ralph-v2-tool-compatibility.md` |
| **External** | Official comparing CLI features | [docs.github.com](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/comparing-cli-features) |
| **External** | Custom agents docs | [docs.github.com](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/create-custom-agents) |
| **External** | Custom instructions docs | [docs.github.com](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-custom-instructions) |
| **External** | Skills docs | [docs.github.com](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/create-skills) |
| **External** | Hooks reference | [docs.github.com](https://docs.github.com/en/copilot/reference/hooks-configuration) |
| **External** | Copilot CLI changelog | [github.blog/changelog](https://github.blog/changelog/2026-02-25-github-copilot-cli-is-now-generally-available/) |
