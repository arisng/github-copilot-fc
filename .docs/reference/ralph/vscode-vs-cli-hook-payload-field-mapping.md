# VS Code vs Copilot CLI hook payload field mapping

## Summary

The shared Ralph hook manifest (`hooks/ralph-tool-logger.hooks.json`) is cross-runtime compatible — both VS Code and Copilot CLI accept the lowerCamelCase event keys and `bash`/`powershell` command properties. The real compatibility gap is in **payload field naming**: both Ralph logger scripts consume CLI-style camelCase fields while VS Code-native payloads use snake_case fields.

## Field mapping

### Tool events (`preToolUse` / `postToolUse`)

| Concept | Copilot CLI field | VS Code native field | Ralph logger reads |
|---------|-------------------|---------------------|--------------------|
| Tool name | `toolName` | `tool_name` | `toolName` only |
| Tool input | `toolArgs` / `toolInput` | `tool_input` | `toolArgs`, `toolInput` |
| Tool result | `toolResult` / `toolResponse` | `tool_response` | `toolResult`, `toolResponse` |
| Invocation ID | (not present) | `tool_use_id` | (not consumed) |

### Subagent events (`subagentStart` / `subagentStop`)

| Concept | Copilot CLI field | VS Code native field | Ralph logger reads |
|---------|-------------------|---------------------|--------------------|
| Agent name | `agentName` | `agent_type` | `agentName` only |
| Agent ID | (not present) | `agent_id` | (not consumed) |
| Stop active flag | (not present) | `stop_hook_active` | (consumed when present) |

### Shared fields (both runtimes)

| Field | Notes |
|-------|-------|
| `hookEventName` | Present in both runtimes |
| `timestamp` | Present in both runtimes |
| `cwd` | Present in both runtimes |
| `sessionId` | Present in both runtimes |
| `transcript_path` / `transcriptPath` | Present in both; loggers normalize both variants |

## Impact

Under native VS Code payloads, the Ralph loggers may produce blank or degraded values for `tool`, `tool_args`, `tool_result`, and `agent` fields because the CLI-style field names they check are not present. The logger does not crash — it just writes empty values for those fields.

## Recommended fix pattern

Add snake_case fallbacks alongside existing camelCase reads in both loggers:

```powershell
# PowerShell example:
$ToolName = $Event.toolName ?? $Event.tool_name ?? ''
$ToolInput = $Event.toolInput ?? $Event.toolArgs ?? $Event.tool_input ?? $null
$ToolResult = $Event.toolResult ?? $Event.toolResponse ?? $Event.tool_response ?? $null
$AgentName = $Event.agentName ?? $Event.agent_type ?? $Event.agent_id ?? ''
$ToolUseId = $Event.tool_use_id ?? $null
```
