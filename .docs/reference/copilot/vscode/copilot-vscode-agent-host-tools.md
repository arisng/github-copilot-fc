# Copilot Agent Host and Agents Window Tool Surface Reference

Reference for the tools available to agents running in the **VS Code Agent Host** — the dedicated process that backs the **Agents window** in VS Code Insiders — and for how that surface differs from the VS Code extension host.

The cross-runtime tool data lives in [`tools/inventory.yaml`](../../../../tools/inventory.yaml) (category `agent-host`). This page explains the runtime model behind it.

## Runtime at a glance

| Piece | Role |
|---|---|
| **Agent Host** | Dedicated process that runs agent harnesses and owns their sessions. Separate from the editor extension host and from the standalone `copilot` CLI binary. |
| **Agent harness** | Implementation that coordinates the model, tools, and workflow. Adapters exist for Copilot (SDK), Claude (SDK), and Codex. |
| **Client** | The Chat view, the Agents window, or the browser UI. Displays and controls a session; does not own it. |

The Agent Host speaks the **Agent Host Protocol (AHP)** — JSON-RPC over a local message pipe, or over WebSocket for a remote host. It can run as a local utility process or as a standalone server (`code agent host`).

## Tool availability model

Tools reach a session in three layers, and the layer determines whether a tool is present at all.

1. **Harness built-in tools** — supplied by the harness itself. In the Copilot harness these are read-only in the **Tools** tab of the Agent Customizations editor; they run in the Copilot runtime, not in the client.
2. **Client-contributed tools** — supplied by a connected client, such as browser tools or tools from installed extensions. The host adds those definitions to the session and routes each tool call back to the contributing client, so **they require that client to stay connected**. The Agent Host's own baseline session and workspace capabilities work without a client.
3. **Extension tools** — available only in chats in an editor window where the extension is running. The Agents window shows the availability list but cannot browse the Marketplace to add more.

Enabling a tool is separate from approval: enabling makes it available, but approval and permission controls still apply.

## Copilot harness tool vocabulary

The Copilot harness in the Agent Host runs the **Copilot SDK runtime**, so it uses the **Copilot CLI tool names**, not the VS Code extension tool names.

| Agent Host tool | VS Code extension counterpart | Purpose |
|---|---|---|
| `bash`, `powershell` | `execute/runInTerminal` | Run a shell command |
| `read_bash`, `read_powershell` | `execute/getTerminalOutput` | Read shell-session output |
| `write_bash`, `write_powershell` | `execute/sendToTerminal` | Send input to a shell session |
| `stop_bash`, `stop_powershell` | `execute/killTerminal` | Terminate a shell session |
| `list_bash`, `list_powershell` | — | List active shell sessions |
| `view` | `read/readFile` | Read files or directories |
| `create` | `edit/createFile` | Create files |
| `edit` | `edit/editFiles` | Edit files |
| `apply_patch` | `edit/applyPatch` | Apply a patch |
| `grep`, `rg` | `search/textSearch` | Search text in files |
| `glob` | `search/fileSearch` | Find files by pattern |
| `task` | `agent/runSubagent` | Run a subagent |
| `read_agent`, `list_agents`, `write_agent` | — | Inspect and steer background agents |
| `skill` | `read/skill` | Invoke a custom skill |
| `ask_user` | `vscode/askQuestions` | Ask the user a question |
| `web_fetch` | `web/fetch` | Fetch and parse web content |
| `lsp` | — | Query language servers |
| `task_complete`, `exit_plan_mode` | — | End a turn / leave plan mode |

**There is no `readFile`, `editFiles`, or `runInTerminal` in this runtime.** Those names belong to the VS Code extension-host tool surface, which is a different runtime.

The SDK runtime exposes a `tools.list` JSON-RPC method to enumerate the built-in tools for a model, and accepts tool filter entries of the form `builtin:bash` and `builtin:*`.

## Built-in agents

The SDK ships agent definitions that use the CLI tool names in their `tools:` frontmatter.

| Agent | Tools | Notes |
|---|---|---|
| `explore` | `grep`, `glob`, `view`, `bash`, `read_bash`, `stop_bash`, `powershell`, `read_powershell`, `stop_powershell`, `lsp` | Read-only codebase exploration, safe to call in parallel |
| `code-review` | `*` | Read-only reviewer of staged, unstaged, or branch diffs |
| `security-review` | `*` | Security-focused review |
| `research` | `*` | Research subagent, searches repos and verifies claims |
| `rubber-duck` | `*` | Constructive critic for proposals and implementations |
| `task` | `*` | Runs tests, builds, linters, and formatters |
| `rem-agent` | `context_board` | Memory consolidation, launched from `/subconscious` |

`context_board` (operations `add` and `prune`) is the Agent Host memory surface. The Copilot CLI's `store_memory`, `read_memories`, and `vote_memory` built-ins are **not** part of the SDK runtime's tool set.

## Harnesses in the Agents window

| Harness | Runs in | Available in the Agents window |
|---|---|---|
| **Copilot** | Agent Host (Copilot SDK) | Yes |
| **Claude** | Anthropic Claude Agent SDK | Yes |
| **Codex** (Agent Host integration) | Agent Host | Yes (experimental) |
| **Codex** (OpenAI extension) | Extension host | No — main VS Code window only |
| **Local** | Extension host | No — main VS Code window only |
| **Cloud** | Provider-managed infrastructure | GitHub-backed repositories only |

## Agents window limitations that affect tool use

- The agents dropdown has no plan agent. Use the `/plan` command, or the plan agent is invoked automatically in Copilot harness sessions.
- Running multiple chats in one session is supported only for the Copilot and Claude harnesses.
- Multi-root sessions are not supported.
- Copilot Cloud sessions require a GitHub-backed repository.

## Local grounding

Observed on VS Code Insiders `1.143.0-insider`:

| Artifact | Value |
|---|---|
| Bundled Copilot extension | `copilot-chat` `0.71.2026101901` — 38 language model tools, 6 tool sets (`edit`, `execute`, `read`, `search`, `vscode`, `web`) |
| Agent Host runtime | `copilot-runtime.exe` from `@github/copilot-sdk-win32-x64`, launched `--headless --stdio --no-auto-login` |
| Copilot CLI shim | `bin/copilot-shim/copilot.exe` — lets the Agents window drive the `copilotcli` harness |
| Agent Host endpoints | `<user-data>/agent-host/local-endpoint/metadata.json` — named pipe `vscode-agent-host-*`, `protocolVersion` `0.7.0`, per-instance connection token |
| Synced customizations | `<user-data>/agentPlugins/vscode-synced-customization-agent-host-copilotcli-*` — Copilot CLI plugins and skills are synced into the Agent Host |

## Cross-references

- [`tools/inventory.yaml`](../../../../tools/inventory.yaml) — the machine-readable inventory, category `agent-host`
- [Agent Host architecture](https://code.visualstudio.com/docs/agents/concepts/agent-host) — upstream documentation
- [Use tools with agents](https://code.visualstudio.com/docs/agents/run/tools) — tool availability and approvals
- [Tools and context reference](https://code.visualstudio.com/docs/agents/reference/tools-reference) — VS Code built-in tool names
- [Agents window](https://code.visualstudio.com/docs/agents/run/agents-window) — the Agents window surface
