# Code Examples (.NET)

Complete working examples in C# for common SDK use cases.

## Example 1: Basic Request-Response

```csharp
using GitHub.Copilot.SDK;
using System.Threading.Tasks;

class Program {
    static async Task Main(string[] args) {
        await using var client = new CopilotClient();
        await client.StartAsync();

        await using var session = await client.CreateSessionAsync(new SessionConfig {
            Model = "gpt-5"
        });

        var response = await session.SendAndWaitAsync(new MessageOptions {
            Prompt = "What is the capital of France?"
        });

        Console.WriteLine($"Response: {response.Data.Content}");
    }
}
```

## Example 2: Streaming Responses

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

session.Events.Subscribe(evt =>
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

## Example 3: Custom Tools

```csharp
using GitHub.Copilot.SDK;
using Microsoft.Extensions.AI;
using System.ComponentModel;

var client = new CopilotClient();
await client.StartAsync();

// Define tool using AIFunctionFactory
var calculateTool = AIFunctionFactory.Create(
    ([Description("Math operation")] string operation, [Description("First number")] double a, [Description("Second number")] double b) => {
        double? result = operation switch {
            "add" => a + b,
            "subtract" => a - b,
            "multiply" => a * b,
            "divide" => b != 0 ? a / b : null,
            _ => null
        };
        return new { result, textResultForLlm = $"{a} {operation} {b} = {result}" };
    },
    "calculate",
    "Perform basic math calculations"
);

var session = await client.CreateSessionAsync(new SessionConfig {
    Model = "gpt-5",
    Tools = new[] { calculateTool }
});

session.Events.Subscribe(evt => {
    if (evt is ToolExecutionStartEvent start) {
        Console.WriteLine($"Tool {start.ToolName} invoked");
    }
});

var response = await session.SendAndWaitAsync(new MessageOptions {
    Prompt = "What is 42 times 3?"
});

Console.WriteLine($"Response: {response.Data.Content}");
await session.DestroyAsync();
await client.StopAsync();
```

## Example 4: Permission Handling

```csharp
using GitHub.Copilot.SDK;

var client = new CopilotClient();
await client.StartAsync();

var session = await client.CreateSessionAsync(new SessionConfig {
    Model = "gpt-5",
    OnPermissionRequest = async (request, context) => {
        Console.WriteLine($"Permission request: {request.Kind}");
        
        switch (request.Kind) {
            case "write":
                var path = request.Properties["path"]?.ToString();
                if (path?.StartsWith("/tmp") == true) {
                    return new PermissionResult { Kind = "approved" };
                }
                return new PermissionResult { 
                    Kind = "denied-by-rules", 
                    Message = "Only /tmp directory allowed" 
                };
            
            case "shell":
                return new PermissionResult { Kind = "denied-interactively-by-user" };
            
            case "read":
                return new PermissionResult { Kind = "approved" };
            
            default:
                return new PermissionResult { 
                    Kind = "denied-no-approval-rule-and-could-not-request-from-user" 
                };
        }
    }
});

await session.SendAndWaitAsync(new MessageOptions {
    Prompt = "Create a file at /tmp/test.txt with 'Hello World'"
});

await session.DestroyAsync();
await client.StopAsync();
```

## Example 5: File Attachments

```csharp
using GitHub.Copilot.SDK;

var client = new CopilotClient();
await client.StartAsync();
var session = await client.CreateSessionAsync(new SessionConfig { Model = "gpt-5" });

var response = await session.SendAndWaitAsync(new MessageOptions {
    Prompt = "Analyze this code for security issues",
    Attachments = [
        new Attachment { 
            Type = "file", 
            Path = "./src/Auth.cs", 
            DisplayName = "Authentication Module" 
        },
        new Attachment { 
            Type = "directory", 
            Path = "./src", 
            DisplayName = "Source Code" 
        }
    ]
});

Console.WriteLine($"Analysis: {response.Data.Content}");
await session.DestroyAsync();
await client.StopAsync();
```
