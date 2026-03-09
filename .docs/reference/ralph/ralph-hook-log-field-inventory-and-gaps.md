# Ralph hook log field inventory and telemetry gaps

## tool-usage.jsonl fields (12 fields)

| Field | Source | Presence | Audit value |
|-------|--------|----------|-------------|
| `ts` | Event timestamp (raw) | Always | Temporal ordering |
| `ts_iso` | Derived ISO8601 | When derivable | Human-readable timestamps |
| `sid` | Session ID | Always | Session scoping |
| `event` | Normalized event name | Always | Event type filtering |
| `cwd` | Working directory | Always | Workspace context |
| `transcript_path` | Event payload | When present | Agent correlation key |
| `agent` | transcript_path lookup → lastAgent fallback | When subagentStart has fired | Agent attribution |
| `tool` | toolName field | When present | Tool identification |
| `result_type` | toolResult.resultType (postToolUse) | When present | Quick triage |
| `result_text` | toolResult.textResultForLlm (postToolUse) | When present | Result preview |
| `tool_args` | Normalized from toolInput/toolArgs | When RALPH_LOG_PAYLOAD=true | Deep input inspection |
| `tool_result` | Full tool result object | When RALPH_LOG_PAYLOAD=true | Deep output inspection |

**Note**: The Bash logger currently drops ALL tool-usage entries due to a jq empty-propagation bug. See the jq empty-propagation reference for details. The field inventory above is verified for the PowerShell logger only until the Bash bug is fixed.

## subagent-usage.jsonl fields (8 fields)

| Field | Source | Presence |
|-------|--------|----------|
| `ts` | Event timestamp | Always |
| `ts_iso` | Derived ISO8601 | When derivable |
| `sid` | Session ID | Always |
| `event` | subagentStart or subagentStop | Always |
| `cwd` | Working directory | Always |
| `agent` | agentName field | When present |
| `transcript_path` | Event payload | When present |
| `stop_hook_active` | subagentStop payload | When present |

## Agent attribution bridge

1. On `subagentStart`: loggers add `transcript_path → agent` to `active-agents.json` and update `lastAgent`.
2. On tool events: loggers look up agent by `transcript_path` in `active-agents.json`; fall back to `lastAgent` if no match.
3. On `subagentStop`: loggers remove the `transcript_path` entry and recalculate `lastAgent` from remaining active agents.

This supports multi-agent disambiguation when concurrent subagents carry distinct `transcript_path` values.

## Known telemetry gaps

| Gap | Severity | Notes |
|-----|----------|-------|
| No invocation correlation ID | Medium | VS Code provides `tool_use_id` but loggers do not consume it. Pre/post pairing relies on timestamp + tool name heuristic. |
| No duration field | Low | Raw timestamps available; duration is a post-processing computation. |
| VS Code native payload fields not consumed | High | Both loggers read CLI-style camelCase only. See the VS Code vs CLI hook payload field mapping reference. |
| No permission/approval decision capture | Low | Not present in current hook payloads from either runtime. |
| Bash `ts_iso` requires functional python3 | Medium | Degrades to `null` when unavailable. Complicated by Windows App Alias shim — see the python3 bash pitfall reference. |
