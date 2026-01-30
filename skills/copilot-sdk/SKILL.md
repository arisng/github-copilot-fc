---
name: copilot-sdk
description: Build applications with GitHub Copilot CLI SDKs across Node.js/TypeScript, Python, Go, and .NET. Use when integrating AI assistance into applications via CopilotClient, managing sessions, streaming responses, custom tools, MCP servers, permission handling, and custom agents. Covers SDK installation, client lifecycle, session management, message handling, tool execution, and advanced integration patterns.
version: 1.0.0
---

# GitHub Copilot CLI SDKs

Use this skill to guide SDK integration, select appropriate APIs, and provide language-specific code examples. Focus on practical implementation patterns for the four supported languages: Node.js/TypeScript, Python, Go, and .NET.

## Quick workflow

1. Identify the user's goal (client creation, session management, streaming, custom tools, permissions, MCP integration, or custom agents).
2. Determine the target language and whether the user needs basic or advanced setup.
3. Select the matching API section and code pattern.
4. Provide language-specific examples with clear context (imports, initialization, event handling).
5. Call out important defaults and configuration options that affect behavior.
6. Mention technical preview status and potential breaking changes across SDK versions.

## SDK selection and installation

- **Node.js/TypeScript**: `npm install @github/copilot-sdk` (uses Zod for type-safe schemas)
- **Python**: `pip install github-copilot-sdk` (uses Pydantic for type-safe schemas)
- **Go**: `go get github.com/github/copilot-sdk/go` (uses struct tags and DefineTool)
- **.NET**: `dotnet add package GitHub.Copilot.SDK` (uses AIFunctionFactory and attributes)

All SDKs communicate via JSON-RPC over stdio (default) or TCP transports.

## Core concepts

- **CopilotClient**: Main entry point managing server lifecycle, connections, and session creation. Can spawn CLI server automatically or connect to external server.
- **Sessions**: Represent individual conversations with persistent state, event handlers, and tool registrations. Each session has a sessionId, model, and optional streaming/tools configuration.
- **Tools**: Custom functions the assistant can invoke. Support type-safe schemas via language-specific mechanisms (Zod, Pydantic, struct tags, AIFunctionFactory).
- **MCP Servers**: External tool servers (local stdio, HTTP, or SSE) extending assistant capabilities.
- **Custom Agents**: Specialized personas with scoped prompts, tool access, and configurations.
- **Streaming**: Real-time response delivery via event handlers (e.g., `assistant.message_delta` for chunks).

## Client creation patterns

### Default client (auto-spawns CLI server)

- **TypeScript**: `const client = new CopilotClient();`
- **Python**: `client = CopilotClient()`
- **Go**: `client := copilot.NewClient(nil)`
- **.NET**: `await using var client = new CopilotClient();`

### Client with options

Common options (all languages):
- `cliPath`: Custom CLI binary path (default: auto-detect)
- `logLevel`: "none", "error", "warning", "info", "debug", "all"
- `autoStart`: Auto-spawn server on first use (default: true)
- `autoRestart`: Auto-restart on crash (default: true)
- `useStdio`: Use stdio transport (default: true)
- `port`: TCP port (0 = random, only when useStdio is false)
- `cwd`: Working directory for CLI process

### External server connection

Use `cliUrl` (TypeScript/Python) or `CliUrl` (.NET) to connect to existing server:
- `"localhost:8080"`, `"http://127.0.0.1:9000"`, or just `"8080"`

### Lifecycle management

- `await client.start()` or `await client.StartAsync()` (manual start if autoStart is false)
- `client.getState()` or `client.State` (returns "disconnected", "connecting", "connected", "error")
- `await client.ping()` (verify connectivity)
- `await client.stop()` or `await client.StopAsync()` (graceful shutdown)
- `await client.forceStop()` (force stop if graceful shutdown hangs)

## Session creation and management

### Basic session

```typescript
const session = await client.createSession({ model: "gpt-5" });
```

### Session with full configuration

Common options (all languages):
- `sessionId`: Custom session identifier (optional)
- `model`: Model to use (e.g., "gpt-5", "claude-sonnet-4.5")
- `streaming`: Enable streaming responses (default: false)
- `availableTools`: Whitelist specific tools
- `excludedTools`: Blacklist specific tools
- `systemMessage`: Custom system prompt with mode ("append" or "replace")
- `onPermissionRequest`: Permission handler function (TypeScript/Python)

### Session queries

- `await client.listSessions()` (all sessions)
- `await client.getLastSessionId()` (for resuming)
- `await client.resumeSession(sessionId, options)` (re-open existing)
- `await client.deleteSession(sessionId)` (permanent delete)
- `await session.destroy()` (release resources, don't delete)

## Message handling and events

### Event subscription pattern

Subscribe before sending messages. All languages support `session.on(handler)`:
```typescript
session.on((event) => {
    switch (event.type) {
        case "user.message": // User's input
        case "assistant.message": // Complete response
        case "assistant.message_delta": // Streaming chunk
        case "assistant.reasoning": // Internal reasoning (complete)
        case "assistant.reasoning_delta": // Reasoning chunk
        case "tool.execution_start": // Tool invoked
        case "tool.execution_end": // Tool completed
        case "session.idle": // No activity
        case "session.error": // Error occurred
    }
});
```

### Send patterns

**Synchronous (wait for completion)**:
```typescript
const response = await session.sendAndWait({
    prompt: "Your question",
    attachments: [/* optional files/dirs */]
}, 60000); // Optional timeout in ms
```

**Asynchronous (non-blocking, event-driven)**:
```typescript
const messageId = await session.send({
    prompt: "Long task",
    mode: "enqueue" // or "immediate"
});
```

### File attachments

Support two types:
```typescript
attachments: [
    { type: "file", path: "/path/to/file", displayName: "File" },
    { type: "directory", path: "/path/to/dir", displayName: "Folder" }
]
```

### Conversation history

```typescript
const history = await session.getMessages();
```

### Abort long-running requests

```typescript
await session.abort();
```

## Custom tools (type-safe)

### TypeScript (Zod)

```typescript
import { z } from "zod";
import { defineTool } from "@github/copilot-sdk";

const myTool = defineTool("tool_name", {
    description: "What this tool does",
    parameters: z.object({
        param1: z.string().describe("Parameter description"),
        param2: z.boolean().optional()
    }),
    handler: async ({ param1, param2 }) => {
        // Implementation
        return { result: "..." };
    }
});

const session = await client.createSession({ tools: [myTool] });
```

### Python (Pydantic)

```python
from pydantic import BaseModel, Field
from copilot import define_tool

class MyToolParams(BaseModel):
    param1: str = Field(description="...")
    param2: bool = Field(default=False)

@define_tool(description="What this tool does")
async def my_tool(params: MyToolParams) -> str:
    # Implementation
    return f"Result: {params.param1}"

session = await client.create_session({"tools": [my_tool]})
```

### Go (DefineTool)

```go
type MyToolParams struct {
    Param1 string `json:"param1" jsonschema:"..."`
    Param2 bool   `json:"param2"`
}

myTool := copilot.DefineTool("tool_name", "Description",
    func(params MyToolParams, inv copilot.ToolInvocation) (any, error) {
        // Implementation
        return map[string]interface{}{"result": "..."}, nil
    })

session, _ := client.CreateSession(&copilot.SessionConfig{
    Tools: []copilot.Tool{myTool},
})
```

### .NET (AIFunctionFactory)

```csharp
using Microsoft.Extensions.AI;
using System.ComponentModel;

var myTool = AIFunctionFactory.Create(
    async ([Description("...")] string param1) => {
        // Implementation
        return new { result = "..." };
    },
    "tool_name",
    "What this tool does"
);

var session = await client.CreateSessionAsync(new SessionConfig {
    Tools = new[] { myTool }
});
```

### Tool result structure (raw schema pattern)

All languages support returning rich structured results:
```typescript
{
    textResultForLlm: "Human-readable text for model",
    resultType: "success" | "failure",
    sessionLog: "Internal diagnostic message",
    toolTelemetry: { /* structured data */ },
    error?: "Error message if failure"
}
```

## Permission handling

Register a permission handler to approve/deny sensitive operations. Available kinds: "shell", "write", "read", "url", "mcp".

### TypeScript pattern

```typescript
const session = await client.createSession({
    onPermissionRequest: async (request, context) => {
        switch (request.kind) {
            case "write":
                const path = request.path;
                if (path.startsWith("/safe/")) {
                    return { kind: "approved" };
                }
                return { kind: "denied-by-rules", rules: [{reason: "..."}] };
            case "shell":
                return { kind: "denied-interactively-by-user" };
            case "read":
                return { kind: "approved" };
            default:
                return { kind: "denied-no-approval-rule-and-could-not-request-from-user" };
        }
    }
});
```

### Result kinds

- `"approved"`: Allow the operation
- `"denied-by-rules"`: Deny with rule explanation
- `"denied-interactively-by-user"`: User denied
- `"denied-no-approval-rule-and-could-not-request-from-user"`: No rule and no user interaction

## Custom provider configuration (BYOK)

Use your own API keys with OpenAI, Azure OpenAI, Anthropic, or compatible providers.

### TypeScript pattern

```typescript
// OpenAI
const openaiSession = await client.createSession({
    provider: {
        type: "openai",
        baseUrl: "https://api.openai.com/v1",
        apiKey: process.env.OPENAI_API_KEY,
        wireApi: "completions" // or "responses"
    }
});

// Azure OpenAI
const azureSession = await client.createSession({
    provider: {
        type: "azure",
        baseUrl: "https://your-resource.openai.azure.com",
        apiKey: process.env.AZURE_OPENAI_KEY,
        azure: { apiVersion: "2024-10-21" }
    }
});

// Anthropic
const anthropicSession = await client.createSession({
    provider: {
        type: "anthropic",
        baseUrl: "https://api.anthropic.com",
        apiKey: process.env.ANTHROPIC_API_KEY
    }
});

// Local (Ollama, no key needed)
const localSession = await client.createSession({
    provider: { type: "openai", baseUrl: "http://localhost:11434/v1" }
});

// Bearer token instead of API key
const bearerSession = await client.createSession({
    provider: {
        type: "openai",
        baseUrl: "https://custom-api.example.com/v1",
        bearerToken: process.env.BEARER_TOKEN
    }
});
```

### .NET pattern

```csharp
var session = await client.CreateSessionAsync(new SessionConfig {
    Provider = new ProviderConfig {
        Type = "azure",
        BaseUrl = "https://your-resource.openai.azure.com",
        ApiKey = Environment.GetEnvironmentVariable("AZURE_OPENAI_KEY"),
        Azure = new AzureProviderConfig { ApiVersion = "2024-10-21" }
    }
});
```

## MCP Server integration

Connect local (stdio) or remote (HTTP/SSE) MCP servers to extend capabilities. Servers expose tools that the assistant can invoke.

### TypeScript pattern

```typescript
const session = await client.createSession({
    mcpServers: {
        "filesystem": {
            type: "local",  // or "stdio"
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/allowed"],
            tools: "*",  // All tools, or ["read_file", "write_file"]
            timeout: 30000,
            env: { "CUSTOM_VAR": "value" },
            cwd: "/working/directory"
        },
        "remote-api": {
            type: "http",
            url: "https://mcp-server.example.com/mcp",
            tools: ["search", "query"],
            headers: { "Authorization": "Bearer token" }
        },
        "streaming-server": {
            type: "sse",
            url: "https://sse-mcp.example.com/events",
            tools: "*"
        }
    }
});

await session.sendAndWait({
    prompt: "List files in the allowed directory"
});
```

### Python pattern

```python
session = await client.create_session({
    "mcp_servers": {
        "filesystem": {
            "type": "local",
            "command": "npx",
            "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path"],
            "tools": "*"
        },
        "remote-api": {
            "type": "http",
            "url": "https://mcp-server.example.com/mcp",
            "tools": ["search"],
            "headers": {"Authorization": "Bearer token"}
        }
    }
})
```

## Custom agents

Define specialized personas with scoped system prompts, tool access, and agent-specific MCP servers. Invoke agents with `@agent-name`.

### TypeScript pattern

```typescript
const session = await client.createSession({
    customAgents: [
        {
            name: "security-reviewer",
            displayName: "Security Reviewer",
            description: "Reviews code for vulnerabilities",
            prompt: `You are a security expert. Identify and fix vulnerabilities following OWASP.`,
            tools: ["Read", "Grep", "Glob"],
            infer: true
        },
        {
            name: "doc-writer",
            displayName: "Documentation Writer",
            description: "Writes documentation",
            prompt: `Create clear, concise documentation.`,
            tools: ["Read", "Write", "Glob"],
            mcpServers: {
                "markdown-tools": {
                    type: "local",
                    command: "markdown-mcp-server",
                    args: [],
                    tools: "*"
                }
            }
        }
    ]
});

// Use agent with mention
await session.sendAndWait({
    prompt: "@security-reviewer Review src/auth.ts for vulnerabilities"
});
```

### Python pattern

```python
session = await client.create_session({
    "custom_agents": [
        {
            "name": "security-reviewer",
            "display_name": "Security Reviewer",
            "description": "Reviews code for vulnerabilities",
            "prompt": "You are a security expert...",
            "tools": ["Read", "Grep", "Glob"],
            "infer": True
        }
    ]
})

await session.send({
    "prompt": "@security-reviewer Review src/auth.py"
})
```

## Common patterns and best practices

### Pattern 1: Simple request-response

```typescript
const client = new CopilotClient();
await client.start();
const session = await client.createSession({ model: "gpt-5" });
const response = await session.sendAndWait({ prompt: "Your question" });
console.log(response?.data.content);
await session.destroy();
await client.stop();
```

### Pattern 2: Streaming with events

```typescript
const session = await client.createSession({ 
    model: "gpt-5", 
    streaming: true 
});
session.on((event) => {
    if (event.type === "assistant.message_delta") {
        process.stdout.write(event.data.deltaContent);
    }
});
await session.sendAndWait({ prompt: "Write a story" });
```

### Pattern 3: Tool invocation with events

```typescript
const session = await client.createSession({ 
    tools: [myTool] 
});
session.on((event) => {
    if (event.type === "tool.execution_start") {
        console.log(`Tool ${event.data.toolName} started`);
    }
});
await session.sendAndWait({ prompt: "Use the tool" });
```

### Pattern 4: File attachments

```typescript
await session.sendAndWait({
    prompt: "Analyze this code",
    attachments: [
        { type: "file", path: "./src/main.ts", displayName: "Main" },
        { type: "directory", path: "./src", displayName: "Source" }
    ]
});
```

### Pattern 5: Multi-language BYOK setup

Choose the provider once during session creation; all messages use that provider.

## Glossary of GitHub Copilot Products

The GitHub Copilot ecosystem comprises multiple distinct products, each serving different use cases and contexts. Understanding the boundaries between them is essential for choosing the right tool and understanding SDK capabilities.

| Product                      | Alias           | Description                                                                                                                                                                                              | Execution Context                            | Primary Interface                                                        | Key Use Cases                                                                                                         |
| ---------------------------- | --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------- | ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------- |
| **Copilot in VS Code**       | Copilot VS Code | GitHub Copilot integrated into Visual Studio Code IDE. Provides chat, inline suggestions, and agent mode for autonomous edits in local development environment.                                          | Local machine (developer's computer)         | VS Code editor window                                                    | Interactive coding assistance, pair programming, quick fixes, IDE-native automation                                   |
| **Copilot in GitHub Mobile** | Copilot Mobile  | GitHub Copilot accessible via GitHub Mobile app on iOS/Android. Limited to chat-based assistance.                                                                                                        | Cloud-side processing                        | GitHub Mobile app                                                        | Quick questions, code review assistance on the go, mobile browsing context                                            |
| **Copilot in GitHub Web**    | Copilot Web     | GitHub Copilot accessible via GitHub.com web interface. Provides chat and integration with GitHub issues, pull requests, and repository context.                                                         | Cloud-side processing                        | GitHub.com web UI (pull requests, issues, code view)                     | Pull request assistance, issue triage, repository questions, web-based workflows                                      |
| **Copilot in CLI**           | Copilot CLI     | Standalone command-line interface to GitHub Copilot. Interactive shell mode for prompt-based assistance with file system access and terminal commands.                                                   | Local machine (terminal)                     | Terminal/shell command line                                              | Terminal automation, scripting assistance, local file operations, batch workflows                                     |
| **Copilot CLI SDK**          | Copilot SDK     | Programmatic SDKs (Node.js/TypeScript, Python, Go, .NET) for integrating GitHub Copilot into applications. Provides low-level APIs for session management, streaming, custom tools, and MCP integration. | Local machine or application runtime         | Application code (embedded programmatically)                             | Application-level AI integration, custom tool development, embedded conversational AI, multi-language app development |
| **Copilot Coding Agent**     | Copilot Agent   | Autonomous background agent that works on GitHub to complete development tasks. Creates pull requests independently based on issues or chat prompts. Runs in GitHub Actions environment.                 | GitHub cloud infrastructure (GitHub Actions) | GitHub Issues, Pull Requests, GitHub Chat, CLI, Third-party integrations | Autonomous bug fixes, feature implementation, test coverage, documentation updates, technical debt resolution         |

## Important defaults and behaviors

- **Transport**: stdio by default (most reliable); TCP requires explicit port configuration
- **Streaming**: Disabled by default; enable per-session via `streaming: true`
- **Auto-restart**: Enabled by default; set `autoRestart: false` to prevent auto-recovery
- **Tool timeout**: 30 seconds default for MCP stdio servers
- **Session persistence**: Sessions survive client restarts if sessionId is preserved
- **Event ordering**: Events fire in order (user.message → tool.execution → assistant.message_delta → assistant.message → session.idle)
- **Technical preview**: All SDKs are in technical preview and may have breaking changes between versions

## Troubleshooting guidance

- **"CLI server not found"**: Verify Copilot CLI is installed or pass explicit `cliPath`
- **"Tool not found"**: Check tool is registered in session and assistant has access (not in `excludedTools`)
- **"Permission denied"**: Permission handler returned deny; check handler logic and rules
- **Streaming not working**: Verify `streaming: true` in session config and subscribed to `assistant.message_delta`
- **MCP server connection fails**: Check server is running, path/URL is correct, and `timeout` is sufficient
- **Session not resuming**: Verify `sessionId` was preserved and matches existing session

## Reference files

- Use [SDK Installation & Setup](references/sdk-setup.md) for quick install commands and platform-specific notes.
- Use [API Reference Guide](references/api-reference.md) for detailed parameter descriptions and error codes.
- Use [Code Examples by Language](references/code-examples.md) for complete working examples in TypeScript, Python, Go, and .NET.
- Use [MCP Server Integration](references/mcp-integration.md) for MCP server setup, local vs. remote patterns, and debugging.
- Use [Custom Tools & Agents](references/tools-agents.md) for tool definition patterns, schema validation, and agent persona setup.
