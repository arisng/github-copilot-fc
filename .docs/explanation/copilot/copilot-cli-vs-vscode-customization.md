# Copilot CLI vs VS Code: Customization Model Differences

> **Last verified**: GA v0.0.420 (February 2026)
> **Related**: [Support Matrix](../../reference/copilot/copilot-cli-customization-matrix.md) · [Ralph-v2 Tool Compatibility](copilot-cli-ralph-v2-tool-compatibility.md) · [Publish How-To](../../how-to/copilot/how-to-publish-customizations-for-copilot-cli.md)

This document explains *why* GitHub Copilot CLI and VS Code use different customization models, and what those differences mean architecturally. It is not a step-by-step guide — see the linked how-to and reference docs for that.

---

## Overview: Why Two Models Exist

GitHub Copilot ships as two distinct products with fundamentally different execution models:

- **VS Code** is editor-first. The extension runs inside the editor process, has access to workspace state, open tabs, diagnostics, and the full VS Code extension API. Customization files live in the editor's user data directory and can reference editor-specific concepts (modes, tool providers, diagnostics integrations).

- **Copilot CLI** is terminal-first. It runs as a standalone process (`copilot` binary) with no editor context. It reads from the filesystem, invokes shell commands directly, and communicates with MCP servers over stdio/SSE. Customization files live under `~/.copilot/` and the current working directory.

These different runtime environments drive every architectural difference described below. Neither model is "better" — they serve different interaction patterns. The same `.agent.md` or `SKILL.md` file can often work in both, but the surrounding infrastructure (tool names, instruction loading, subagent wiring) differs because the host environments differ.

---

## Agent Frontmatter Schema Comparison

Both platforms read `.agent.md` files with YAML frontmatter, but support different property sets. Unrecognized properties are **silently ignored** on both platforms — agents degrade gracefully rather than failing.

| Property         | Type    |  CLI  | VS Code | Purpose                                                                                            |
| ---------------- | ------- | :---: | :-----: | -------------------------------------------------------------------------------------------------- |
| `name`           | string  |   ✅   |    ✅    | Agent display name. CLI derives from filename if omitted.                                          |
| `description`    | string  |   ✅   |    ✅    | Agent description. Required in VS Code.                                                            |
| `instructions`   | string  |   ✅   |    ✅    | Markdown body after frontmatter.                                                                   |
| `tools`          | array   |   ✅   |    ✅    | Tool whitelist/blacklist. CLI supports glob patterns and `-` prefix for deny.                      |
| `model`          | string  |   ✅   |    ❌    | CLI-only. Override the default LLM model per agent.                                                |
| `infer`          | boolean |   ✅   |    ❌    | CLI-only. Controls whether other agents can delegate to this agent via TaskTool (default: `true`). |
| `mcpServers`     | object  |   ✅   |    ❌    | CLI-only. Bundle MCP server definitions directly in the agent file.                                |
| `agents`         | array   |   ❌   |    ✅    | VS Code-only. Declare subagent references for orchestration.                                       |
| `argument-hint`  | string  |   ❌   |    ✅    | VS Code-only. Hint text shown in the agent picker.                                                 |
| `user-invocable` | boolean |   ✅   |    ✅    | Controls whether the agent appears in the user-facing picker. Default: `true`.                     |

**Why the divergence?** VS Code agents operate within the extension host where subagent references must be explicitly declared (the `agents:` array). CLI agents operate in a flat namespace where any agent with `infer: true` is automatically visible as a delegatable tool — no explicit wiring needed.

### Practical Impact

An agent file written for VS Code that uses `agents:` and `argument-hint:` will still load in CLI. The unsupported keys are silently dropped. However, the subagent orchestration behavior will differ — see [Subagent Orchestration](#subagent-orchestration) below.

> **Runtime variant model (iteration 2):** Because agents are not behaviorally shareable across runtimes (tool namespaces, frontmatter fields, and body-level instructions all diverge), the workspace adopts a **per-runtime variant approach**. Platform-agnostic content (persona, rules, workflows, artifact templates, signal protocols) is extracted into shared `.instructions.md` files. Each runtime then gets a thin variant agent (~50 lines) containing only platform-specific frontmatter (`agents:` + VS Code tools, or `infer:` + `mcpServers:` + CLI tools) and tool-specific instructions. This keeps a single source of truth for agent behavior while allowing each platform to use its native capabilities. See [agent-variant-proposal.md](../../reference/copilot/agent-variant-proposal.md) for the full directory structure and extraction strategy.

---

## Tool Namespace Differences

The built-in tools available to agents use completely different names across platforms. This is because VS Code tools are backed by editor APIs (diagnostics, terminals, extension host), while CLI tools are backed by direct filesystem and shell operations.

| VS Code Tool            | CLI Tool          | Category            | Notes                                                                                                |
| ----------------------- | ----------------- | ------------------- | ---------------------------------------------------------------------------------------------------- |
| `execute/runInTerminal` | `bash`            | Shell execution     | CLI uses `bash` on Linux/macOS, PowerShell on Windows. No terminal UI — output is captured directly. |
| `read/readFile`         | `view`            | File reading        | Functionally identical. CLI's `view` supports line ranges natively.                                  |
| `edit/editFiles`        | `edit`            | File editing        | Both support string replacement. CLI's `edit` uses a unified edit model.                             |
| *(via edit)*            | `create`          | File creation       | CLI has a dedicated `create` tool. VS Code uses `edit/editFiles` or `create_file`.                   |
| `search`                | Built-in search   | Code search         | Both do codebase-level search. Underlying implementations differ.                                    |
| `agent`                 | `task` (TaskTool) | Subagent delegation | Architecturally different models (see below).                                                        |
| `web`                   | **No built-in**   | Web access          | CLI has no built-in web tool. Mitigate with MCP servers (Brave Search, fetch).                       |
| `vscode/memory`         | **No equivalent** | Memory              | CLI has implicit memory (automatic), not programmatic. Cannot `memory.create()`.                     |
| `execute/runTests`      | **No equivalent** | Test execution      | CLI uses shell-based test runners via `bash`.                                                        |
| `execute/testFailure`   | **No equivalent** | Test diagnostics    | CLI parses test output from `bash` invocations.                                                      |

**Why not just alias them?** The tools aren't purely renamed — they have different capabilities. `bash` captures stdout/stderr as text; `execute/runInTerminal` interacts with a terminal UI that persists. `view` is a stateless file read; `readFile` integrates with editor state. The different names reflect genuinely different underlying implementations.

### Impact on Agent Files

Agent `tools:` frontmatter must reference the correct namespace for the target platform:

```yaml
# VS Code agent
tools:
  - execute/runInTerminal
  - read/readFile
  - edit/editFiles

# CLI agent
tools:
  - bash
  - view
  - edit
  - create
```

A cross-platform agent should either omit the `tools:` key (allowing all tools) or maintain platform-aware tool lists.

---

## Instruction Loading Model

This is perhaps the starkest architectural difference: VS Code spreads instructions across many files; CLI concentrates them.

### VS Code Model

VS Code loads instructions from multiple independent files, each controlling its own scope:

```
~/.vscode/prompts/                    # User-level (per-editor install)
├── my-rules.instructions.md          # applyTo: **/*.ts
├── testing.instructions.md           # applyTo: **/*.test.*
└── ...
.github/
├── copilot-instructions.md           # Repository-level (always loaded)
└── instructions/
    └── backend.instructions.md       # Repository-level with applyTo
```

- Each `.instructions.md` file has YAML frontmatter with `applyTo` glob patterns.
- Files are independently toggled; adding or removing one doesn't affect others.
- The editor evaluates `applyTo` against the active file context to decide which instructions are loaded.

### CLI Model

CLI loads instructions from a single file or an environment variable pointing to directories:

```
$HOME/.copilot/copilot-instructions.md     # User-level (single file)
.github/copilot-instructions.md            # Repository-level (always loaded)
.github/instructions/**/*.instructions.md  # Repository-level with applyTo
```

Or using the environment variable:

```bash
export COPILOT_CUSTOM_INSTRUCTIONS_DIRS="/path/to/dir1:/path/to/dir2"
```

**Key differences:**

| Aspect                 | VS Code                                                     | CLI                                                    |
| ---------------------- | ----------------------------------------------------------- | ------------------------------------------------------ |
| User-level location    | Editor prompts directory (per-install)                      | `$HOME/.copilot/copilot-instructions.md` (single file) |
| User-level granularity | Multiple files with individual `applyTo`                    | One file (all instructions concatenated)               |
| Env override           | Not applicable                                              | `COPILOT_CUSTOM_INSTRUCTIONS_DIRS`                     |
| Repo-level location    | `.github/copilot-instructions.md` + `.github/instructions/` | Same ✓                                                 |
| `applyTo` support      | Yes (user + repo level)                                     | Yes (repo-level `.github/instructions/` only)          |

**Why the difference?** VS Code has a rich file-watching model — it monitors the prompts directory and dynamically evaluates `applyTo` against editor context. CLI runs as a one-shot or session process without persistent file watching. A single instructions file is simpler to load at session start.

**Important**: `~/.copilot/instructions/` is **NOT** a valid discovery path for CLI. This is a common assumption — the CLI only reads from the single `copilot-instructions.md` file or directories listed in `COPILOT_CUSTOM_INSTRUCTIONS_DIRS`.

---

## Subagent Orchestration

This is where the architectural models diverge most significantly.

### VS Code: Explicit Declarations

In VS Code, a parent agent lists its subagents in frontmatter:

```yaml
---
name: orchestrator
description: Manages sub-tasks
agents:
  - executor
  - reviewer
  - planner
---
```

The runtime resolves these names to `.agent.md` files and makes them available as invocable tools within the parent agent's context. The parent can call `@executor` directly.

### CLI: Inferred Delegation via TaskTool

In CLI, there is no `agents:` key. Instead, all agents with `infer: true` (the default) are automatically visible as delegatable targets through the `task` tool (TaskTool):

```yaml
---
name: executor
description: Implements specific tasks
infer: true    # default — makes this agent available for delegation
---
```

The active agent can delegate by invoking `task("executor", "implement task-1")`. The CLI runtime handles context isolation — only the active agent's full instructions are loaded; other agents appear as brief tool descriptions.

**Why the difference?** VS Code agents live in a controlled environment where the extension host manages the agent registry. Explicit `agents:` declarations create a wiring contract. CLI agents live in a flat filesystem namespace where any agent file in `~/.copilot/agents/` or `.github/agents/` is discoverable. The `infer` model eliminates the need for manual wiring — the runtime builds the delegation graph dynamically.

### Practical Impact

A VS Code agent using `agents: [executor, reviewer]` will load in CLI, but the `agents` key is silently ignored. For delegation to work, the referenced agents must exist as separate `.agent.md` files with `infer: true` (default). The orchestration *works*, but through a fundamentally different mechanism.

---

## Hook Model

Hooks share the **same JSON schema** across both platforms, making them the most compatible customization type.

```json
{
  "version": 1,
  "hooks": {
    "preToolUse": [{ "command": "python3 validate.py", "description": "..." }],
    "postToolUse": [{ "command": "python3 log.py", "description": "..." }]
  }
}
```

### Loading Path Differences

| Aspect                 | VS Code                                                                                           | CLI                                     |
| ---------------------- | ------------------------------------------------------------------------------------------------- | --------------------------------------- |
| Discovery path         | `.github/hooks/`                                                                                  | CWD (repo root) or via plugins          |
| Installation           | Publish to `.github/hooks/`                                                                       | Place in repo root or package as plugin |
| Lifecycle events       | `sessionStart`, `sessionEnd`, `userPromptSubmitted`, `preToolUse`, `postToolUse`, `errorOccurred` | Same events ✓                           |
| `preToolUse` responses | `deny` / `allow` / `ask`                                                                          | Same ✓                                  |
| Plugin bundling        | Not applicable                                                                                    | Plugins can bundle hooks                |

**Why similar?** Hooks were designed after both platforms existed and benefited from a unified specification. The JSON schema is platform-agnostic by design — hooks execute shell commands, which are inherently portable.

---

## Tool Restriction

Both platforms support restricting which tools an agent can use, but through different mechanisms.

### VS Code: Toolset Files

VS Code uses `.toolsets.jsonc` files to define named tool collections:

```jsonc
// toolsets/workspace-read.toolsets.jsonc
{
  "tools": ["read/readFile", "search"]
}
```

Agents reference toolsets in frontmatter, and the editor resolves the tool whitelist.

### CLI: Flags, Frontmatter, and Hooks

CLI has no `.toolsets.jsonc` equivalent. Instead, tool restriction uses three complementary mechanisms:

1. **CLI flags**: `--allow-tool "shell(npm run test:*)"` and `--deny-tool "shell(rm *)"` apply session-wide.
2. **Agent `tools:` frontmatter**: Whitelist (`[edit, view]`) or blacklist (`[-bash]`) per-agent.
3. **`preToolUse` hooks**: Programmatic per-invocation decisions returning `deny`, `allow`, or `ask`.

Additionally: `--available-tools`, `--excluded-tools`, `--disable-mcp-server`, and `--disable-builtin-mcps` provide coarser controls.

**Deny rules always take precedence over allow rules** in CLI (safe defaults).

**Why no file format?** CLI is invoked with explicit flags — there's no persistent editor session to apply file-based configuration to. The flag-and-hook model fits the CLI's invocation-scoped lifecycle.

---

## Memory

### VS Code: Programmatic Memory Tool

VS Code provides a `vscode/memory` tool that agents can use to create, read, and manage persistent notes:

```
memory.create("/memories/user-prefs.md", "Prefers TypeScript...")
memory.view("/memories/")
```

Memory is organized into scopes (user, session, repository) and persists across conversations.

### CLI: Implicit Memory

CLI has automatic, implicit memory. The runtime records facts from conversations and recalls them in future sessions. There is no programmatic API — agents cannot explicitly `create` or `view` memory entries.

**Why the gap?** VS Code memory integrates with the extension host's storage APIs. CLI runs as a standalone process where persistent state management is handled by the backend service, not the local process.

### Impact

Agents that depend on `vscode/memory` for cross-session context (e.g., storing user preferences, tracking task state) will lose that capability in CLI. The implicit memory may capture some patterns automatically, but agents cannot control what is stored or retrieved.

---

## Web Access

### VS Code: Built-in Web Tool

VS Code provides a built-in `web` tool that agents can use for web searches and content fetching. No configuration needed.

### CLI: MCP-Based Web Access

CLI has **no built-in web tool**. Web access requires configuring MCP servers:

```json
// ~/.copilot/mcp-config.json
{
  "mcpServers": {
    "brave-search": {
      "command": "npx",
      "args": ["-y", "@anthropic/mcp-brave-search"],
      "env": { "BRAVE_API_KEY": "..." }
    }
  }
}
```

Alternatively, agents can use `bash` with `curl` for simple HTTP requests.

**Why no built-in?** VS Code's web tool is provided by the extension, which runs in a rich Node.js environment. CLI deliberately keeps its built-in tool surface minimal — web access is delegated to the MCP ecosystem, which offers more flexibility (choice of search provider, caching, rate limiting).

---

## Shared Concepts

Despite the differences, several customization concepts work identically across both platforms:

| Concept                    | CLI Path                                    | VS Code Path                           | Notes                                |
| -------------------------- | ------------------------------------------- | -------------------------------------- | ------------------------------------ |
| **Agent file format**      | `*.agent.md` with YAML frontmatter          | Same ✓                                 | Unrecognized keys silently ignored   |
| **Repo instructions**      | `.github/copilot-instructions.md`           | Same ✓                                 | Always loaded for all agents         |
| **Repo instruction files** | `.github/instructions/**/*.instructions.md` | Same ✓                                 | With `applyTo` support               |
| **Skills directory**       | `~/.copilot/skills/`                        | Same ✓                                 | Folder-based, `SKILL.md` required    |
| **MCP config**             | `~/.copilot/mcp-config.json`                | `.vscode/mcp.json` or VS Code settings | Different file but same MCP protocol |
| **Hook JSON schema**       | `{ "version": 1, "hooks": {...} }`          | Same ✓                                 | Portable across platforms            |
| **Graceful degradation**   | Unrecognized frontmatter silently ignored   | Same ✓                                 | Agents don't fail on unknown keys    |

These shared concepts form the foundation for cross-platform agent authoring. An agent that sticks to this common subset will work on both platforms without modification.

---

## Further Reading

- **Reference**: [Copilot-CLI Customization Support Matrix](../../reference/copilot/copilot-cli-customization-matrix.md)
- **How-to**: [Publish Customizations for Copilot CLI](../../how-to/copilot/how-to-publish-customizations-for-copilot-cli.md)
- **Tool gaps**: [Ralph-v2 Tool Compatibility](copilot-cli-ralph-v2-tool-compatibility.md)
