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
7. Create the selected log directory on demand and append to the Ralph hook log files.

## Output guarantees

- Hook execution remains non-fatal.
- The logger returns `{"continue":true}` even when it falls back to the session-level path.
- Tool events are written to `tool-usage.jsonl`.
- Subagent lifecycle events are written to `subagent-usage.jsonl`.

## Event schema

- `subagentStart` and `subagentStop` write `ts`, `ts_iso`, `sid`, `event`, `cwd`, `transcript_path`, and `agent` to `subagent-usage.jsonl`.
- `preToolUse` and `postToolUse` write `ts`, `ts_iso`, `sid`, `event`, `cwd`, `transcript_path`, `agent`, and `tool` to `tool-usage.jsonl`.
- When available, `result_type` and `result_text` are captured for `postToolUse`.
- When payload logging is enabled, the logger also records normalized `tool_args` and `tool_result` payloads.

## Cross-shell notes

- The PowerShell and Bash loggers normalize both `toolInput` and `toolArgs` into `tool_args`.
- The PowerShell and Bash loggers normalize both `toolResult` and `toolResponse` into `tool_result`.
- Agent attribution is keyed by `transcript_path` via `.ralph-sessions/.hook-state/active-agents.json`, with `lastAgent` kept only as a fallback.
- On Windows-hosted Bash replays, the Bash logger can fall back to `powershell.exe` to serialize `toolArgs` when the local `jq` path cannot parse the payload.

## Verified behavior

The logger contract now guarantees separate tool and subagent audit trails across PowerShell and Bash on both the normal iteration-scoped path and the degraded session-level fallback path.

- `ts`
- `ts_iso`
- `sid`
- `event`
- `cwd`
- `transcript_path`
- `agent`
- `tool`
- `tool_args`
- `result_type`
- `result_text`
- `tool_result`
