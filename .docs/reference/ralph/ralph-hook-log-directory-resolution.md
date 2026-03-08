# Ralph hook log directory resolution

## Purpose

This reference defines where Ralph hook logger events are written and how the logger chooses between iteration-scoped and session-scoped paths.

## Resolution algorithm

1. Read the repository-local session root from `<event.cwd>/.ralph-sessions`.
2. Read the active session id from `.ralph-sessions/.active-session`.
3. Set the fallback log directory to `.ralph-sessions/<SESSION_ID>/logs`.
4. Read `.ralph-sessions/<SESSION_ID>/metadata.yaml`.
5. If the metadata contains a valid integer line `iteration: <N>`, use `.ralph-sessions/<SESSION_ID>/iterations/<N>/logs`.
6. If the metadata file is missing, unreadable, malformed, or does not expose an integer iteration value, keep the session-level fallback directory.
7. Create the selected log directory on demand and append to `tool-usage.jsonl`.

## Output guarantees

- Hook execution remains non-fatal.
- The logger returns `{"continue":true}` even when it falls back to the session-level path.
- The log file name is always `tool-usage.jsonl`.

## Event schema

- `SubagentStart` and `SubagentStop` write `ts`, `sid`, `event`, and `agent`.
- `PreToolUse` and `PostToolUse` write `ts`, `sid`, `event`, `agent`, and `tool`.
- Tool `input` is also logged when payload logging is enabled for that code path.

## Cross-shell notes

- The PowerShell logger includes `input` when `RALPH_LOG_PAYLOAD=true` and the hook event carries `toolInput`.
- The Bash logger preserves `input` for `PreToolUse` and `PostToolUse` unless payload logging is explicitly disabled with `RALPH_LOG_PAYLOAD=false`.
- On Windows-hosted Bash replays, the Bash logger can fall back to `powershell.exe` to serialize `toolInput` when the local `jq` path cannot provide `jq -c '.toolInput // null'`.

## Verified behavior

Iteration 2 verification confirmed the same six-field tool-event schema across PowerShell and Bash on both the normal iteration-scoped path and the degraded session-level fallback path:

- `ts`
- `sid`
- `event`
- `agent`
- `tool`
- `input`
