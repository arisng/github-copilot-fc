# Code Examples by Language

Complete working examples in TypeScript, Python, Go, and .NET for common SDK use cases.

## Example 1: Basic Request-Response

### TypeScript

```typescript
import { CopilotClient } from "@github/copilot-sdk";

async function main() {
    const client = new CopilotClient();
    
    try {
        await client.start();
        const session = await client.createSession({ 
            model: "gpt-5" 
        });
        
        const response = await session.sendAndWait({
            prompt: "What is the capital of France?"
        });
        
        console.log("Response:", response?.data.content);
        await session.destroy();
    } finally {
        await client.stop();
    }
}

main();
```

### Python

```python
import asyncio
from copilot import CopilotClient

async def main():
    client = CopilotClient()
    
    try:
        await client.start()
        session = await client.create_session({"model": "gpt-5"})
        
        response = await session.send_and_wait({
            "prompt": "What is the capital of France?"
        })
        
        print(f"Response: {response['data']['content']}")
        await session.destroy()
    finally:
        await client.stop()

asyncio.run(main())
```

### Go

```go
package main

import (
    "fmt"
    "log"
    copilot "github.com/github/copilot-sdk/go"
)

func main() {
    client := copilot.NewClient(nil)
    
    if err := client.Start(); err != nil {
        log.Fatal(err)
    }
    defer client.Stop()
    
    session, err := client.CreateSession(&copilot.SessionConfig{
        Model: "gpt-5",
    })
    if err != nil {
        log.Fatal(err)
    }
    defer session.Destroy()
    
    response, err := session.SendAndWait(&copilot.MessageOptions{
        Prompt: "What is the capital of France?",
    })
    
    if err != nil {
        log.Fatal(err)
    }
    fmt.Printf("Response: %s\n", response.Data.Content)
}
```

### .NET

```csharp
using GitHub.Copilot.SDK;

var client = new CopilotClient();

try
{
    await client.StartAsync();
    await using var session = await client.CreateSessionAsync(new SessionConfig
    {
        Model = "gpt-5"
    });
    
    var response = await session.SendAndWaitAsync(new MessageOptions
    {
        Prompt = "What is the capital of France?"
    });
    
    Console.WriteLine($"Response: {response?.Data.Content}");
}
finally
{
    await client.StopAsync();
}
```

---

## Example 2: Streaming Responses

### TypeScript

```typescript
import { CopilotClient } from "@github/copilot-sdk";

async function main() {
    const client = new CopilotClient();
    await client.start();
    
    const session = await client.createSession({
        model: "gpt-5",
        streaming: true
    });
    
    let isComplete = false;
    
    session.on((event) => {
        if (event.type === "assistant.message_delta") {
            process.stdout.write(event.data.deltaContent);
        } else if (event.type === "assistant.message") {
            console.log("\n[Message complete]");
            isComplete = true;
        }
    });
    
    await session.sendAndWait({
        prompt: "Write a haiku about programming"
    });
    
    await session.destroy();
    await client.stop();
}

main();
```

### Python

```python
import asyncio
from copilot import CopilotClient

async def main():
    client = CopilotClient()
    await client.start()
    
    session = await client.create_session({
        "model": "gpt-5",
        "streaming": True
    })
    
    done = asyncio.Event()
    
    def on_event(event):
        if event.type.value == "assistant.message_delta":
            print(event.data.delta_content, end="", flush=True)
        elif event.type.value == "assistant.message":
            print("\n[Message complete]")
            done.set()
    
    session.on(on_event)
    
    await session.send({
        "prompt": "Write a haiku about programming"
    })
    
    await done.wait()
    await session.destroy()
    await client.stop()

asyncio.run(main())
```

### Go

```go
package main

import (
    "fmt"
    copilot "github.com/github/copilot-sdk/go"
)

func main() {
    client := copilot.NewClient(nil)
    client.Start()
    defer client.Stop()
    
    session, _ := client.CreateSession(&copilot.SessionConfig{
        Model:     "gpt-5",
        Streaming: true,
    })
    defer session.Destroy()
    
    done := make(chan bool)
    
    session.On(func(event copilot.SessionEvent) {
        switch event.Type {
        case "assistant.message_delta":
            if event.Data.DeltaContent != nil {
                fmt.Print(*event.Data.DeltaContent)
            }
        case "assistant.message":
            fmt.Println("\n[Message complete]")
            close(done)
        }
    })
    
    session.Send(copilot.MessageOptions{
        Prompt: "Write a haiku about programming",
    })
    
    <-done
}
```

### .NET

```csharp
using GitHub.Copilot.SDK;

var client = new CopilotClient();
await client.StartAsync();

await using var session = await client.CreateSessionAsync(new SessionConfig
{
    Model = "gpt-5",
    Streaming = true
});

var done = new TaskCompletionSource();

session.On(evt =>
{
    switch (evt)
    {
        case AssistantMessageDeltaEvent delta:
            Console.Write(delta.Data.DeltaContent);
            break;
        case AssistantMessageEvent:
            Console.WriteLine("\n[Message complete]");
            done.SetResult();
            break;
    }
});

await session.SendAsync(new MessageOptions
{
    Prompt = "Write a haiku about programming"
});

await done.Task;
await session.DestroyAsync();
await client.StopAsync();
```

---

## Example 3: Custom Tools

### TypeScript with Zod

```typescript
import { z } from "zod";
import { CopilotClient, defineTool } from "@github/copilot-sdk";

async function main() {
    const client = new CopilotClient();
    await client.start();
    
    // Define a custom tool
    const calculateTool = defineTool("calculate", {
        description: "Perform basic math calculations",
        parameters: z.object({
            operation: z.enum(["add", "subtract", "multiply", "divide"])
                .describe("Math operation to perform"),
            a: z.number().describe("First number"),
            b: z.number().describe("Second number")
        }),
        handler: async ({ operation, a, b }) => {
            let result;
            switch (operation) {
                case "add": result = a + b; break;
                case "subtract": result = a - b; break;
                case "multiply": result = a * b; break;
                case "divide": result = b !== 0 ? a / b : null; break;
            }
            return {
                result,
                textResultForLlm: `${a} ${operation} ${b} = ${result}`
            };
        }
    });
    
    const session = await client.createSession({
        model: "gpt-5",
        tools: [calculateTool]
    });
    
    session.on((event) => {
        if (event.type === "tool.execution_start") {
            console.log(`Tool ${event.data.toolName} invoked`);
        }
    });
    
    const response = await session.sendAndWait({
        prompt: "What is 42 times 3?"
    });
    
    console.log("Response:", response?.data.content);
    await session.destroy();
    await client.stop();
}

main();
```

### Python with Pydantic

```python
from pydantic import BaseModel, Field
from copilot import CopilotClient, define_tool
import asyncio

class CalculateParams(BaseModel):
    operation: str = Field(description="Math operation: add, subtract, multiply, divide")
    a: float = Field(description="First number")
    b: float = Field(description="Second number")

@define_tool(description="Perform basic math calculations")
async def calculate(params: CalculateParams) -> dict:
    if params.operation == "add":
        result = params.a + params.b
    elif params.operation == "subtract":
        result = params.a - params.b
    elif params.operation == "multiply":
        result = params.a * params.b
    elif params.operation == "divide":
        result = params.a / params.b if params.b != 0 else None
    
    return {
        "result": result,
        "textResultForLlm": f"{params.a} {params.operation} {params.b} = {result}"
    }

async def main():
    client = CopilotClient()
    await client.start()
    
    session = await client.create_session({
        "model": "gpt-5",
        "tools": [calculate]
    })
    
    done = asyncio.Event()
    
    def on_event(event):
        if event.type.value == "tool.execution_start":
            print(f"Tool {event.data.tool_name} invoked")
        elif event.type.value == "session.idle":
            done.set()
    
    session.on(on_event)
    
    await session.send({
        "prompt": "What is 42 times 3?"
    })
    
    await done.wait()
    await session.destroy()
    await client.stop()

asyncio.run(main())
```

---

## Example 4: Permission Handling

### TypeScript

```typescript
import { CopilotClient, PermissionRequest } from "@github/copilot-sdk";

async function main() {
    const client = new CopilotClient();
    await client.start();
    
    const session = await client.createSession({
        model: "gpt-5",
        onPermissionRequest: async (request, context) => {
            console.log(`Permission request in session ${context.sessionId}: ${request.kind}`);
            
            switch (request.kind) {
                case "write":
                    // Only allow writes to /tmp
                    const path = request.path as string;
                    if (path.startsWith("/tmp")) {
                        return { kind: "approved" };
                    }
                    return { 
                        kind: "denied-by-rules", 
                        rules: [{ reason: "Only /tmp directory allowed" }] 
                    };
                
                case "shell":
                    // Deny all shell commands
                    return { kind: "denied-interactively-by-user" };
                
                case "read":
                    // Allow all reads
                    return { kind: "approved" };
                
                default:
                    return { kind: "denied-no-approval-rule-and-could-not-request-from-user" };
            }
        }
    });
    
    await session.sendAndWait({
        prompt: "Create a file at /tmp/test.txt with 'Hello World'"
    });
    
    await session.destroy();
    await client.stop();
}

main();
```

---

## Example 5: File Attachments

### TypeScript

```typescript
import { CopilotClient } from "@github/copilot-sdk";

async function main() {
    const client = new CopilotClient();
    await client.start();
    
    const session = await client.createSession({ model: "gpt-5" });
    
    const response = await session.sendAndWait({
        prompt: "Analyze this code for security issues and suggest improvements",
        attachments: [
            {
                type: "file",
                path: "./src/auth.ts",
                displayName: "Authentication Module"
            },
            {
                type: "directory",
                path: "./src",
                displayName: "Source Code"
            }
        ]
    });
    
    console.log("Analysis:", response?.data.content);
    await session.destroy();
    await client.stop();
}

main();
```
