# Frontend Tool Rendering & SSE Integration with Blazor

## Overview

Frontend tools are agent-requested functions that execute **on the Blazor client**, not the server. This is useful for:
- Browser-only operations (copy to clipboard, local file handling)
- Client-side computations
- Real-time data from local sources

The typical flow:
1. Agent calls a frontend tool
2. Server sends tool-call event via SSE
3. Blazor client executes the tool
4. Blazor sends result back to server
5. Agent continues with the result

## Registering Frontend Tools in Blazor

Use `AIFunctionFactory.Create()` to define client-side tools and include them in agent requests:

```csharp
// In Blazor component or service
var clipboardTool = AIFunctionFactory.Create(
    name: "copyToClipboard",
    description: "Copy text to user's clipboard",
    handler: async (string text) =>
    {
        // Use JavaScript interop to access clipboard API
        await jsRuntime.InvokeVoidAsync("navigator.clipboard.writeText", text);
        return "Text copied to clipboard";
    }
);

var localStorageTool = AIFunctionFactory.Create(
    name: "getLocalData",
    description: "Retrieve data from browser local storage",
    handler: async (string key) =>
    {
        var value = await jsRuntime.InvokeAsync<string>("localStorage.getItem", key);
        return value ?? "Key not found";
    }
);
```

## SSE Event Parsing in Blazor

Parse AG-UI protocol events from the SSE stream and handle each event type:

```csharp
@implements IAsyncDisposable

@code {
    private HttpClient httpClient;
    private EventSource eventSource;
    private List<AgentEvent> events = new();
    private string conversationId;

    private void ConnectToAgent()
    {
        var url = $"/api/chat?conversationId={conversationId}";
        eventSource = new EventSource(url);
        eventSource.OnMessage += (msg) => HandleSSEEvent(msg);
    }

    private void HandleSSEEvent(Message msg)
    {
        var evt = JsonSerializer.Deserialize<AgentEvent>(msg.Data);

        switch (evt.Type)
        {
            case "chatDelta":
                // Append to chat timeline
                ChatMessages.Last().Content += evt.Delta;
                break;

            case "toolCall":
                // Tool call started (Tool-Based UI: feature 5)
                events.Add(new AgentEvent { Type = "toolCall", ToolName = evt.Name, Arguments = evt.Arguments });
                break;

            case "toolResult":
                // Tool finished; display result
                var toolEvent = events.FirstOrDefault(e => e.ToolCallId == evt.ToolCallId);
                if (toolEvent != null)
                    toolEvent.Result = evt.Result;
                break;

            case "approvalRequest":
                // Human-in-the-Loop: show approval dialog (feature 3)
                ShowApprovalDialog(evt);
                break;

            case "progress":
                // Agentic GenUI: update progress for long-running tool (feature 4)
                UpdateProgress(evt.ToolCallId, evt.Status, evt.Percent);
                break;

            case "state":
                // Shared State: parse state update (feature 6)
                UpdateLocalState(evt.Key, evt.Value);
                break;

            case "argumentsStream":
                // Predictive State Updates: show arguments optimistically (feature 7)
                RenderOptimistic(evt.ToolCallId, evt.Arguments);
                break;
        }

        StateHasChanged();
    }

    private async Task SendUserMessage(string userInput)
    {
        // Include ConversationId and any client state in request
        var request = new
        {
            conversationId = conversationId,
            messages = new[] { new { role = "user", content = userInput } },
            frontendTools = new[] { clipboardTool, localStorageTool }, // Optional: send tool defs to server
            clientState = GetCurrentClientState() // Shared State: feature 6
        };

        var response = await httpClient.PostAsJsonAsync("/api/chat", request);
        // SSE stream will start sending events
    }

    async ValueTask IAsyncDisposable.DisposeAsync()
    {
        eventSource?.Dispose();
    }
}
```

## Tool Result Serialization

AG-UI expects tool results as JSON. When sending tool results back to server:

```csharp
// After executing frontend tool, send result via HTTP
var toolResultRequest = new
{
    conversationId = conversationId,
    toolCallId = "tool-1", // From the original toolCall event
    result = new
    {
        success = true,
        message = "Text copied to clipboard",
        timestamp = DateTime.UtcNow
    }
};

await httpClient.PostAsJsonAsync("/api/chat/tool-result", toolResultRequest);
```

## Backend vs Frontend Tools Comparison

| Aspect       | Backend Tools                           | Frontend Tools                             |
| ------------ | --------------------------------------- | ------------------------------------------ |
| Execution    | Server-side                             | Blazor client                              |
| Access       | Databases, APIs, files                  | Clipboard, localStorage, local file system |
| Latency      | Network roundtrip                       | Instant (local)                            |
| Definition   | `AIFunctionFactory.Create()` on server  | `AIFunctionFactory.Create()` in Blazor     |
| Registration | Via agent tools                         | Sent with each client request              |
| When to use  | Data access, computations, integrations | Local operations, UI interactions          |

## Source
- [Microsoft Learn: Frontend Tools](https://learn.microsoft.com/en-us/agent-framework/integrations/ag-ui/frontend-tools)
- [AG-UI Protocol: Tool Call Events](https://docs.ag-ui.com/)
