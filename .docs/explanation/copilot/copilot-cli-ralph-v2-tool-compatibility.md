# Ralph-v2 Tool Compatibility Analysis for Copilot CLI

> **Last verified**: GA v0.0.420 (February 2026)
> **Related**: [Support Matrix](../../reference/copilot/copilot-cli-customization-matrix.md) · [CLI vs VS Code](copilot-cli-vs-vscode-customization.md) · [Publish How-To](../../how-to/copilot/how-to-publish-customizations-for-copilot-cli.md)

## Overview

Ralph-v2 is a multi-agent orchestration system comprising 6 specialized agents (Orchestrator, Planner, Questioner, Executor, Reviewer, Librarian) that collaborate through a state machine to plan, execute, review, and commit work within structured sessions. Each agent declares a specific set of VS Code tools in its `tools:` frontmatter array.

This document provides a complete tool compatibility analysis for running ralph-v2 agents in GitHub Copilot CLI. Every tool declared across the 6 agent files is cataloged and classified as **Native** (direct copilot-cli equivalent), **MCP-bridgeable** (available via MCP server configuration), **Shell-fallback** (achievable through shell commands), or **Unavailable** (no equivalent in copilot-cli).

The analysis is grounded in research from Q-TECH-001 through Q-TECH-008, Q-ASM-001, Q-ASM-003, Q-RSK-002, Q-RSK-004, and Q-RSK-006.

---

## Per-Tool Compatibility Matrix

### Core File & Edit Tools

| VS Code Tool | Copilot-CLI Equivalent | Status | Workaround / Migration Path |
|---|---|---|---|
| `read/readFile` | `view` | **Native** | Direct equivalent. No changes needed. |
| `edit/editFiles` | `edit` | **Native** | Direct equivalent. No changes needed. |
| `edit/createFile` | `create` | **Native** | Direct equivalent. No changes needed. |
| `edit/createDirectory` | `bash` (mkdir) | **Shell-fallback** | Use `bash(mkdir -p <path>)`. Functional but requires shell execution. |
| `search` | Built-in search | **Native** | Copilot-cli has built-in codebase search. No changes needed. |

### Terminal & Execution Tools

| VS Code Tool | Copilot-CLI Equivalent | Status | Workaround / Migration Path |
|---|---|---|---|
| `execute/runInTerminal` | `bash` / PowerShell | **Native** | Maps to `bash` (Linux/macOS) or PowerShell (Windows). Direct equivalent. |
| `execute/getTerminalOutput` | `bash` (inline) | **Native** | Copilot-cli captures shell output inline. No separate "get output" tool needed. |
| `execute/awaitTerminal` | `bash` (blocking) | **Native** | Shell commands in copilot-cli are blocking by default. No separate await needed. |
| `execute/killTerminal` | `bash` (kill/Ctrl+C) | **Shell-fallback** | Use `bash(kill <pid>)` or process management. Terminal lifecycle differs in CLI. |
| `execute/runTests` | `bash` (test runner) | **Shell-fallback** | No dedicated test tool. Use `bash(dotnet test)`, `bash(npm test)`, etc. Test output parsed from stdout/stderr. (Q-TECH-008) |
| `execute/testFailure` | `bash` (test runner) | **Shell-fallback** | No dedicated test failure tool. Parse test output from shell execution. (Q-TECH-008) |

### Terminal Inspection Tools

| VS Code Tool | Copilot-CLI Equivalent | Status | Workaround / Migration Path |
|---|---|---|---|
| `read/terminalSelection` | N/A | **Unavailable** | No terminal selection concept in CLI. Not critical — agents rarely use this. |
| `read/terminalLastCommand` | `bash` (history) | **Shell-fallback** | Use shell history (`history 1` / `Get-History -Count 1`). Rarely needed. |
| `read/problems` | `bash` (linter) | **Shell-fallback** | No VS Code Problems panel. Use shell-based linters: `dotnet build`, `eslint`, `tsc --noEmit`. |

### Agent & Orchestration Tools

| VS Code Tool | Copilot-CLI Equivalent | Status | Workaround / Migration Path |
|---|---|---|---|
| `agent` (subagent invocation) | `task` (TaskTool) | **Native** (different model) | Agents with `infer: true` become TaskTool targets. Main agent delegates based on descriptions. Replaces explicit `agents:` array. **Critical architectural change.** (Q-TECH-003) |

### Web & Research Tools

| VS Code Tool | Copilot-CLI Equivalent | Status | Workaround / Migration Path |
|---|---|---|---|
| `web` | N/A (no built-in) | **MCP-bridgeable** | No native web tool in copilot-cli. Use MCP-based web search (Brave Search MCP, `fetch_content` MCP). Agent can bundle `mcpServers` for self-contained web access. (Q-TECH-007, Q-RSK-006) |

### Memory Tools

| VS Code Tool | Copilot-CLI Equivalent | Status | Workaround / Migration Path |
|---|---|---|---|
| `vscode/memory` | Implicit memory | **Unavailable** (partial) | No programmatic store/retrieve API. Copilot-cli has implicit repository memory (auto-learns conventions) and cross-session memory. Agents cannot explicitly store/retrieve facts. (Q-TECH-004) |

### MCP Tools — Docker/Utility Servers

| VS Code Tool | Copilot-CLI Equivalent | Status | Workaround / Migration Path |
|---|---|---|---|
| `mcp_docker/sequentialthinking` | Auto-discovered | **MCP-bridgeable** | Available if `mcp_docker` server configured in `~/.copilot/mcp-config.json`. Agents don't need explicit refs. (Q-ASM-003) |
| `mcp_docker/brave_web_search` | Auto-discovered | **MCP-bridgeable** | Available if Brave Search MCP configured. Replaces `web` tool for search. |
| `mcp_docker/brave_summarizer` | Auto-discovered | **MCP-bridgeable** | Available if Brave Search MCP configured. |
| `mcp_docker/fetch_content` | Auto-discovered | **MCP-bridgeable** | Available if fetch MCP configured. Replaces `web` for page fetching. |
| `mcp_docker/search` | Auto-discovered | **MCP-bridgeable** | Available if DuckDuckGo MCP configured. |
| `mcp_docker/get-library-docs` | Auto-discovered | **MCP-bridgeable** | Available if Context7 MCP configured. |
| `mcp_docker/resolve-library-id` | Auto-discovered | **MCP-bridgeable** | Available if Context7 MCP configured. |

### MCP Tools — Microsoft Docs

| VS Code Tool | Copilot-CLI Equivalent | Status | Workaround / Migration Path |
|---|---|---|---|
| `microsoftdocs/mcp/*` | Auto-discovered | **MCP-bridgeable** | Available if Microsoft Docs MCP server configured. Includes `microsoft_docs_search`, `microsoft_docs_fetch`, `microsoft_code_sample_search`. |

### MCP Tools — DeepWiki

| VS Code Tool | Copilot-CLI Equivalent | Status | Workaround / Migration Path |
|---|---|---|---|
| `deepwiki/*` | Auto-discovered | **MCP-bridgeable** | Available if DeepWiki MCP server configured. Includes `ask_question`, `read_wiki_contents`, `read_wiki_structure`. |

### MCP Tools — Aspire

| VS Code Tool | Copilot-CLI Equivalent | Status | Workaround / Migration Path |
|---|---|---|---|
| `aspire/*` | Auto-discovered | **MCP-bridgeable** | Available if Aspire MCP server configured. |

### MCP Tools — GitHub

| VS Code Tool | Copilot-CLI Equivalent | Status | Workaround / Migration Path |
|---|---|---|---|
| `github/get_commit` | Built-in GitHub MCP | **Native** | Copilot-cli includes a built-in GitHub MCP server with ~20 tools. |
| `github/get_file_contents` | Built-in GitHub MCP | **Native** | Part of built-in GitHub MCP. |
| `github/get_latest_release` | Built-in GitHub MCP | **Native** | Part of built-in GitHub MCP. |
| `github/get_release_by_tag` | Built-in GitHub MCP | **Native** | Part of built-in GitHub MCP. |
| `github/get_tag` | Built-in GitHub MCP | **Native** | Part of built-in GitHub MCP. |
| `github/list_branches` | Built-in GitHub MCP | **Native** | Part of built-in GitHub MCP. |
| `github/list_commits` | Built-in GitHub MCP | **Native** | Part of built-in GitHub MCP. |
| `github/list_releases` | Built-in GitHub MCP | **Native** | Part of built-in GitHub MCP. |
| `github/list_tags` | Built-in GitHub MCP | **Native** | Part of built-in GitHub MCP. |
| `github/search_code` | Built-in GitHub MCP | **Native** | Part of built-in GitHub MCP. |
| `github/search_repositories` | Built-in GitHub MCP | **Native** | Part of built-in GitHub MCP. |

### Compatibility Summary by Status

| Status | Count | Examples |
|---|---|---|
| **Native** | 18 | `view`, `edit`, `create`, `bash`, `search`, `task`, GitHub MCP tools |
| **MCP-bridgeable** | 12 | `mcp_docker/*`, `microsoftdocs/mcp/*`, `deepwiki/*`, `aspire/*`, `web` (via Brave) |
| **Shell-fallback** | 7 | `execute/runTests`, `execute/testFailure`, `read/problems`, `edit/createDirectory`, `execute/killTerminal`, `read/terminalLastCommand` |
| **Unavailable** | 2 | `vscode/memory` (partial — implicit only), `read/terminalSelection` |

---

## Per-Agent Readiness Summary

### Ralph-v2-Orchestrator

**Declared tools**: `execute/getTerminalOutput`, `execute/awaitTerminal`, `execute/killTerminal`, `execute/runInTerminal`, `read/problems`, `read/readFile`, `read/terminalSelection`, `read/terminalLastCommand`, `agent`, `edit/createDirectory`, `edit/createFile`, `edit/editFiles`, `search`, `mcp_docker/sequentialthinking`, `vscode/memory`

**Also declares**: `agents: ['Ralph-v2-Planner', 'Ralph-v2-Questioner', 'Ralph-v2-Executor', 'Ralph-v2-Reviewer', 'Ralph-v2-Librarian']`

| Category | Tools | Count |
|---|---|---|
| Native | `execute/runInTerminal`→bash, `execute/getTerminalOutput`→bash, `execute/awaitTerminal`→bash, `read/readFile`→view, `edit/createFile`→create, `edit/editFiles`→edit, `search`, `agent`→task | 8 |
| MCP-bridgeable | `mcp_docker/sequentialthinking` | 1 |
| Shell-fallback | `execute/killTerminal`, `read/problems`, `edit/createDirectory`, `read/terminalLastCommand` | 4 |
| Unavailable | `vscode/memory`, `read/terminalSelection` | 2 |

**Readiness: Partial** — Core orchestration works, but two critical gaps:
1. **`agents:` frontmatter key unsupported** — Must migrate to `infer: true` + TaskTool delegation model. Subagents become auto-discoverable tools rather than explicit dependencies. (Q-TECH-003)
2. **`vscode/memory` unavailable** — Implicit memory only. Cannot programmatically store session state facts.

---

### Ralph-v2-Planner

**Declared tools**: `execute/getTerminalOutput`, `execute/awaitTerminal`, `execute/killTerminal`, `execute/runInTerminal`, `read/problems`, `read/readFile`, `read/terminalSelection`, `read/terminalLastCommand`, `edit/createDirectory`, `edit/createFile`, `edit/editFiles`, `search`, `web`, `mcp_docker/fetch_content`, `mcp_docker/search`, `mcp_docker/sequentialthinking`, `mcp_docker/brave_summarizer`, `mcp_docker/brave_web_search`, `vscode/memory`

| Category | Tools | Count |
|---|---|---|
| Native | `execute/runInTerminal`→bash, `execute/getTerminalOutput`→bash, `execute/awaitTerminal`→bash, `read/readFile`→view, `edit/createFile`→create, `edit/editFiles`→edit, `search` | 7 |
| MCP-bridgeable | `web`→Brave MCP, `mcp_docker/fetch_content`, `mcp_docker/search`, `mcp_docker/sequentialthinking`, `mcp_docker/brave_summarizer`, `mcp_docker/brave_web_search` | 6 |
| Shell-fallback | `execute/killTerminal`, `read/problems`, `edit/createDirectory`, `read/terminalLastCommand` | 4 |
| Unavailable | `vscode/memory`, `read/terminalSelection` | 2 |

**Readiness: Partial** — Planning workflows functional with MCP web search. `web` tool gap mitigated by Brave MCP. Memory loss impacts cross-session planning context.

---

### Ralph-v2-Questioner

**Declared tools**: `execute/getTerminalOutput`, `execute/awaitTerminal`, `execute/killTerminal`, `execute/runInTerminal`, `read/problems`, `read/readFile`, `read/terminalSelection`, `read/terminalLastCommand`, `edit/createDirectory`, `edit/createFile`, `edit/editFiles`, `search`, `web`, `microsoftdocs/mcp/*`, `github/*` (11 tools), `mcp_docker/fetch_content`, `mcp_docker/get-library-docs`, `mcp_docker/resolve-library-id`, `mcp_docker/search`, `mcp_docker/sequentialthinking`, `mcp_docker/brave_summarizer`, `mcp_docker/brave_web_search`, `deepwiki/*`, `vscode/memory`

| Category | Tools | Count |
|---|---|---|
| Native | `execute/runInTerminal`→bash, `execute/getTerminalOutput`→bash, `execute/awaitTerminal`→bash, `read/readFile`→view, `edit/createFile`→create, `edit/editFiles`→edit, `search`, `github/*` (11 GitHub MCP tools — built-in) | 18 |
| MCP-bridgeable | `web`→Brave MCP, `microsoftdocs/mcp/*`, `deepwiki/*`, `mcp_docker/fetch_content`, `mcp_docker/get-library-docs`, `mcp_docker/resolve-library-id`, `mcp_docker/search`, `mcp_docker/sequentialthinking`, `mcp_docker/brave_summarizer`, `mcp_docker/brave_web_search` | 10 |
| Shell-fallback | `execute/killTerminal`, `read/problems`, `edit/createDirectory`, `read/terminalLastCommand` | 4 |
| Unavailable | `vscode/memory`, `read/terminalSelection` | 2 |

**Readiness: Partial** — Research workflows fully functional with MCP servers. The Questioner has the broadest MCP dependency but benefits from copilot-cli's built-in GitHub MCP. `web` gap fully mitigated by Brave MCP. Memory loss has minimal impact (Questioner stores answers in files, not memory).

---

### Ralph-v2-Executor

**Declared tools**: `vscode/memory`, `execute/getTerminalOutput`, `execute/awaitTerminal`, `execute/killTerminal`, `execute/testFailure`, `execute/runInTerminal`, `execute/runTests`, `read/terminalSelection`, `read/terminalLastCommand`, `read/problems`, `read/readFile`, `edit/createDirectory`, `edit/createFile`, `edit/editFiles`, `search`, `web`, `aspire/*`, `deepwiki/*`, `mcp_docker/brave_summarizer`, `mcp_docker/brave_web_search`, `mcp_docker/fetch_content`, `mcp_docker/get-library-docs`, `mcp_docker/resolve-library-id`, `mcp_docker/search`, `mcp_docker/sequentialthinking`, `microsoftdocs/mcp/*`

| Category | Tools | Count |
|---|---|---|
| Native | `execute/runInTerminal`→bash, `execute/getTerminalOutput`→bash, `execute/awaitTerminal`→bash, `read/readFile`→view, `edit/createFile`→create, `edit/editFiles`→edit, `search` | 7 |
| MCP-bridgeable | `web`→Brave MCP, `aspire/*`, `deepwiki/*`, `microsoftdocs/mcp/*`, `mcp_docker/brave_summarizer`, `mcp_docker/brave_web_search`, `mcp_docker/fetch_content`, `mcp_docker/get-library-docs`, `mcp_docker/resolve-library-id`, `mcp_docker/search`, `mcp_docker/sequentialthinking` | 11 |
| Shell-fallback | `execute/killTerminal`, `execute/runTests`→bash, `execute/testFailure`→bash, `read/problems`→bash linter, `edit/createDirectory`→bash mkdir, `read/terminalLastCommand` | 6 |
| Unavailable | `vscode/memory`, `read/terminalSelection` | 2 |

**Readiness: Partial** — Implementation workflows functional. Test execution via shell commands instead of dedicated test tools. Broadest tool surface but most tools are MCP-bridgeable. Memory loss impacts repo memory storage for cross-session knowledge.

---

### Ralph-v2-Reviewer

**Declared tools**: `vscode/memory`, `execute/testFailure`, `execute/getTerminalOutput`, `execute/awaitTerminal`, `execute/killTerminal`, `execute/runInTerminal`, `execute/runTests`, `read/problems`, `read/readFile`, `read/terminalSelection`, `read/terminalLastCommand`, `edit/createDirectory`, `edit/createFile`, `edit/editFiles`, `search`, `web`, `aspire/*`, `mcp_docker/brave_summarizer`, `mcp_docker/brave_web_search`, `mcp_docker/fetch_content`, `mcp_docker/search`, `mcp_docker/sequentialthinking`

| Category | Tools | Count |
|---|---|---|
| Native | `execute/runInTerminal`→bash, `execute/getTerminalOutput`→bash, `execute/awaitTerminal`→bash, `read/readFile`→view, `edit/createFile`→create, `edit/editFiles`→edit, `search` | 7 |
| MCP-bridgeable | `web`→Brave MCP, `aspire/*`, `mcp_docker/brave_summarizer`, `mcp_docker/brave_web_search`, `mcp_docker/fetch_content`, `mcp_docker/search`, `mcp_docker/sequentialthinking` | 7 |
| Shell-fallback | `execute/killTerminal`, `execute/runTests`→bash, `execute/testFailure`→bash, `read/problems`→bash linter, `edit/createDirectory`→bash mkdir, `read/terminalLastCommand` | 6 |
| Unavailable | `vscode/memory`, `read/terminalSelection` | 2 |

**Readiness: Partial** — Review/validation workflows functional. Test execution via shell is the primary change. Runtime validation (`execute/runTests`) shifts to shell-based test runners, which is a natural fit for CLI environments.

---

### Ralph-v2-Librarian

**Declared tools**: `vscode/memory`, `execute/getTerminalOutput`, `execute/awaitTerminal`, `execute/killTerminal`, `execute/runInTerminal`, `read/problems`, `read/readFile`, `read/terminalSelection`, `read/terminalLastCommand`, `edit/createDirectory`, `edit/createFile`, `edit/editFiles`, `search`, `web`, `mcp_docker/brave_summarizer`, `mcp_docker/brave_web_search`, `mcp_docker/fetch_content`, `mcp_docker/search`, `mcp_docker/sequentialthinking`

| Category | Tools | Count |
|---|---|---|
| Native | `execute/runInTerminal`→bash, `execute/getTerminalOutput`→bash, `execute/awaitTerminal`→bash, `read/readFile`→view, `edit/createFile`→create, `edit/editFiles`→edit, `search` | 7 |
| MCP-bridgeable | `web`→Brave MCP, `mcp_docker/brave_summarizer`, `mcp_docker/brave_web_search`, `mcp_docker/fetch_content`, `mcp_docker/search`, `mcp_docker/sequentialthinking` | 6 |
| Shell-fallback | `execute/killTerminal`, `read/problems`, `edit/createDirectory`, `read/terminalLastCommand` | 4 |
| Unavailable | `vscode/memory`, `read/terminalSelection` | 2 |

**Readiness: Partial** — Knowledge extraction/staging/promotion workflows functional. File-based operations (the Librarian's primary work) map directly to copilot-cli equivalents. Memory loss does not impact the Librarian since it writes to `.docs/` files.

---

## Readiness Overview

| Agent | Native | MCP | Shell | Unavailable | Score |
|---|---|---|---|---|---|
| **Orchestrator** | 8 | 1 | 4 | 2 | **Partial** |
| **Planner** | 7 | 6 | 4 | 2 | **Partial** |
| **Questioner** | 18 | 10 | 4 | 2 | **Partial** |
| **Executor** | 7 | 11 | 6 | 2 | **Partial** |
| **Reviewer** | 7 | 7 | 6 | 2 | **Partial** |
| **Librarian** | 7 | 6 | 4 | 2 | **Partial** |

**Scoring criteria**:
- **Ready** — All tools available natively or via MCP; no critical gaps.
- **Partial** — Core workflows functional; some tools need MCP/shell fallbacks; no blocking gaps for the agent's primary purpose.
- **Blocked** — Critical tool missing that prevents the agent's primary function.

All agents score **Partial** due to the universal `vscode/memory` gap. No agent is **Blocked** because their primary workflows (file editing, shell execution, search) are all natively available. The `agents:` orchestration gap (Orchestrator-specific) is the most architecturally significant change but does not block individual agent operation.

---

## Critical Gaps — Detailed Analysis

### Gap 1: `agents:` Subagent Orchestration (Q-TECH-003)

**Impact**: The Orchestrator declares `agents: ['Ralph-v2-Planner', 'Ralph-v2-Questioner', 'Ralph-v2-Executor', 'Ralph-v2-Reviewer', 'Ralph-v2-Librarian']` to establish an explicit subagent registry. Copilot-cli does not support the `agents:` frontmatter key.

**Copilot-CLI model**: Subagent orchestration uses `infer: true` (default) + TaskTool delegation:
- All agents with `infer: true` become visible as tool descriptions to the main agent.
- The main agent decides which subagent to invoke based on the subagent's `description` field.
- Multiple subagents can run in parallel.
- Subagents have isolated context windows (Q-RSK-004).

**Migration path**:
1. Remove `agents:` from Orchestrator frontmatter (silently ignored per Q-RSK-002, but clean is better).
2. Ensure each subagent has `infer: true` (copilot-cli default) so they appear as TaskTool targets.
3. Write rich `description` fields for each subagent — the description drives the Orchestrator's delegation decisions in copilot-cli.
4. Consider tool aliasing for deterministic routing: the Orchestrator can alias the `task` tool to create named delegation targets.

**Severity**: High — Architectural change to orchestration model. The VS Code explicit `agents:` list gives deterministic routing; copilot-cli's `infer`-based model is more heuristic. The state machine logic in the Orchestrator's markdown body is still usable as instructions, but invocation syntax changes.

**Graceful degradation**: The `agents:` key is silently ignored (Q-RSK-002). Ralph-v2 agents load in copilot-cli but the Orchestrator cannot explicitly invoke subagents by name through the `agents:` mechanism. Individual agents remain functional when invoked directly via `/agent ralph-v2-executor`.

---

### Gap 2: `web` Tool (Q-TECH-007)

**Impact**: The `web` tool (general web search/fetch) is declared by 5 of 6 agents (all except Orchestrator). The Questioner and Planner depend on it most heavily for research workflows.

**Copilot-CLI alternatives**:
1. **MCP-based web search**: Configure Brave Search MCP in `~/.copilot/mcp-config.json`. Provides `brave_web_search`, `brave_summarizer`.
2. **MCP-based fetch**: Configure fetch MCP for page content retrieval (`fetch_content`).
3. **Shell commands**: `curl` / `wget` for specific URLs. Less intelligent but universally available.
4. **Agent-bundled MCP**: Add `mcpServers` to agent frontmatter for self-contained web access without requiring global MCP config.

**Migration path**:
1. Remove `web` from copilot-cli agent `tools:` arrays.
2. Ensure Brave Search MCP or equivalent is configured in `~/.copilot/mcp-config.json`.
3. Alternatively, bundle web MCP servers in agent `mcpServers` frontmatter for zero-config operation.
4. The existing `mcp_docker/brave_web_search` and `mcp_docker/fetch_content` declarations already cover this gap — they just need the MCP servers running.

**Severity**: Medium — Fully mitigatable. The workspace already configures Brave Search and fetch MCP servers. The practical impact is minimal if users have the same MCP configuration (Q-RSK-006).

---

### Gap 3: `vscode/memory` (Q-TECH-004)

**Impact**: All 6 agents declare `vscode/memory`. Used for storing repository-scoped facts (conventions, patterns) and cross-session context that persists beyond a single conversation.

**Copilot-CLI memory model**:
- **Repository memory**: Copilot-cli automatically learns conventions and preferences from codebase interactions. No explicit API call needed.
- **Cross-session memory**: Users can reference past work, files, and PRs across sessions.
- **Auto-compaction**: At ~95% context usage, conversation history is compressed, enabling infinite sessions.
- **No programmatic API**: Agents cannot call a `store()` or `retrieve()` function.

**Migration path**:
1. Remove `vscode/memory` from copilot-cli agent `tools:` arrays.
2. Accept implicit memory as a partial replacement — most convention learning happens automatically.
3. For explicit fact storage, use file-based persistence: write facts to `.docs/` or session files instead of calling `vscode/memory`.
4. The Librarian's knowledge pipeline (EXTRACT → STAGE → PROMOTE to `.docs/`) already provides structured knowledge persistence that doesn't depend on `vscode/memory`.

**Severity**: Low-Medium — The practical impact is limited because:
- Ralph-v2's file-based artifact model (task files, reports, progress.md) already serves as the primary state persistence mechanism.
- The Librarian's `.docs/` knowledge pipeline replaces most `vscode/memory` use cases for long-term knowledge.
- Copilot-cli's implicit memory covers convention learning automatically.
- The main loss is the ability to programmatically store/retrieve specific facts mid-session.

---

## MCP Tool Discovery in Copilot CLI

A key architectural difference: in copilot-cli, MCP tools from `~/.copilot/mcp-config.json` are **auto-discovered** and available to all agents without explicit declaration (Q-ASM-003). Agent `tools:` arrays serve as **filters** (whitelist/blacklist), not requirements.

This means:
- Ralph-v2 agents do NOT need to list every MCP tool in their `tools:` frontmatter.
- If `tools:` is omitted entirely, the agent has access to ALL available tools (built-in + MCP).
- MCP glob patterns like `mcp_docker/*` and `deepwiki/*` work as whitelist filters.
- Agent-bundled `mcpServers` in frontmatter provide additional scoped MCP servers.
- Plugin-provided MCP servers (`~/.copilot/plugins/*/mcp-config.json`) are also auto-merged.

**Implication for ralph-v2**: The extensive MCP tool declarations in agent frontmatter are useful for VS Code (explicit whitelisting) but function differently in copilot-cli (filtering from a global pool). In copilot-cli, agents could use a simplified `tools:` array or omit it entirely.

---

## Migration Recommendations

### Option A: Dual-Compatible Agents (Shared Frontmatter Only)

**Approach**: Maintain a single set of agent `.md` files using only frontmatter fields shared between VS Code and copilot-cli.

**Shared fields**: `name`, `description`, `tools`

**Dropped VS Code fields**: `agents`, `argument-hint`, `user-invocable`
**Dropped CLI fields**: `model`, `infer`, `mcpServers` (not added)

**Pros**:
- Single source of truth — no divergence between platforms.
- Unrecognized fields are silently ignored on both platforms (Q-RSK-002).
- Simplest maintenance model.

**Cons**:
- Cannot leverage copilot-cli-specific features (`infer`, `mcpServers`, `model`).
- `agents:` removal means VS Code loses explicit subagent routing (significant for Orchestrator).
- VS Code tool namespaces in `tools:` arrays won't resolve in copilot-cli.

**Verdict**: Not recommended for ralph-v2 due to the `agents:` dependency and tool namespace incompatibility.

---

### Option B: Platform-Specific Agent Variants

**Approach**: Maintain two sets of agent files — `agents/ralph-v2/*.agent.md` for VS Code and `agents/ralph-v2-cli/*.agent.md` for copilot-cli.

**VS Code variant** (current):
```yaml
tools: ['execute/runInTerminal', 'read/readFile', 'edit/editFiles', ...]
agents: ['Ralph-v2-Planner', 'Ralph-v2-Questioner', ...]
```

**Copilot-CLI variant**:
```yaml
tools: ['bash', 'view', 'edit', 'create', 'search', 'task', ...]
infer: true
mcpServers:
  brave-search:
    command: npx
    args: ["-y", "@anthropic/brave-search-mcp"]
```

**Pros**:
- Each platform gets optimized agent definitions.
- Full access to platform-specific features.
- Publish scripts route to the correct variant.

**Cons**:
- Double maintenance burden — changes must be mirrored.
- Risk of variants drifting out of sync.
- More complex publish flow.

**Verdict**: Recommended for production use if copilot-cli becomes a primary target. Best suited when the platforms diverge significantly (as they do for the Orchestrator).

---

### Option C: Conditional Tool Declarations via Agent `tools:` Filtering

**Approach**: Include BOTH VS Code and copilot-cli tool names in the `tools:` array. Each platform ignores unknown tool names.

```yaml
tools:
  # VS Code tools (ignored by copilot-cli)
  - 'execute/runInTerminal'
  - 'read/readFile'
  - 'edit/editFiles'
  - 'vscode/memory'
  # Copilot-CLI tools (ignored by VS Code)
  - 'bash'
  - 'view'
  - 'edit'
  - 'create'
  - 'task'
  # MCP tools (work on both if configured)
  - 'mcp_docker/*'
  - 'deepwiki/*'
```

**Pros**:
- Single file, both platforms work.
- Unknown tool names are silently ignored (no errors).
- MCP tools declared once, work everywhere.

**Cons**:
- Bloated `tools:` arrays with redundant entries.
- Still cannot use `agents:` (VS Code-only) or `infer`/`mcpServers` (CLI-only) simultaneously.
- Confusing for maintainers who need to understand why both namespaces exist.

**Verdict**: Viable for non-Orchestrator agents. The `tools:` bloat is manageable. The Orchestrator still needs a separate approach for `agents:` vs `infer` + TaskTool.

---

### Recommended Approach

**Hybrid of Option B + C**:

1. **Orchestrator**: Use Option B (platform-specific variants) because the orchestration model is fundamentally different (`agents:` vs `infer` + TaskTool).
2. **Other 5 agents**: Use Option C (conditional tools) because their primary differences are tool namespace aliases, which can coexist in a single `tools:` array.
3. **Publish flow**: `publish-agents.ps1` already handles flat publishing to `~/.copilot/agents/`. Add logic to select CLI-variant for the Orchestrator when targeting copilot-cli.
4. **MCP prerequisite**: Document that copilot-cli usage requires MCP servers (Brave Search, DeepWiki, etc.) configured in `~/.copilot/mcp-config.json`.

This minimizes maintenance burden while properly handling the Orchestrator's architectural divergence.
