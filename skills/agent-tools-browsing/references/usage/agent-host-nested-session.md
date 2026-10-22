# Create a nested session in the Agent Host

**Runtime:** `agent-host`  **Tools:** `create_session`, `move_session`, `list_sessions`, `get_current_session`

## When to use this

The VS Code Agents window shows one card per session. Hovering a card reveals
a **+** button that creates a *nested* session under it — a second chat
belonging to that session, visible in the sidebar beneath the parent. This
scenario does that programmatically.

## Before you start

Read [agent-host-session-tools.md](agent-host-session-tools.md) first. It
covers the tool surface, the create-versus-move distinction, the
`move_session` gates, and the nesting model. In short:

- `create_session` **creates**; `move_session` **re-parents**. They are not
  interchangeable.
- `create_session` with `currentSession` is bound to the **invoking**
  session and cannot target an arbitrary other session. That is why the
  cross-session case needs two steps.
- `move_session` is gated by the `chat.agentHost.moveChats.enabled` setting
  (default **false**), the provider's `multipleChats` capability, and
  top-level-chat-only enforcement.
- Nesting depth is **one level**. A nested session is a peer chat of its
  parent, not a container, so it cannot own nested sessions of its own.

## Steps

### Case A — nest under the current session

One call. Use this whenever the parent is the session you are running in.

```json
{ "name": "create_session", "arguments": { "relationship": "currentSession", "title": "review-the-auth-flow", "prompt": "Review the auth flow and report findings." } }
```

This creates a new chat with its own id, registers it in the parent's
peer-chat list, and gives it its own title and provider data — a sibling of
the parent's main chat, which is how the window renders a nested session.

### Case B — nest under a different session

Two calls, because no single call does create-and-nest for an arbitrary
target.

**Step 1** — create the session standalone:

```json
{ "name": "create_session", "arguments": { "relationship": "independent", "title": "review-the-auth-flow", "prompt": "Review the auth flow and report findings." } }
```

The return value is an `agent-host-session://` link for the new session, and
that link is what step 2 needs.

**Step 2** — nest it under the target:

```json
{ "name": "move_session", "arguments": { "session": "agent-host-session://ahp-session/<new-session-id>", "relationship": "nested", "into": "agent-host-session://ahp-session/<target-session-id>" } }
```

Get both links from `list_sessions`. For a session that already has nested
sessions, its `chats` array lists the main session (`main: true`) and each
nested session, each with an `openLink` naming that chat. Omit `after` to
place the moved session at the end; set it to a sibling's `openLink` to place
it after that one.

## Verify

```json
{ "name": "list_sessions", "arguments": { "session": "agent-host-session://ahp-session/<parent-session-id>" } }
```

The parent's `chats` array now lists the new nested session, with its title
and an `openLink`. To confirm it has its own conversation, read it back with
`get_session_context` using that `openLink`.

## Pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| New session is top-level, not nested | `independent` was used | Use `currentSession` for the current parent, or nest with `move_session`. |
| `move_session` missing from the tool list | `chat.agentHost.moveChats.enabled` is off | Enable it. It defaults to false. |
| "must use the same agent" | The sessions run different harnesses | Move only into a session using the same agent. |
| The move is refused | Session has nested sessions, is archived, or is changing workspace | A whole session moves only when it has no nested sessions. Move those individually, or unarchive first. |
| The move applies at end of turn | The tool moved the chat it runs in | The host defers a self-move. Make it the final call of the turn. |
| Nested session cannot be moved again | `move_session` is top-level-chat-only | Call it from a top-level session. |
