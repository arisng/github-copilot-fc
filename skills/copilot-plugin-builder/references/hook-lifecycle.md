# Hook Lifecycle Reference

Grounded in the [GitHub Copilot hooks reference](https://docs.github.com/en/copilot/reference/hooks-reference) and the [Agent plugin authoring reference](https://code.visualstudio.com/docs/agents/reference/agent-plugin-reference).

## Hook File Locations (Plugin Formats)

| Plugin format | Hook file path |
|---------------|----------------|
| Agent Plugins 1.0 | `com.github.copilot/hooks/hooks.json` |
| Legacy Copilot | `hooks.json` at the plugin root |
| Claude | `hooks/hooks.json` |

Hooks are client-specific — not a portable Agent Plugins 1.0 component. Plugin hooks run alongside user, repository, and policy hooks.

## All 14 Hook Events

| Event | Fires when | Output processed |
|-------|------------|------------------|
| `agentStop` | Main agent finishes a turn | Yes — can block and force continuation |
| `errorOccurred` | Error occurs during execution | No |
| `notification` | CLI emits a system notification (shell/agent completion, permission prompts, elicitation dialogs); fire-and-forget; `matcher` filters `notification_type` | Optional — inject `additionalContext` |
| `permissionRequest` | Before the permission service runs (rules engine, approvals, auto-allow/deny, prompting); `matcher` filters `toolName` | Yes — `allow`/`deny` short-circuits the normal permission flow |
| `postToolUse` | After each tool completes successfully | Yes — modify the tool result or inject context |
| `postToolUseFailure` | After a tool completes with a failure | Yes — recovery guidance via `additionalContext` |
| `preCompact` | Context compaction is about to begin; `matcher` filters `manual`/`auto` | No — notification only |
| `preToolUse` | Before each tool executes | Yes — allow, deny, or modify |
| `sessionEnd` | Session terminates | No |
| `sessionStart` | New or resumed session begins | Optional — inject `additionalContext` |
| `subagentStart` | Subagent is spawned; `matcher` filters by agent name | Optional — prepend to the subagent's prompt |
| `subagentStop` | Subagent completes | Yes — can block and force continuation |
| `userPromptSubmitted` | User submits a prompt | Optional — `modifiedPrompt` honored only by SDK programmatic hooks |
| `userPromptTransformed` | After the runtime transforms a submitted prompt into model-facing content | Yes — rewrite the model-facing content |

Event names accept runtime camelCase (`postToolUse`) and aliases (`PostToolUse`). Payload fields are camelCase for camelCase event names, and snake_case for PascalCase (VS Code-compatible) event names.

## hooks.json Format

```json
{
  "version": 1,
  "hooks": {
    "sessionStart": [
      { "command": "echo 'Session started'", "timeoutSec": 10 }
    ],
    "preToolUse": [
      { "command": "./scripts/validate-tool.sh", "timeoutSec": 5 }
    ]
  }
}
```

## Command Hook Entry Properties

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `type` | `"command"` | No | Defaults to `"command"` when omitted |
| `command` | string | One of `bash`/`powershell`/`command`, unless `exec` | Cross-platform fallback; copied to both platform fields |
| `bash` | string | One of `bash`/`powershell`/`command`, unless `exec` | Shell command for Unix |
| `powershell` | string | One of `bash`/`powershell`/`command`, unless `exec` | Shell command for Windows |
| `exec` | string | Instead of the shell fields | Executable run directly without a shell (CLI only) |
| `args` | string[] | No | Arguments for `exec`, no shell interpretation (CLI only) |
| `cwd` | string | No | Working directory (relative to repo root or absolute) |
| `env` | object | No | Environment variables (supports variable expansion) |
| `matcher` | string | No | Regex filter (event-specific subject) |
| `timeoutSec` | number | No | Timeout in seconds (default: `30`) |
| `timeout` | number | No | Alias for `timeoutSec`; `timeoutSec` wins when both are present |

HTTP hooks (`type: "http"`) post the payload to a `url` with optional `headers`/`allowedEnvVars` instead of running a command.

Command hooks can emit progress lines by writing a single-line `{"type": "progress", "message": "..."}` JSON object to stdout before the final decision object.

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

Hooks into multiple lifecycle events:

```json
{
  "hooks": {
    "sessionStart":        [{ "hooks": [{ "type": "command", "command": "agento11y copilot hook", "timeoutSec": 10 }] }],
    "sessionEnd":          [{ "hooks": [{ "type": "command", "command": "agento11y copilot hook", "timeoutSec": 10 }] }],
    "userPromptSubmitted": [{ "hooks": [{ "type": "command", "command": "agento11y copilot hook", "timeoutSec": 10 }] }],
    "preToolUse":          [{ "hooks": [{ "type": "command", "command": "agento11y copilot hook", "timeoutSec": 10 }] }],
    "postToolUse":         [{ "hooks": [{ "type": "command", "command": "agento11y copilot hook", "timeoutSec": 10 }] }],
    "errorOccurred":       [{ "hooks": [{ "type": "command", "command": "agento11y copilot hook", "timeoutSec": 10 }] }],
    "agentStop":           [{ "hooks": [{ "type": "command", "command": "agento11y copilot hook", "timeoutSec": 30 }] }]
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
