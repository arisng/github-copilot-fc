# Copilot-CLI Customization Support Matrix

> **Last verified**: GA v0.0.420 (February 2026)
> **Changelog**: [GitHub Copilot CLI — Generally Available](https://github.blog/changelog/2026-02-25-github-copilot-cli-is-now-generally-available/)
> **Minimum version**: v0.0.400+ (GA release, February 2026)

This reference maps the workspace's 6 artifact types against GitHub Copilot CLI support status, and maps the CLI's 8 customization features back to workspace equivalents.

The product GitHub Copilot CLI uses `target: github-copilot` in custom agent frontmatter.

---

## References (Official Documentation)

Periodically verify against the official documentation to ensure accuracy, as the CLI is rapidly evolving and may have discrepancies or silent changes:
[Overview of customizing GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/quickstart-for-customizing)
[Custom agents configuration](https://docs.github.com/en/copilot/reference/custom-agents-configuration)
[Hook Configuration](https://docs.github.com/en/copilot/reference/hooks-configuration)
[Support for different types of custom instructions](https://docs.github.com/en/copilot/reference/custom-instructions-support)
[GitHub Copilot CLI plugin reference](https://docs.github.com/en/copilot/reference/cli-plugin-reference)
[GitHub Copilot CLI command reference](https://docs.github.com/en/copilot/reference/cli-command-reference)
[Copilot customization cheat sheet](https://docs.github.com/en/copilot/reference/customization-cheat-sheet)

## Workspace Artifacts → Copilot-CLI Equivalents

| Workspace Artifact                                  | CLI Equivalent                     | CLI Discovery Path                                                                           | Status                               | Publish Script                                                                                                          | Action Items                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| --------------------------------------------------- | ---------------------------------- | -------------------------------------------------------------------------------------------- | ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Agents** (`agents/*.agent.md`)                    | Custom Agents                      | `~/.copilot/agents/*.agent.md` or `.github/agents/`                                          | **Supported**                        | `publish-agents.ps1` — already targets `~/.copilot/agents/` ✓                                                           | Frontmatter schema differs: no `agents:`, `argument-hint:`; has `disable-model-invocation`, `mcp-servers`, `target`. `infer` is retired. `model` is silently ignored. See [Schema Differences](#agent-frontmatter-schema-differences). **Variant model (iteration 2):** Agents are [not shareable](runtime-support-framework.md#agents--not-shareable-) across runtimes due to frontmatter, tool namespace, and body-level incompatibilities. Per-runtime variants are required — the workspace uses a nested subdirectory convention (`agents/ralph-v2/vscode/` for VS Code, `agents/ralph-v2/cli/` for copilot-cli) with shared `.instructions.md` files containing runtime-agnostic logic. See [agent-variant-proposal.md](agent-variant-proposal.md) and [runtime-support-framework.md](runtime-support-framework.md) for the full design. |
| **Instructions** (`instructions/*.instructions.md`) | Custom Instructions                | `AGENTS.md` (CWD, repo root, `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` dirs), `CLAUDE.md` / `GEMINI.md` (repo root), `$HOME/.copilot/copilot-instructions.md` (single file), `COPILOT_CUSTOM_INSTRUCTIONS_DIRS`, `.github/copilot-instructions.md`, `.github/instructions/**/*.instructions.md` | **Supported** (different path model) | `publish-instructions.ps1` — **GAP**: only targets VS Code dirs. Needs redesign for CLI's single-file or env-var model. | `AGENTS.md` is a primary repo-level instruction file discovered in CWD, repo root, and `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` directories. `CLAUDE.md` and `GEMINI.md` are also recognized at repo root. `~/.copilot/instructions/` is **NOT** a valid path. Options: (a) concatenate into single file, (b) use `COPILOT_CUSTOM_INSTRUCTIONS_DIRS`. The `excludeAgent` frontmatter keyword (values: `"code-review"`, `"coding-agent"`) can scope `.github/instructions/*.instructions.md` files to exclude specific agents. Use `--no-custom-instructions` CLI flag to disable loading of all instruction files. |
| **Skills** (`skills/*/SKILL.md`)                    | Skills                             | `~/.copilot/skills/`                                                                         | **Supported**                        | `publish-skills.ps1` — already targets `~/.copilot/skills/` ✓                                                           | No changes needed.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| **Prompts** (`prompts/*.prompt.md`)                 | —                                  | Not documented                                                                               | **Not documented**                   | `publish-prompts.ps1` — VS Code only                                                                                    | No CLI discovery for `.prompt.md` files. Skills largely replace prompts in CLI.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| **Hooks** (`hooks/<name>/<name>.hooks.json`)                    | Hooks                              | CWD (repo-level) or via plugins                                                              | **Supported** (same JSON schema)     | `publish-hooks.ps1` — publishes to `.github/hooks/` ✓                                                                   | Same `{ "version": 1, "hooks": { ... } }` JSON schema. Works in CLI if placed in CWD or packaged as plugin.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| **Toolsets** (`toolsets/*.toolsets.jsonc`)          | CLI flags + agent `tools:` + hooks | N/A (no file format)                                                                         | **Not supported** as file format     | `publish-toolsets.ps1` — VS Code only                                                                                   | Equivalent control via `--allow-tool`, `--deny-tool`, agent `tools:` filtering, and `preToolUse` hooks. See [Tool Restriction Mechanisms](#tool-restriction-mechanisms).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |

---

## Copilot-CLI Features → Workspace Mapping

The [official comparison page](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/comparing-cli-features) lists 8 customization features.

| #   | CLI Feature                    | Workspace Equivalent                  | Notes                                                                                                                                                                                                                                  |
| --- | ------------------------------ | ------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | **Custom Agents**              | `agents/*.agent.md`                   | Schema overlap with differences. Agents are discoverable from `~/.copilot/agents/` and `.github/agents/`.                                                                                                                              |
| 2   | **Custom Instructions**        | `instructions/*.instructions.md`      | CLI loads instructions from: `AGENTS.md` (CWD, repo root, `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` dirs), `CLAUDE.md` / `GEMINI.md` (repo root), `$HOME/.copilot/copilot-instructions.md`, `COPILOT_CUSTOM_INSTRUCTIONS_DIRS`, `.github/copilot-instructions.md`, and `.github/instructions/**/*.instructions.md` (with `applyTo` and `excludeAgent`). Use `--no-custom-instructions` flag to disable all. |
| 3   | **Skills**                     | `skills/*/SKILL.md`                   | Direct match. Same `~/.copilot/skills/` discovery path.                                                                                                                                                                                |
| 4   | **Tools / MCP Servers**        | `toolsets/*.toolsets.jsonc` (partial) | MCP servers configured in `~/.copilot/mcp-config.json` are auto-discovered. Agent `mcp-servers` frontmatter bundles MCP servers per-agent. Toolsets have no direct file equivalent; use CLI flags and agent `tools:` filtering instead. Use `--additional-mcp-config <path>` to load extra MCP config files. Interactive MCP management via `/mcp` commands (see [MCP Interactive Commands](#mcp-interactive-commands)). |
| 5   | **Hooks**                      | `hooks/<name>/<name>.hooks.json`                  | Same JSON schema as VS Code. Supported lifecycle events: `sessionStart`, `sessionEnd`, `agentStop`, `subagentStop`, `userPromptSubmitted`, `preToolUse`, `postToolUse`, `errorOccurred`. `preToolUse` can `deny`/`allow`/`ask`.                                     |
| 6   | **Subagents**                  | `agents:` frontmatter key             | **Different mechanism.** CLI uses runtime-managed delegation plus `disable-model-invocation` eligibility, NOT the `agents:` array key. The `agents:` key is silently ignored in CLI. |
| 7   | **Custom Agents** (invocation) | Agent modes in VS Code                | CLI: `/agent <name>` or `--agent <name>`. VS Code: `@agent` in chat.                                                                                                                                                                   |
| 8   | **Plugins**                    | `plugins/<runtime>/<name>/plugin.json` | CLI packaging system bundling agents, skills, hooks, and MCP servers into distributable units. Manifest schema (6 official component fields): `name` (required), plus optional `description`, `version`, `author {name}`, `agents`, `skills`, `commands`, `hooks`, `mcpServers`, `lspServers`. `strict` is NOT a plugin.json field (marketplace.json only). Install via `copilot plugin install ./plugins/cli/<name>`. Workspace pilot: `plugins/cli/ralph-v2/`. See [CLI Plugin Reference](cli-plugin-reference.md) and [publish-plugins.ps1](../../../scripts/publish/publish-plugins.ps1). |

---

## Agent Frontmatter Schema Differences

| Property                    | Type    |   Copilot-CLI    |   VS Code    | Notes                                                                                                                         |
| --------------------------- | ------- | :--------------: | :----------: | ----------------------------------------------------------------------------------------------------------------------------- |
| `name`                      | string  |        ✅         |      ✅       | Derived from filename if omitted in CLI                                                                                       |
| `description`               | string  |        ✅         | ✅ (required) |                                                                                                                               |
| `instructions`              | string  |        ✅         |      ✅       | Markdown body content                                                                                                         |
| `tools`                     | array   |        ✅         |      ✅       | Whitelist/blacklist filtering in CLI                                                                                          |
| `user-invocable`            | boolean |        ✅         |      ✅       | Controls agent picker selection on both platforms. Default: `true`.                                                           |
| `model`                     | string  | ⚠️ Host-dependent |      ✅       | VS Code supports per-agent model selection. Current GitHub Copilot coding-agent docs say this field is ignored there.        |
| `disable-model-invocation`  | boolean |        ✅         |      ✅       | Supported across runtimes. Prevents automatic subagent or model invocation when `true`. Default: `false`. Official canonical field per March 2026 docs.                                                                                             |
| `infer`                     | boolean | ⚠️ Retired     |      ❌       | **Retired** as of March 2026 official docs. Use `disable-model-invocation` instead. Setting `disable-model-invocation: true` is equivalent to the old `infer: false`.                                                                          |
| `mcp-servers`               | object  |        ✅         |      ❌       | CLI-only: agent-bundled MCP servers                                                                                           |
| `target`                    | string  |        ✅         |      ✅       | Optional. `vscode` or `github-copilot`. If unset, defaults to both environments.                                              |
| `agents`                    | array   |        ❌         |      ✅       | VS Code-only: subagent declarations                                                                                           |
| `argument-hint`             | string  |        ❌         |      ✅       | VS Code-only                                                                                                                  |

Unrecognized frontmatter fields are **silently ignored** in both platforms — agents degrade gracefully, not with errors.

---

## Tool Namespace Remapping

Built-in tools use different names across runtimes.

| VS Code Tool            | Copilot-CLI Tool                  | Notes                                                 |
| ----------------------- | --------------------------------- | ----------------------------------------------------- |
| `execute/runInTerminal` | `bash` (or PowerShell on Windows) | Shell command execution                               |
| `read/readFile`         | `view`                            | File reading                                          |
| `edit/editFiles`        | `edit`                            | File editing                                          |
| (file creation)         | `create`                          | File creation                                         |
| `search`                | Built-in search                   | Codebase search                                       |
| `agent`                 | `task` (TaskTool)                 | Subagent delegation                                   |
| `web`                   | **No built-in equivalent**        | Use MCP servers (Brave Search, etc.) or shell `curl`  |
| `vscode/memory`         | **No equivalent**                 | CLI has implicit memory (automatic, not programmatic) |
| `execute/testFailure`   | **No equivalent**                 | Use shell-based test execution                        |
| `execute/runTests`      | **No equivalent**                 | Use shell-based test execution                        |

Tool filtering in CLI uses glob patterns: `--allow-tool "shell(npm run test:*)"`, `--deny-tool "shell(rm *)"`.

---

## Tool Restriction Mechanisms

The CLI provides multiple tool restriction mechanisms that replace `.toolsets.jsonc`:

| Mechanism                                | Scope                           | Example                                 |
| ---------------------------------------- | ------------------------------- | --------------------------------------- |
| `--allow-tool` / `--deny-tool`           | Session-wide (CLI flags)        | `--deny-tool "shell(rm *)"`             |
| `--available-tools` / `--excluded-tools` | Session-wide (CLI flags)        | `--available-tools "edit,view"`         |
| Agent `tools:` frontmatter               | Per-agent (whitelist/blacklist) | `tools: [edit, view, -bash]`            |
| `preToolUse` hooks                       | Per-invocation (programmatic)   | Script returns `deny` / `allow` / `ask` |
| MCP server `tools:` config               | Per-MCP-server                  | `"tools": ["search_*"]`                 |
| `--disable-mcp-server`                   | Session-wide                    | `--disable-mcp-server brave`            |
| `--disable-builtin-mcps`                 | Session-wide                    | Disables built-in GitHub MCP            |
| `--additional-mcp-config`                | Session-wide (CLI flag)         | `--additional-mcp-config ./extra-mcp.json` |
| `--no-custom-instructions`               | Session-wide (CLI flag)         | Disables all custom instruction loading |

Deny rules take precedence over allow rules (safe defaults).

---

## MCP Interactive Commands

The CLI provides interactive `/mcp` commands for managing MCP server configuration within a session:

| Command                    | Description                                      |
| -------------------------- | ------------------------------------------------ |
| `/mcp add`                 | Interactive form to add a new MCP server (Tab to navigate fields) |
| `/mcp show`                | List all configured MCP servers                  |
| `/mcp show SERVER-NAME`    | Show details for a specific MCP server           |
| `/mcp edit SERVER-NAME`    | Edit an existing MCP server configuration        |
| `/mcp delete SERVER-NAME`  | Delete an MCP server configuration               |
| `/mcp disable SERVER-NAME` | Temporarily disable an MCP server                |
| `/mcp enable SERVER-NAME`  | Re-enable a disabled MCP server                  |

> **Note:** The deletion command is `/mcp delete`, not `/mcp remove` (pre-GA syntax). The `/mcp add` command is fully interactive — no server name argument is passed on the command line.

---

## Hook Lifecycle Events

Both VS Code and Copilot-CLI support the same hook lifecycle events and JSON schema:

| Event                 | Trigger                      |        Can Modify Behavior         |
| --------------------- | ---------------------------- | :--------------------------------: |
| `sessionStart`        | Session begins or resumes    |                 No                 |
| `sessionEnd`          | Session completes/terminates |                 No                 |
| `agentStop`           | Agent stops or is replaced   |                 No                 |
| `subagentStop`        | Subagent task completes      |                 No                 |
| `userPromptSubmitted` | User submits prompt          |                 No                 |
| `preToolUse`          | Before any tool execution    | **Yes** (`deny` / `allow` / `ask`) |
| `postToolUse`         | After tool execution         |                 No                 |
| `errorOccurred`       | Error during execution       |                 No                 |

Hook config format: `{ "version": 1, "hooks": { "<event>": [{ "bash": "...", "powershell": "...", "cwd": "...", "timeout": ... }] } }`

---

## Version Requirements

| Feature              | Minimum Version    | Source                                                                                                                                        |
| -------------------- | ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Custom agents        | October 2025       | [Changelog (2025-10-28)](https://github.blog/changelog/2025-10-28-github-copilot-cli-use-custom-agents-and-delegate-to-copilot-coding-agent/) |
| Skills               | December 2025      | [Changelog (2025-12-18)](https://github.blog/changelog/2025-12-18-github-copilot-now-supports-agent-skills/)                                  |
| Hooks (`preToolUse`) | February 2026 (GA) | [GA Announcement](https://github.blog/changelog/2026-02-25-github-copilot-cli-is-now-generally-available/)                                    |
| All features         | **v0.0.400+** (GA) | GA release, February 2026                                                                                                                     |

---

## Configuration Override

The default configuration directory `~/.copilot/` can be overridden:

- **CLI flag**: `--config-dir <directory>`
- **Environment variable**: `XDG_CONFIG_HOME` (path becomes `$XDG_CONFIG_HOME/.copilot/`)
- **Config file**: `config-dir` key in `~/.copilot/config.json`

This redirects the entire `~/.copilot/` tree (agents, skills, MCP config, instructions, logs, sessions).

---

## Quick Reference Links

| Category        | Document                                 | Path                                                                                                                |
| --------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| **How-to**      | Publish customizations for Copilot CLI   | `.docs/how-to/copilot/how-to-publish-customizations-for-copilot-cli.md`                                             |
| **Explanation** | CLI vs VS Code customization differences | `.docs/explanation/copilot/copilot-cli-vs-vscode-customization.md`                                                  |
| **Explanation** | Ralph-v2 tool compatibility              | `.docs/explanation/copilot/copilot-cli-ralph-v2-tool-compatibility.md`                                              |
| **Reference**   | CLI Plugin Reference                     | `.docs/reference/copilot/cli-plugin-reference.md`                                                                    |
| **How-to**      | How to Create a CLI Plugin               | `.docs/how-to/copilot/how-to-create-cli-plugin.md`                                                                  |
| **Explanation** | About CLI Plugins                        | `.docs/explanation/copilot/about-cli-plugins.md`                                                                     |
| **External**    | Official comparing CLI features          | [docs.github.com](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/comparing-cli-features)            |
| **External**    | Custom agents docs                       | [docs.github.com](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/create-custom-agents)    |
| **External**    | Custom instructions docs                 | [docs.github.com](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-custom-instructions) |
| **External**    | Skills docs                              | [docs.github.com](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/create-skills)           |
| **External**    | Hooks reference                          | [docs.github.com](https://docs.github.com/en/copilot/reference/hooks-configuration)                                 |
| **External**    | Copilot CLI changelog                    | [github.blog/changelog](https://github.blog/changelog/2026-02-25-github-copilot-cli-is-now-generally-available/)    |
