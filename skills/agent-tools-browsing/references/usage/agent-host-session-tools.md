# Agent Host session-management tools

Shared reference for the Agent Host's session-management tool group. Every
`agent-host` scenario that touches sessions links here for the tool surface
and the gates, so each scenario file can stay short and hold only its
procedure.

These tools are **host-provided**. The Agent Host registers them per session
and they are **not** nameable in an agent's `tools:` frontmatter — no agent
file grants them. See [../naming-rules.md](../naming-rules.md) §7b.

## The tools

| Tool | Relationship | Effect |
|---|---|---|
| `create_session` | `currentSession` | Creates a new chat in the invoking session. |
| `create_session` | `independent` | Creates a brand-new top-level session. |
| `move_session` | `nested` | Re-parents a session or nested session into a target session. |
| `move_session` | `independent` | Promotes a nested session back to top-level. |
| `list_sessions` | — | Lists sessions; a session with nested sessions also lists its `chats`. |
| `get_current_session` | — | Metadata and open link for the invoking session. |
| `get_session_context` | — | Reads a session's or nested chat's recent conversation. |
| `delete_session` | — | Deletes a session. |
| `rename_chat` | — | Renames one chat in a session. |
| `set_workspace` | — | Changes the current chat's workspace and worktree isolation. |
| `isolate_session` | — | Moves the current chat into its own Git worktree. |
| `add_artifact_or_reference` and siblings | — | Manage the artifact list surfaced next to a chat. |

`create_chat` is a legacy alias in the same group. It additionally accepts an
explicit `session` argument, where `create_session` only targets the
invoking session or an independent one.

## The create / move distinction

`create_session` creates. `move_session` re-parents. They are not
interchangeable, and confusing them is the most common mistake.

`create_session` with `currentSession` is bound to the **invoking** session.
It cannot target an arbitrary other session. To put a new session under a
different session, create it standalone and then nest it.

## Gates on `move_session`

1. The `chat.agentHost.moveChats.enabled` setting, which defaults to
   **false**. When off, the tool is absent from the session and the call
   fails pointing at the setting.
2. The provider must advertise the `multipleChats` capability. The Copilot,
   Claude, and Codex harnesses do.
3. The tool is **top-level-chat-only** — it cannot be called from inside a
   nested session.

## The nesting model

A session card in the Agents window is one session. A nested session is a
**peer chat** of that parent, not a separate session entity. This is why:

- nesting depth is capped at **one level** — a peer chat cannot own nested
  sessions of its own;
- `list_sessions` reports nested sessions in the parent's `chats` array,
  where the main session carries `main: true` and each nested session has
  its own `title` and `openLink`;
- a link carrying a chat id (`?chat=<id>`) addresses one nested session,
  while a bare session link addresses the whole session.

## Cross-references

- [agent-host-nested-session.md](agent-host-nested-session.md) — the procedure.

This skill travels with its own directory, so it must not depend on files
outside it. The workspace reference for the full Agent Host tool surface
lives at `.docs/reference/copilot/vscode/copilot-vscode-agent-host-tools.md`.
