---
category: reference
---

# Windows Hook Manifest-Runtime Smoke Test Contract

## Summary

The workspace keeps a dedicated Windows smoke test at `hooks/scripts/tests/test-windows-hook-runtime.ps1` to guard the shared Ralph hook logger against parser and startup regressions under the exact manifest runtime.

## Runtime Under Test

- The test validates the Windows manifest command declared in `hooks/ralph-tool-logger.hooks.json`: `powershell -NoProfile -File hooks\scripts\ralph-tool-logger.ps1`.
- It treats that command as the contract, not just the logger script in isolation.
- All four shared hook events use the same PowerShell entrypoint: `subagentStart`, `subagentStop`, `preToolUse`, and `postToolUse`.

## Required Coverage

The smoke test should replay all four shared events through the configured manifest entrypoint.

| Event | Expected log |
| ----- | ------------ |
| `subagentStart` | `subagent-usage.jsonl` entry with agent identity and transcript path |
| `preToolUse` | `tool-usage.jsonl` entry with tool name and normalized `tool_args` |
| `postToolUse` | `tool-usage.jsonl` entry with `result_type`, `result_text`, and payload fields when enabled |
| `subagentStop` | `subagent-usage.jsonl` entry with agent identity and `stop_hook_active` when present |

## Failure Semantics

- Any non-zero exit code from the manifest command must fail the test immediately.
- Any response missing `"continue": true` must fail the test immediately.
- The test must not continue to later assertions after a parser or startup failure in the configured Windows runtime.

## Harness Design

- Build an isolated temporary workspace rather than invoking the logger against the repository's live session artifacts.
- Create `.ralph-sessions/.active-session` and `.ralph-sessions/<SESSION_ID>/metadata.yaml` in the temporary workspace so the logger exercises real session and iteration log-path resolution.
- Assert the manifest wiring before replaying events so the test catches configuration drift as well as script regressions.
- Validate the last JSONL entry after each replay to confirm the runtime produced the expected durable log fields.

## Maintenance Implication

When modifying either `hooks/scripts/ralph-tool-logger.ps1` or `hooks/ralph-tool-logger.hooks.json`, keep this smoke test passing under the exact `powershell` manifest command. That preserves coverage for the full four-event Windows blast radius instead of only tool-hook paths.
