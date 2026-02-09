# Microsoft Agent Framework Integration

The GitHub Copilot SDK integrates with the Microsoft Agent Framework, offering a consistent abstraction for building agentic applications in .NET. This allows you to treat GitHub Copilot as a building block in larger multi-agent systems.

## Packages

| Language | Package | Command |
|----------|---------|---------|
| **.NET** | `Microsoft.Agents.AI.GitHub.Copilot` | `dotnet add package Microsoft.Agents.AI.GitHub.Copilot --prerelease` |

## Creating a Copilot Agent

Wraps the core `CopilotClient` into an `AIAgent`.

### .NET
```csharp
using GitHub.Copilot.SDK;
using Microsoft.Agents.AI;

await using CopilotClient copilotClient = new();
await copilotClient.StartAsync();

// Convert to Agent Framework agent
AIAgent agent = copilotClient.AsAIAgent(
    instructions: "You are a helpful assistant."
);

Console.WriteLine(await agent.RunAsync("What is Microsoft Agent Framework?"));
```

## Function Tools

Register tools using the framework's patterns.

### .NET (AIFunctionFactory)
```csharp
using Microsoft.Extensions.AI;

AIFunction weatherTool = AIFunctionFactory.Create((string location) =>
{
    return $"The weather in {location} is sunny.";
}, "GetWeather", "Get weather for location.");

AIAgent agent = copilotClient.AsAIAgent(
    tools: [weatherTool],
    instructions: "You are a helpful weather agent."
);
```

## Streaming Responses

### .NET
```csharp
await foreach (AgentResponseUpdate update in agent.RunStreamingAsync("Tell a story."))
{
    Console.Write(update);
}
```

## Multi-Agent Workflows

Combine Copilot agents with other agents (e.g., Azure OpenAI) in sequential or hierarchical workflows.

### .NET (Sequential Workflow)
```csharp
using Microsoft.Agents.AI.Workflows;

// ... initialize writer (Azure OpenAI) and reviewer (Copilot) ...

Workflow workflow = AgentWorkflowBuilder.BuildSequential([writer, reviewer]);
await using StreamingRun run = await InProcessExecution.StreamAsync(workflow, input: prompt);
```

## Permissions & MCP Servers

Configure permissions and MCP servers via session configuration.

### .NET
```csharp
SessionConfig sessionConfig = new()
{
    OnPermissionRequest = (req, inv) => { /* approval logic */ },
    McpServers = new Dictionary<string, object>
    {
        ["filesystem"] = new McpLocalServerConfig { ... }
    }
};
AIAgent agent = copilotClient.AsAIAgent(sessionConfig);
```

