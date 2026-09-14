# Hook Lifecycle Reference

## All 9 Hook Types

| Hook | Trigger | Input | Output |
|------|---------|-------|--------|
| `sessionStart` | Session begins | `{ sessionId }` | `{ additionalContext: string }` |
| `sessionEnd` | Session ends | `{ sessionId }` | Cleanup logic |
| `userPromptSubmitted` | User sends message | `{ prompt, sessionId }` | Modified prompt or `null` |
| `preToolUse` | Before tool executes | `{ toolName, toolArgs, sessionId }` | `allow`/`deny` decision |
| `postToolUse` | After tool succeeds | `{ toolName, toolResult, sessionId }` | Transformed result or `null` |
| `postToolUseFailure` | After tool fails | `{ toolName, toolResult, sessionId }` | Transformed result or `null` |
| `errorOccurred` | Error happens | Error details | Custom error handling |
| `subagentStart` | Sub-agent begins | Agent context | — |
| `subagentStop` | Sub-agent ends | Agent context | — |

## hooks.json Format

```json
{
  "version": 1,
  "hooks": {
    "sessionStart": [
      {
        "type": "command",
        "command": "echo 'Session started'",
        "timeout": 10
      }
    ],
    "preToolUse": [
      {
        "type": "command",
        "command": "./scripts/validate-tool.sh",
        "timeout": 5
      }
    ]
  }
}
```

## Hook Entry Properties

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `type` | string | Yes | `"command"` |
| `command` | string | Yes | Shell command to execute |
| `timeout` | number | No | Timeout in seconds (default: 10) |
| `powershell` | string | No | PowerShell-specific command (Windows) |

## SDK Hook Registration

```typescript
const session = await client.createSession({
    hooks: {
        onPreToolUse: async (input) => {
            // input.toolName, input.toolArgs, input.sessionId
            if (BLOCKED_TOOLS.includes(input.toolName)) {
                return { permissionDecision: "deny", permissionDecisionReason: "Not permitted" };
            }
            return { permissionDecision: "allow" };
        },
        onPostToolUse: async (input) => {
            // input.toolName, input.toolResult, input.sessionId
            return null; // No transformation
        },
        onSessionStart: async (input) => {
            return { additionalContext: "User prefers concise answers." };
        },
        onUserPromptSubmitted: async (input) => {
            // input.prompt, input.sessionId
            return null; // No modification
        },
    },
});
```

## Real-World Example: Grafana Agent Observability

Hooks into ALL lifecycle events:

```json
{
  "hooks": {
    "sessionStart":        [{ "hooks": [{ "type": "command", "command": "agento11y copilot hook", "timeout": 10 }] }],
    "sessionEnd":          [{ "hooks": [{ "type": "command", "command": "agento11y copilot hook", "timeout": 10 }] }],
    "userPromptSubmitted": [{ "hooks": [{ "type": "command", "command": "agento11y copilot hook", "timeout": 10 }] }],
    "preToolUse":          [{ "hooks": [{ "type": "command", "command": "agento11y copilot hook", "timeout": 10 }] }],
    "postToolUse":         [{ "hooks": [{ "type": "command", "command": "agento11y copilot hook", "timeout": 10 }] }],
    "errorOccurred":       [{ "hooks": [{ "type": "command", "command": "agento11y copilot hook", "timeout": 10 }] }],
    "agentStop":           [{ "hooks": [{ "type": "command", "command": "agento11y copilot hook", "timeout": 30 }] }]
  }
}
```

## Real-World Example: build-perf-cpp

```json
{
  "version": 1,
  "hooks": {
    "sessionStart": [
      { "type": "command", "powershell": "./scripts/install-vcperf.ps1", "timeoutSec": 120 }
    ],
    "userPromptSubmitted": [
      { "type": "command", "powershell": "./scripts/write-correlation-id.ps1", "timeoutSec": 5 }
    ]
  }
}
```
