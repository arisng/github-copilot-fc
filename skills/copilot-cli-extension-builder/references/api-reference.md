# Copilot CLI Extension API Reference

## joinSession() — Single Entry Point

```javascript
import { joinSession } from "@github/copilot-sdk/extension";

const session = await joinSession({
    // Tools the agent can call
    tools?: Tool<any>[];
    // Lifecycle hooks
    hooks?: SessionHooks;
    // Slash commands (for users)
    commands?: CommandDefinition[];
    // Canvas declarations (side-panel UIs)
    canvases?: Canvas[];
    // Extension identity for canvas provider
    extensionInfo?: ExtensionInfo;
    // Enable canvas rendering (adds 3 canvas tools to agent)
    requestCanvasRenderer?: boolean;
    // Enable extension management tools
    requestExtensions?: boolean;
    // Model configuration
    model?: string;
    reasoningEffort?: "low" | "medium" | "high";
});
// Returns: CopilotSession
```

## Tool Interface

```javascript
{
    name: string,                               // Required. Globally unique across ALL extensions
    description?: string,                       // What it does; agent decides when to call
    parameters?: Record<string, unknown>,       // JSON Schema for arguments
    handler?: (args, invocation) => Promise<unknown> | unknown,
    skipPermission?: boolean,                   // true = no approval prompt
    defer?: "auto" | "never",                   // "never" = always pre-loaded; "auto" = lazy-load
    overridesBuiltInTool?: boolean,             // Replace a built-in tool of same name
    metadata?: Record<string, unknown>,
}
```

### Handler Signature

```javascript
async function handler(args, invocation) {
    // args — the argument object matching the JSON Schema
    // invocation — { sessionId, toolCallId, toolName, arguments, traceparent?, tracestate? }
    return "string result";  // Plain string = success
    // OR
    return {
        textResultForLlm: "string",
        resultType: "success" | "failure" | "rejected" | "denied" | "timeout",
        error?: string,
    };
}
```

### Properties Reference

| Property | Values | Effect |
|---|---|---|
| `defer` | `"never"` | Tool always visible in agent's tool list |
| `defer` | `"auto"` | Tool may be lazy-loaded via tool search (default) |
| `skipPermission` | `true` | No approval prompt on each invocation |
| `skipPermission` | `false` | Agent asks user for approval (default) |
| `overridesBuiltInTool` | `true` | Replaces a built-in tool with same `name` |

## CommandDefinition Interface

```javascript
{
    name: string,                    // Command name without leading /
    description?: string,            // Shown in command completion picker
    handler: async (ctx) => void,    // ctx.args = text after command name
}

// ctx properties:
//   ctx.sessionId     - Session ID where invoked
//   ctx.command       - Full command text (e.g., "/deploy production")
//   ctx.commandName   - Name without leading /
//   ctx.args          - Raw argument string after command name
```

## CopilotSession API

### Logging

```javascript
await session.log("message", { level: "info" | "warning" | "error" });
await session.log("transient", { ephemeral: true });  // Not persisted
```

### Sending Prompts to the Agent

```javascript
await session.send("prompt text");
await session.send({
    prompt: "prompt text",
    displayPrompt: "visible text",   // Optional: different text shown to user
    attachments: [...],
});
await session.sendAndWait("prompt", 60000);  // Returns on completion or timeout
```

### Session Events

Subscribe to events with `session.on(eventType, handler)`. Returns unsubscribe function.

```javascript
const unsub = session.on("tool.execution_start", (event) => {
    const { toolName, toolCallId, arguments } = event.data;
});

// Later: unsub();  // Cleanup
```

| Event Type | Key `data` Fields | Description |
|---|---|---|
| `assistant.message` | `content, citations?` | Agent's final response |
| `assistant.message_delta` | `deltaContent` | Streaming content chunk |
| `assistant.turn_start` | `turnId` | Agent begins response cycle |
| `assistant.usage` | `inputTokens, outputTokens, cacheReadTokens?, cacheWriteTokens?, model, duration?` | Token usage after turn |
| `tool.execution_start` | `toolCallId, toolName, arguments?, model?` | Tool about to run |
| `tool.execution_complete` | `toolCallId, toolName, success?, result?, error?` | Tool finished |
| `user.message` | `content, attachments?, source?` | User sent message |
| `session.idle` | `backgroundTasks` | Turn finished |
| `session.error` | `errorType, message` | Error occurred |
| `session.shutdown` | `shutdownType, totalPremiumRequests` | Session ending |

## Hooks API (SessionHooks)

All hooks receive `{ timestamp, workingDirectory }` plus type-specific fields.

```javascript
const session = await joinSession({
    hooks: {
        onUserPromptSubmitted: async (input) => {
            // input: { prompt, timestamp, workingDirectory }
            return { modifiedPrompt, additionalContext };  // Optional modifications
        },
        onPreToolUse: async (input) => {
            // input: { toolName, toolArgs, timestamp, workingDirectory }
            return { permissionDecision: "allow" | "deny" | "ask", modifiedArgs, additionalContext };
        },
        onPostToolUse: async (input) => {
            // input: { toolName, toolArgs, toolResult, timestamp, workingDirectory }
            return { modifiedResult, additionalContext };
        },
        onPostToolUseFailure: async (input) => {
            // input: { toolName, toolArgs, error, timestamp, workingDirectory }
            return { additionalContext };
        },
        onSessionStart: async (input) => {
            // input: { source: "startup"|"resume"|"new", timestamp, workingDirectory }
            return { additionalContext };
        },
        onSessionEnd: async (input) => {
            // input: { reason, finalMessage?, error?, timestamp, workingDirectory }
            return { sessionSummary, cleanupActions };
        },
        onErrorOccurred: async (input) => {
            // input: { error, errorContext, recoverable, timestamp, workingDirectory }
            return { errorHandling: "retry"|"skip"|"abort", retryCount, userNotification };
        },
    },
});
```

## Canvas API (createCanvas)

### CanvasOptions

```javascript
import { createCanvas, CanvasError } from "@github/copilot-sdk/extension";

const canvas = createCanvas({
    id: "my-canvas",                     // Unique within this extension
    displayName: "My Canvas",            // Human-readable label
    description: "...",                  // Agent-facing description
    inputSchema?: {                      // JSON Schema for open input
        type: "object",
        properties: { ... },
    },
    actions?: [{                         // Agent-invocable actions
        name: "action_name",             // MUST NOT start with "canvas."
        description?: string,
        inputSchema?: { ... },           // JSON Schema
        handler: async (ctx) => {
            // ctx: { sessionId, extensionId, canvasId, instanceId, actionName, input, host }
            return { ... };
        },
    }],
    open: async (ctx) => {
        // **Must be idempotent** — same instanceId may arrive after provider reconnect
        return {
            url: "http://127.0.0.1:<port>/",   // Loopback URL for iframe
            title?: "Panel Title",
            status?: "ready",
        };
    },
    onClose?: async (ctx) => {
        // Fire-and-forget cleanup; return value ignored
    },
});
```

### Canvas Types

```javascript
// CanvasError
class CanvasError extends Error {
    constructor(public readonly code: string, message: string);
    static noHandler(): CanvasError;  // "canvas_action_no_handler"
}

// json-schema — any valid JSON Schema object
type CanvasJsonSchema = Record<string, unknown>;
```

### Agent-Side Canvas Tools

These 3 tools appear to the agent when `requestCanvasRenderer: true`:

| Tool | Parameters | Description |
|---|---|---|
| `list_canvas_capabilities` | `extensionId?`, `canvasId` | Discover available canvases and action schemas |
| `open_canvas` | `extensionId?`, `canvasId`, `instanceId`, `input?` | Open/focus a canvas instance |
| `invoke_canvas_action` | `instanceId`, `actionName`, `input` | Invoke a named action on an open instance |

## Extension Management Tools

The agent can manage extensions with `extensions_manage`:

| Operation | Purpose | Example |
|---|---|---|
| `scaffold` | Generate starter extension.mjs | `{ operation: "scaffold", name: "my-ext", kind: "canvas", location: "project" }` |
| `list` | List discovered extensions with status | `{ operation: "list" }` |
| `inspect` | Inspect extension (log path + tail) | `{ operation: "inspect", name: "my-ext" }` |

## Extension Identity

```javascript
{
    source: string,    // Extension namespace (e.g., "github-app", "user", "project")
    name: string,      // Stable provider name within the source
}
```

The runtime auto-derives `extensionId` as `${source}:${name}` (e.g., `project:my-extension`, `user:tool-time`).

## Constraints

| Rule | Reason |
|---|---|
| Only `.mjs` supported | TypeScript (`.ts`) not accepted |
| `console.log()` breaks JSON-RPC | Use `session.log()` instead |
| Tool names must be globally unique | Duplicate names cause load failure |
| Canvas action names can't start with `canvas.` | Reserved for lifecycle verbs |
| `open()` must be idempotent | Same instanceId may re-open after reconnect |
| Bind HTTP servers to `127.0.0.1` only | Host only embeds loopback URLs |
| Don't call `session.send()` synchronously from `onUserPromptSubmitted` | Use `setTimeout(() => ..., 0)` to avoid infinite loops |
