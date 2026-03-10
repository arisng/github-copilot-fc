# VS Code vs Copilot CLI hook payload field mapping

## Summary

The shared Ralph hook manifest (`.github/hooks/ralph-tool-logger.hooks.json`) is cross-runtime compatible — both VS Code and Copilot CLI accept the lowerCamelCase event keys and `bash`/`powershell` command properties. Both logger scripts implement a **dual-fallback pattern** that reads VS Code snake_case fields first and falls through to CLI camelCase fields, producing identical normalized log entries regardless of runtime.

## Field mapping

### Tool events (`preToolUse` / `postToolUse`)

| Concept | VS Code native field | Copilot CLI field | Logger fallback order | Normalization |
|---------|---------------------|-------------------|-----------------------|---------------|
| Tool name | `tool_name` | `toolName` | `tool_name` → `toolName` | Direct string |
| Tool input | `tool_input` (parsed JSON object) | `toolArgs` (JSON string) | `tool_input` → `toolInput` → `toolArgs` | VS Code object returned directly; CLI string parsed via `ConvertFrom-JsonSafe` (PS) / `fromjson?` (Bash). Both produce a JSON object in `tool_args`. |
| Tool result | `tool_response` (object) | `toolResult` / `toolResponse` | `tool_result` → `toolResult` → `tool_response` → `toolResponse` | Parsed to object via `ConvertFrom-JsonSafe` (PS) / jq (Bash) |
| Result type | Nested in `tool_response.resultType` | Nested in `toolResult.resultType` | All four result containers checked with `.resultType` | Direct string |
| Result text | Nested in `tool_response.textResultForLlm` | Nested in `toolResult.textResultForLlm` | All four result containers checked with `.textResultForLlm` | Direct string |
| Invocation ID | `tool_use_id` | (not present) | (not consumed) | — |

### Subagent events (`subagentStart` / `subagentStop`)

| Concept | VS Code native field | Copilot CLI field | Logger fallback order | Notes |
|---------|---------------------|-------------------|-----------------------|-------|
| Agent identity | `agent_id` | `agentName` | `agent_id` → `agentName` | Used for log `agent` field and active-agent tracking |
| Agent type | `agent_type` | (not present) | `agent_type` only | Conditionally included in log when present; absent for CLI payloads |
| Stop active flag | `stop_hook_active` | `stopHookActive` | `stop_hook_active` → `stopHookActive` | Conditionally included in subagentStop entries |

### Shared fields (both runtimes)

| Field | Notes |
|-------|-------|
| `hookEventName` | Present in both runtimes; loggers normalize PascalCase → lowerCamelCase |
| `timestamp` | Present in both runtimes; converted to ISO 8601 via `ConvertTo-IsoTimestamp` / `to_iso_timestamp` |
| `cwd` | Present in both runtimes |
| `sessionId` | Present in both runtimes; falls back to `.active-session` file content |
| `transcript_path` / `transcriptPath` | Present in both; loggers normalize both variants |

## Dual-fallback implementation

Both loggers use the same priority pattern: **snake_case first → camelCase fallback**.

**PowerShell** — uses `Get-HookProperty` with ordered name arrays:
```powershell
# Tool name: snake_case first
$toolName = Get-HookProperty -Event $event -Names @('tool_name', 'toolName')
# Agent identity: VS Code agent_id first, CLI agentName fallback
$agentName = Get-HookProperty -Event $event -Names @('agent_id', 'agentName')
```

**Bash** — uses jq `//` fallback operator:
```bash
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // .toolName // empty')
AGENT_NAME=$(echo "$INPUT" | jq -r '.agent_id // .agentName // empty')
```

### Key structural difference: `tool_input` vs `toolArgs`

The most significant cross-runtime difference is in tool arguments:

- **VS Code** sends `tool_input` as a **parsed JSON object** — already structured data.
- **CLI** sends `toolArgs` as a **JSON string** — must be parsed before logging.

Both loggers normalize this difference so the logged `tool_args` field is always a JSON object:

| Runtime | Source field | Type | Normalization |
|---------|-------------|------|---------------|
| VS Code | `tool_input` | Object | Returned directly |
| CLI | `toolArgs` | String | `ConvertFrom-JsonSafe` (PS) / `fromjson?` (Bash) |

## Fallback Order Convention

Snake_case (VS Code native) fields are checked first in the fallback order. This ensures that when both field sets are present (which shouldn't happen in practice), the runtime-native field wins. The pattern is consistent across all field lookups in both scripts.
