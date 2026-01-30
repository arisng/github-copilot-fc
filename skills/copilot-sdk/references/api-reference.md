# API Reference Guide

Detailed parameter descriptions, method signatures, and error codes for GitHub Copilot CLI SDKs.

## CopilotClient

### Constructor

**TypeScript/Python/Go/.NET all follow similar patterns**

#### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `cliPath` | string | auto-detect | Custom path to Copilot CLI binary |
| `logLevel` | string | "warning" | Logging level: "none", "error", "warning", "info", "debug", "all" |
| `autoStart` | boolean | true | Automatically start server on first use |
| `autoRestart` | boolean | true | Automatically restart on crash |
| `useStdio` | boolean | true | Use stdio transport (most reliable) |
| `port` | number | 0 | TCP port (0 = random); only used when useStdio is false |
| `cwd` | string | process.cwd() | Working directory for CLI process |
| `cliUrl` | string | - | Connect to external server (format: "host:port" or "http://host:port") |

### Methods

#### start()
Manually start the client (if autoStart is false).

**Signature:**
- TypeScript: `await client.start(): Promise<void>`
- Python: `await client.start(): None`
- Go: `func (c *Client) Start() error`
- .NET: `await client.StartAsync(): Task`

**Throws:** Error if CLI not found or connection fails

#### getState() / State
Get current connection state.

**Returns:** "disconnected" | "connecting" | "connected" | "error"

#### ping(message?)
Verify connectivity and measure latency.

**Returns:**
```typescript
{
    timestamp: number,
    protocolVersion: string,
    latency?: number
}
```

#### stop() / StopAsync()
Gracefully shutdown the client.

**Returns:** Promise<Error[]> (list of cleanup errors, if any)

#### forceStop() / ForceStopAsync()
Force shutdown (use if stop() hangs).

**Returns:** Promise<void>

#### createSession(config) / CreateSessionAsync(config)
Create a new conversation session.

**See:** Session creation parameters below

#### listSessions() / ListSessionsAsync()
List all active sessions.

**Returns:** Array of session summaries with id, summary, modifiedTime

#### getLastSessionId() / GetLastSessionIdAsync()
Get most recently used session ID (for resuming).

**Returns:** string | null

#### resumeSession(sessionId, options) / ResumeSessionAsync(...)
Re-open an existing session.

**Parameters:**
- `sessionId`: string (required)
- `options`: Partial SessionConfig (optional streaming, tools)

#### deleteSession(sessionId) / DeleteSessionAsync(sessionId)
Permanently delete a session.

**Throws:** Error if session not found

---

## Session Configuration

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `sessionId` | string | auto-generated | Custom session identifier (must be unique) |
| `model` | string | - | AI model to use: "gpt-5", "gpt-4.1", "claude-sonnet-4.5" |
| `streaming` | boolean | false | Enable streaming responses (assistant.message_delta events) |
| `availableTools` | string[] | all | Whitelist specific tools (if set, only these are available) |
| `excludedTools` | string[] | [] | Blacklist specific tools (removed from availability) |
| `systemMessage` | object | - | Custom system prompt: `{ mode: "append" \| "replace", content: string }` |
| `onPermissionRequest` | function | - | Permission handler: async (request, context) => PermissionResult |
| `tools` | Tool[] | [] | Array of custom tools |
| `mcpServers` | object | {} | MCP server configuration |
| `customAgents` | Agent[] | [] | Custom agents with specialized prompts |
| `provider` | object | - | Custom API provider (BYOK) |

### Error Codes

| Code | Message | Cause |
|------|---------|-------|
| `ERR_SESSION_NOT_FOUND` | Session does not exist | sessionId not found in client |
| `ERR_INVALID_MODEL` | Unknown model specified | Model not available in this SDK version |
| `ERR_TOOL_NOT_FOUND` | Tool not found | Tool name doesn't match registered tool |
| `ERR_MCP_SERVER_UNAVAILABLE` | MCP server unreachable | Server path/URL incorrect or server down |
| `ERR_PERMISSION_DENIED` | Operation not permitted | Permission handler returned deny |

---

## Session Methods

### sendAndWait(message, timeout?) / SendAndWaitAsync(...)
Send message and wait for completion.

**Parameters:**
- `message`: MessageOptions (prompt, attachments)
- `timeout`: number in ms (default: 60000)

**Returns:** MessageResponse | null (null if timeout)

**Message Structure:**
```typescript
{
    prompt: string,  // Required
    attachments?: [
        { type: "file" | "directory", path: string, displayName?: string }
    ],
    mode?: "immediate"  // Optional
}
```

### send(message) / SendAsync(message)
Send message asynchronously (non-blocking).

**Parameters:** MessageOptions (same as sendAndWait)

**Returns:** string (messageId)

### on(handler) / On(handler)
Subscribe to session events.

**Event Types:**
```typescript
"user.message" | "assistant.message" | "assistant.message_delta" | 
"assistant.reasoning" | "assistant.reasoning_delta" | 
"tool.execution_start" | "tool.execution_end" | 
"session.idle" | "session.error"
```

**Handler Signature:**
```typescript
(event: SessionEvent) => void
```

### getMessages() / GetMessagesAsync()
Get conversation history.

**Returns:** Array of all events (user messages, assistant responses, tool calls)

### abort() / AbortAsync()
Cancel long-running request.

**Returns:** Promise<void>

### destroy() / DestroyAsync()
Release resources (doesn't delete session data).

**Returns:** Promise<void>

---

## Permission Handler

### PermissionRequest Object

```typescript
{
    kind: "shell" | "write" | "read" | "url" | "mcp",
    path?: string,      // For "write" and "read"
    url?: string,       // For "url"
    command?: string    // For "shell"
}
```

### PermissionResult

```typescript
{
    kind: "approved" | "denied-by-rules" | "denied-interactively-by-user" | 
           "denied-no-approval-rule-and-could-not-request-from-user",
    rules?: Array<{ reason: string }>
}
```

---

## Custom Tools

### Tool Schema (Raw Pattern)

```typescript
{
    name: string,
    description: string,
    parameters: {
        type: "object",
        properties: { [key: string]: JSONSchema },
        required?: string[]
    },
    handler: async (args, invocation?) => ToolResult
}
```

### ToolResult Structure

```typescript
{
    textResultForLlm: string,           // Required: Human-readable result
    resultType: "success" | "failure",  // Required
    sessionLog?: string,                // Optional: Diagnostic info
    toolTelemetry?: object,             // Optional: Structured data
    error?: string                      // Optional: Error message if failure
}
```

---

## MCP Server Configuration

### Local (Stdio) Server

```typescript
{
    type: "local" | "stdio",
    command: string,           // Executable name or path
    args: string[],            // Command arguments
    tools: "*" | string[],     // "*" for all tools or specific list
    timeout?: number,          // Milliseconds (default: 30000)
    env?: object,              // Environment variables
    cwd?: string               // Working directory
}
```

### HTTP Server

```typescript
{
    type: "http",
    url: string,                    // Full URL to MCP endpoint
    tools: "*" | string[],          // Tool filter
    headers?: object,               // Custom headers (e.g., Authorization)
    timeout?: number                // Milliseconds
}
```

### SSE Server

```typescript
{
    type: "sse",
    url: string,                    // SSE endpoint URL
    tools: "*" | string[]
}
```

---

## Custom Provider Configuration

### Provider Object

```typescript
{
    type: "openai" | "azure" | "anthropic" | string,
    baseUrl: string,                // API base URL
    apiKey?: string,                // API key
    bearerToken?: string,           // Alternative to apiKey
    wireApi?: "completions" | "responses",  // OpenAI wire format
    azure?: {
        apiVersion: string          // Azure API version
    }
}
```
