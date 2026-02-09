# API Reference Guide

Detailed parameter descriptions, method signatures, and error codes for GitHub Copilot CLI SDK (.NET).

## CopilotClient

### Constructor

#### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `CliPath` | string | auto-detect | Custom path to Copilot CLI binary |
| `LogLevel` | string | "warning" | Logging level: "none", "error", "warning", "info", "debug", "all" |
| `AutoStart` | boolean | true | Automatically start server on first use |
| `AutoRestart` | boolean | true | Automatically restart on crash |
| `UseStdio` | boolean | true | Use stdio transport (most reliable) |
| `Port` | number | 0 | TCP port (0 = random); only used when useStdio is false |
| `Cwd` | string | process.cwd() | Working directory for CLI process |
| `CliUrl` | string | - | Connect to external server (format: "host:port" or "http://host:port") |

### Methods

#### StartAsync()
Manually start the client (if AutoStart is false).

**Signature:** `await client.StartAsync(): Task`

**Throws:** Exception if CLI not found or connection fails

#### State
Get current connection state.

**Returns:** "disconnected" | "connecting" | "connected" | "error"

#### PingAsync(message?)
Verify connectivity and measure latency.

**Returns:** `Task<PingResponse>`

#### StopAsync()
Gracefully shutdown the client.

**Returns:** `Task<IEnumerable<Exception>>` (list of cleanup errors, if any)

#### ForceStopAsync()
Force shutdown (use if StopAsync() hangs).

**Returns:** `Task`

#### CreateSessionAsync(config)
Create a new conversation session.

**See:** Session creation parameters below

#### ListSessionsAsync()
List all active sessions.

**Returns:** `Task<IEnumerable<SessionInfo>>`

#### GetLastSessionIdAsync()
Get most recently used session ID (for resuming).

**Returns:** `Task<string?>`

#### ResumeSessionAsync(sessionId, options)
Re-open an existing session.

**Parameters:**
- `sessionId`: string (required)
- `options`: Partial SessionConfig (optional streaming, tools)

#### DeleteSessionAsync(sessionId)
Permanently delete a session.

**Throws:** Exception if session not found

---

## Session Configuration

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `SessionId` | string | auto-generated | Custom session identifier (must be unique) |
| `Model` | string | - | AI model to use: "gpt-5", "gpt-4.1", "claude-sonnet-4.5" |
| `Streaming` | boolean | false | Enable streaming responses (assistant.message_delta events) |
| `AvailableTools` | string[] | all | Whitelist specific tools (if set, only these are available) |
| `ExcludedTools` | string[] | [] | Blacklist specific tools (removed from availability) |
| `SystemMessage` | object | - | Custom system prompt: `{ Mode: "append" \| "replace", Content: string }` |
| `OnPermissionRequest` | func | - | Permission handler: `async (request, context) => PermissionResult` |
| `Tools` | Tool[] | [] | Array of custom tools |
| `McpServers` | object | {} | MCP server configuration (Dictionary) |
| `CustomAgents` | Agent[] | [] | Custom agents with specialized prompts |
| `Provider` | object | - | Custom API provider (BYOK) |

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

### SendAndWaitAsync(message, timeout?)
Send message and wait for completion.

**Parameters:**
- `message`: MessageOptions (prompt, attachments)
- `timeout`: TimeSpan (default: 60s)

**Returns:** `Task<MessageResponse?>`

**Message Structure:**
```csharp
new MessageOptions {
    Prompt = "...",
    Attachments = [...],
    Mode = MessageMode.Immediate // or Enqueue
}
```

### SendAsync(message)
Send message asynchronously (non-blocking).

**Parameters:** MessageOptions (same as SendAndWaitAsync)

**Returns:** `Task<string>` (messageId)

### Events.Subscribe(handler)
Subscribe to session events (IObservable).

**Event Types:**
- `UserMessageEvent`
- `AssistantMessageEvent`
- `AssistantMessageDeltaEvent`
- `ToolExecutionStartEvent` / `ToolExecutionEndEvent`
- `SessionIdleEvent` / `SessionErrorEvent`

### GetMessagesAsync()
Get conversation history.

**Returns:** `Task<IEnumerable<SessionEvent>>`

### AbortAsync()
Cancel long-running request.

**Returns:** `Task`

### DestroyAsync()
Release resources (doesn't delete session data).

**Returns:** `Task`

---

## Permission Handler

### PermissionRequest Object

```csharp
public class PermissionRequest {
    public string Kind { get; } // "shell", "write", "read", "url", "mcp"
    public Dictionary<string, object> Properties { get; }
    // Properties["path"], Properties["url"], Properties["command"]
}
```

### PermissionResult

```csharp
public class PermissionResult {
    public string Kind { get; set; } // "approved", "denied-by-rules", ...
    public string Message { get; set; }
}
```

---

## Custom Tools

### Tool Result Structure

```csharp
public class ToolResult {
    public string TextResultForLlm { get; set; } // Required
    public string ResultType { get; set; } // "success" | "failure"
    public string SessionLog { get; set; } 
    public object ToolTelemetry { get; set; }
    public string Error { get; set; }
}
```

---

## MCP Server Configuration

### Local (Stdio) Server

```csharp
new McpLocalServerConfig {
    Type = "local", // or "stdio"
    Command = "npx",
    Args = ["..."],
    Tools = "*", // or ["tool1"]
    Timeout = TimeSpan.FromSeconds(30),
    Env = new Dictionary<string, string> { ... },
    Cwd = "..."
}
```

### HTTP Server

```csharp
new McpRemoteServerConfig {
    Type = "http",
    Url = "https://...",
    Tools = "*",
    Headers = new Dictionary<string, string> { ... }
}
```

### SSE Server

```csharp
new McpRemoteServerConfig {
    Type = "sse",
    Url = "https://...",
    Tools = "*"
}
```

---

## Custom Provider Configuration

### Provider Object

```csharp
new ProviderConfig {
    Type = "openai", // or "azure", "anthropic"
    BaseUrl = "https://...",
    ApiKey = "...",
    Azure = new AzureProviderConfig { ApiVersion = "..." }
}
```
