# Copilot SDK Examples

## Installation

| Language | Install Command |
|----------|----------------|
| **TypeScript** | `npm install @github/copilot-sdk tsx` |
| **Python** | `pip install github-copilot-sdk` |
| **Go** | `go get github.com/github/copilot-sdk/go` |
| **Rust** | `cargo add github-copilot-sdk --features derive` |
| **.NET** | `dotnet add package GitHub.Copilot.SDK` |
| **Java** | `com.github:copilot-sdk-java:${copilot.sdk.version}` |

## TypeScript

### Basic Usage

```typescript
import { CopilotClient, approveAll } from "@github/copilot-sdk";

const client = new CopilotClient();
await client.start();

const session = await client.createSession({
    model: "auto",
    onPermissionRequest: approveAll,
});

const response = await session.sendAndWait({ prompt: "What is 2 + 2?" });
console.log(response?.data.content);

await client.stop();
```

### Streaming

```typescript
const session = await client.createSession({ model: "auto", streaming: true });
session.on("assistant.message_delta", (event) => process.stdout.write(event.data.deltaContent));
session.on("session.idle", () => console.log());
await session.sendAndWait({ prompt: "Explain quantum computing" });
```

### Custom Tool

```typescript
import { defineTool } from "@github/copilot-sdk";
import { z } from "zod";

const getWeather = defineTool("get_weather", {
    description: "Get the current weather for a city",
    parameters: z.object({ city: z.string().describe("The city name") }),
    handler: async (args) => {
        return { city: args.city, temperature: "72°F", condition: "sunny" };
    },
});

const session = await client.createSession({
    model: "auto",
    tools: [getWeather],
});
```

### Custom Agent

```typescript
const session = await client.createSession({
    customAgents: [
        {
            name: "researcher",
            displayName: "Research Agent",
            description: "Explores codebases and answers questions using read-only tools",
            tools: ["grep", "glob", "view"],
            prompt: "You are a research assistant. Analyze code and answer questions.",
        },
        {
            name: "editor",
            displayName: "Editor Agent",
            description: "Makes targeted code changes",
            tools: ["view", "edit", "bash"],
            prompt: "You are a code editor. Make minimal, surgical changes.",
            infer: false,
        },
    ],
});
```

### MCP Server Config

```typescript
const session = await client.createSession({
    mcpServers: {
        "my-local-server": {
            type: "local",
            command: "node",
            args: ["./mcp-server.js"],
            env: { DEBUG: "true" },
            tools: ["*"],
        },
    },
});
```

### Hooks

```typescript
const session = await client.createSession({
    hooks: {
        onPreToolUse: async (input) => {
            if (BLOCKED_TOOLS.includes(input.toolName)) {
                return { permissionDecision: "deny", permissionDecisionReason: "Not permitted" };
            }
            return { permissionDecision: "allow" };
        },
        onSessionStart: async (input) => {
            return { additionalContext: "User prefers concise answers." };
        },
    },
});
```

### Loading Plugins

```typescript
const client = new CopilotClient({
    connection: RuntimeConnection.forStdio({
        args: ["--plugin-dir", "./plugins/code-reviewer"],
    }),
});
await client.start();
```

## Python

```python
from copilot import CopilotClient
from copilot.session import PermissionHandler

async def main():
    client = CopilotClient()
    await client.start()
    session = await client.create_session(
        on_permission_request=PermissionHandler.approve_all,
        model="auto"
    )
    response = await session.send_and_wait("What is 2 + 2?")
    print(response.data.content)
    await client.stop()
```

## Go

```go
client := copilot.NewClient(nil)
client.Start(ctx)
defer client.Stop()

session, _ := client.CreateSession(ctx, &copilot.SessionConfig{Model: "auto"})
response, _ := session.SendAndWait(ctx, copilot.MessageOptions{Prompt: "What is 2 + 2?"})
if d, ok := response.Data.(*copilot.AssistantMessageData); ok {
    fmt.Println(d.Content)
}
```

## .NET

```csharp
await using var client = new CopilotClient();
await using var session = await client.CreateSessionAsync(new SessionConfig {
    Model = "auto",
    OnPermissionRequest = PermissionHandler.ApproveAll
});
var response = await session.SendAndWaitAsync(new MessageOptions { Prompt = "What is 2 + 2?" });
Console.WriteLine(response?.Data.Content);
```

## Rust

```rust
let client = Client::start(ClientOptions::default()).await?;
let session = client.create_session(
    SessionConfig::default().with_permission_handler(Arc::new(ApproveAllHandler))
).await?;
let response = session.send_and_wait(
    MessageOptions::new("What is 2 + 2?")
).await?;
```

## Java

```java
try (var client = new CopilotClient()) {
    client.start().get();
    var session = client.createSession(
        new SessionConfig().setModel("auto")
            .setOnPermissionRequest(PermissionHandler.APPROVE_ALL)
    ).get();
    var response = session.sendAndWait(
        new MessageOptions().setPrompt("What is 2 + 2?")
    ).get();
    System.out.println(response.getData().content());
}
```
