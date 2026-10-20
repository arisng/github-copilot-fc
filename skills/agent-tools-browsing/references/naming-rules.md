# Naming rules for the `tools:` frontmatter field

The `tools:` field of a custom agent is a **runtime-local allowlist**. The same list can be correct in one runtime and meaningless in another. These are the rules that decide which names belong in it.

## 1. Pick the runtime before picking names

A `tools:` list is only meaningful against the runtime that will load the agent file.

| Runtime | Agent file lives in | Vocabulary |
|---|---|---|
| `cli` | `~/.copilot/agents/`, `.github/agents/`, `.claude/agents/` | CLI aliases plus concrete built-ins |
| `agent-host` | Same files, loaded by the VS Code Agent Host | Identical to `cli` |
| `vscode` | VS Code custom agent | Conceptual aliases, `category/tool` ids, extension tools |
| `github-copilot` | Repository agent profile on GitHub.com | Conceptual aliases plus `github/*` and `playwright/*` |

`copilot-cli-agent-customization` covers where agent files go and which frontmatter keys each runtime honors. This skill covers the names inside `tools:`.

## 2. Alias and concrete built-in are different surfaces

A conceptual alias expands to several tools. A concrete built-in is one tool.

- **Conceptual aliases** — `execute`, `read`, `edit`, `search`, `agent`, `web`, `todo`. These are the cross-runtime names and the ones the vendor documents for the cloud agent and VS Code.
- **Concrete built-ins** — `bash`, `powershell`, `view`, `create`, `edit`, `apply_patch`, `grep`, `rg`, `glob`, `web_fetch`, `read_bash`, `stop_bash`, `write_bash`, `list_bash`, `lsp`, `ask_user`, `update_todo`, `task`, `read_agent`, `list_agents`, `write_agent`, `context_board`.

The CLI command reference publishes concrete built-in names in its **Tool availability values** table, because that table documents `--available-tools` and `--excluded-tools`. Those are *session flags*, not the agent `tools:` list. Do not treat the two as one list.

**What the runtime's own agents prove.** The CLI ships built-in agent definitions in `~/.copilot/pkg/<platform>/<version>/definitions/*.agent.yaml`, and the VS Code Agent Host SDK ships byte-identical copies. The `explore` agent's `tools:` list is:

```
grep, glob, view, bash, read_bash, stop_bash, powershell, read_powershell, stop_powershell, lsp
```

So the CLI and Agent Host accept **concrete built-in names**, not only aliases. The March 2026 workspace note that listed `bash, view, edit, search` as the only valid CLI names is outdated on this point, and its `create` finding is now doubtful: `create` is a documented built-in, but no shipped agent uses it.

**Practical rule.** Prefer a shipped or documented alias when one covers the capability. Reach for a concrete built-in only when no alias exists for what the agent needs, and say so when you do.

## 3. `*` anywhere means everything

The CLI documents the `tools` field as: *Tools available to the agent. Default: `["*"]` (all tools). Include `*` anywhere in the list to grant full tool access — for example, `["view", "*"]` grants every tool, not just `view`.*

So `["view", "*"]` is an unrestricted agent. A list that looks scoped but contains `*` is not scoped.

- `tools: []` — no tools at all.
- `tools: ["*"]` — every tool. This is also the default when `tools` is omitted, so an agent with no `tools:` key is unrestricted.
- Any list containing `*` — every tool.

## 4. Unknown names are silently ignored

Unrecognized names do not raise an error. They are dropped, and the agent keeps whatever else the list grants. A typo therefore widens the agent rather than narrowing it, and there is no error to notice.

Run the candidate list through the `check` mode before writing it.

## 5. MCP tools use `serverName/toolName`

- One tool: `github-mcp-server/get_commit`, `mcp_docker/fetch_content`.
- A whole server: `github-mcp-server/*`.
- An extension proxy in VS Code: `azure.some-extension/some-tool`.
- The cloud agent's out-of-the-box servers are `github` and `playwright`, addressed as `github/*` and `playwright/*`.

A slash in a name means an MCP or extension tool, never a built-in. The CLI and the Agent Host sanitize MCP names to `serverName-toolName` in the *runtime* surface; the `tools:` allowlist keeps the slash form.

## 6. Case sensitivity differs

- `cli` and `agent-host` are **case sensitive**. `Bash` is not `bash`.
- `vscode` and `github-copilot` are **case insensitive**. `read/readFile` and `read/readfile` are the same tool.

## 7. The Agent Host and the extension host are different runtimes

The VS Code **Agent Host** runs the Copilot SDK harness and speaks the CLI vocabulary. The VS Code **extension host** runs the editor-side tools and speaks the `category/tool` vocabulary. The same agent file can be valid in one and ignored in the other.

Client-contributed tools — browser tools and tools from installed extensions — are added by the connected client and routed back to it. They are not nameable from a `tools:` allowlist, and they stop working when the client disconnects.

## 8. The cloud agent has its own gaps

- `todo` is not supported in the cloud agent. Naming it has no effect.
- The cloud agent has no local development context, so VS Code built-in tools are unavailable regardless of what the list says.
- Its token is scoped to the source repository.

## 9. VS Code has a request-size ceiling

A single chat request may carry at most 128 tools. Long allowlists, plus MCP servers, plus extension tools, can exceed that and fail the request. Prefer tool sets and virtual tools over long lists. `toolSearch` lets the agent search the catalog instead of receiving every tool.

## Naming checklist

1. Which runtime will load this agent file?
2. Does the intent need a capability with no alias? If so, which concrete built-in covers it?
3. Is `*` absent from the list?
4. Does every name validate against that runtime's vocabulary?
5. Are MCP names written as `serverName/toolName`, with the server actually configured?
6. For VS Code, is the list short enough to stay under 128 tools?
