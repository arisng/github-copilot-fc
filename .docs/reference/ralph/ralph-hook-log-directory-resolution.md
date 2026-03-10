# Ralph hook log directory resolution

## Purpose

This reference defines where Ralph hook logger events are written and how the logger chooses between iteration-scoped and session-scoped paths. It also documents the deployment model and session-state validation that prevents stale log pollution.

## Deployment model

The hook manifest is deployed as a **workspace-scoped** file at `.github/hooks/ralph-tool-logger.hooks.json`. This is the primary deployment location — GitHub Copilot discovers and loads hooks from `.github/hooks/` relative to the workspace root.

The manifest references logger scripts at `hooks/scripts/ralph-tool-logger.ps1` (PowerShell) and `hooks/scripts/ralph-tool-logger.sh` (Bash), both resolved relative to the workspace root.

## Session-state validation guard

Before resolving the log directory, both loggers perform a defensive validation sequence that rejects stale or completed sessions:

1. **Active-session file check**: If `.ralph-sessions/.active-session` does not exist, exit with `{"continue":true}`.
2. **Session ID resolution**: Read from event `sessionId` first, then fall back to `.active-session` file content.
3. **Session directory existence**: If `.ralph-sessions/<SESSION_ID>/` does not exist, emit a stderr warning and exit with `{"continue":true}`.
4. **Orchestrator state check**: Read `.ralph-sessions/<SESSION_ID>/metadata.yaml`. If `state: COMPLETE` is found, emit a stderr warning and exit with `{"continue":true}`.

This `.active-session` lifecycle defense prevents stale-session data corruption — without it, hook events from a new Copilot session could pollute a completed Ralph session's logs.

### Fail-open design

- If `metadata.yaml` is missing or unreadable, logging proceeds normally (fail-open).
- PowerShell wraps the metadata read in `try/catch`; Bash uses `[ -f ]` guard and `2>/dev/null` on grep.
- The validation never blocks the agent session: all exit paths use exit code 0 with `{"continue":true}`.

## Log directory resolution algorithm

After session-state validation passes:

1. Read the repository-local session root from `<event.cwd>/.ralph-sessions`.
2. Read the active session ID from `.ralph-sessions/.active-session`.
3. Set the fallback log directory to `.ralph-sessions/<SESSION_ID>/logs`.
4. Read `.ralph-sessions/<SESSION_ID>/metadata.yaml`.
5. If the metadata contains a valid integer line `iteration: <N>`, use `.ralph-sessions/<SESSION_ID>/iterations/<N>/logs`.
6. If the metadata file is missing, unreadable, malformed, or does not expose an integer iteration value, keep the session-level fallback directory.
7. Create the selected log directory on demand and append to the Ralph hook log files.

## Output guarantees

- Hook execution remains non-fatal.
- The logger returns `{"continue":true}` in all cases — normal logging, fallback paths, and validation rejections.
- Tool events are written to `tool-usage.jsonl`.
- Subagent lifecycle events are written to `subagent-usage.jsonl`.

## Event schema

- `subagentStart` and `subagentStop` write `ts`, `ts_iso`, `sid`, `event`, `cwd`, `transcript_path`, `agent`, and `agent_type` (when present) to `subagent-usage.jsonl`.
- `preToolUse` and `postToolUse` write `ts`, `ts_iso`, `sid`, `event`, `cwd`, `transcript_path`, `agent`, `agent_type` (when present), and `tool` to `tool-usage.jsonl`.
- When available, `result_type` and `result_text` are captured for `postToolUse`.
- When payload logging is enabled (`RALPH_LOG_PAYLOAD=true`), the logger also records normalized `tool_args` and `tool_result` payloads.

## Cross-shell notes

- Both loggers implement a dual-fallback pattern: VS Code snake_case fields are checked first, then CLI camelCase fields (see `vscode-vs-cli-hook-payload-field-mapping.md`).
- VS Code sends `tool_input` as a parsed JSON object; CLI sends `toolArgs` as a JSON string. Both loggers normalize to the same JSON object in `tool_args`.
- Agent attribution is keyed by `transcript_path` via `.ralph-sessions/.hook-state/active-agents.json`, with `lastAgent` kept only as a fallback.
- The Bash logger uses `resolve_python()` to find a working Python interpreter (skipping Windows App Alias shims) for ISO timestamp conversion.
- On Windows-hosted Bash replays, the Bash logger can fall back to `powershell.exe` to serialize `toolArgs` when the local `jq` path cannot parse the payload.

## Verified behavior

The logger contract guarantees:
- Separate tool and subagent audit trails across PowerShell and Bash.
- Correct logging on both the normal iteration-scoped path and the degraded session-level fallback path.
- Clean rejection of stale/completed sessions with no log entries written.
- Fail-open on missing/unreadable metadata — logging proceeds on the fallback path.

### Log entry fields

| Field | Tool events | Subagent events | Notes |
|-------|:-----------:|:---------------:|-------|
| `ts` | ✓ | ✓ | Raw timestamp from event |
| `ts_iso` | ✓ | ✓ | ISO 8601 conversion |
| `sid` | ✓ | ✓ | Session ID |
| `event` | ✓ | ✓ | Normalized event name |
| `cwd` | ✓ | ✓ | Working directory |
| `transcript_path` | ✓ | ✓ | When present |
| `agent` | ✓ | ✓ | Resolved agent identity |
| `agent_type` | ✓ | ✓ | VS Code only; omitted for CLI |
| `tool` | ✓ | — | Tool name |
| `tool_args` | ✓* | — | *When `RALPH_LOG_PAYLOAD=true` |
| `result_type` | ✓ | — | From tool result container |
| `result_text` | ✓ | — | From tool result container |
| `tool_result` | ✓* | — | *When `RALPH_LOG_PAYLOAD=true` |
| `stop_hook_active` | — | ✓ | subagentStop only; when present |
