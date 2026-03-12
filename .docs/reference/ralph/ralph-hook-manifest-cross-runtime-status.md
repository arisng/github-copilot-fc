# Ralph hook manifest cross-runtime compatibility status

## Manifest verdict

The shared Ralph hook manifest (`hooks/ralph-tool-logger/ralph-tool-logger.hooks.json`) is cross-runtime compatible for the four events it currently wires:

| Event | Payload logging | Status |
|-------|----------------|--------|
| `subagentStart` | disabled | Compatible |
| `subagentStop` | disabled | Compatible |
| `preToolUse` | enabled | Compatible |
| `postToolUse` | enabled | Compatible |

The manifest uses Copilot CLI-compatible lowerCamelCase event keys plus `bash` and `powershell` command properties. VS Code documentation confirms it parses Copilot CLI hook configurations and maps those event names into the VS Code runtime.

## Where the real gap is

The compatibility gap is in **payload parsing**, not manifest syntax:

- **Manifest format**: Cross-runtime compatible. No rewrite needed.
- **Payload field names**: Both loggers read CLI-style camelCase fields (`toolName`, `toolArgs`, `toolResult`, `agentName`) while VS Code native payloads use snake_case fields (`tool_name`, `tool_input`, `tool_response`, `agent_type`, `agent_id`). See the VS Code vs CLI hook payload field mapping reference for details.
- **Documentation**: `hooks/README.md` correctly recommends the CLI-style manifest schema for shared files and the nested `hooks/<name>/` authoring layout.

## Scope limitation

The current manifest covers a narrow 4-event telemetry slice. The broader Ralph hook reference appendix (`agents/ralph-v2/docs/reference/hooks-integrations.md`) describes a wider proposed hook catalog that is aspirational — it does not reflect the current implementation.
