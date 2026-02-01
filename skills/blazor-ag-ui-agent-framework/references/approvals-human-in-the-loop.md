# Human-in-the-Loop: Approvals & Confirmations

## Overview

Human-in-the-loop (approval workflows) allow agents to request user confirmation before executing sensitive actions (delete, transfer funds, send email, etc.). Agent Framework implements this via `ApprovalRequiredAIFunction` middleware that converts approval logic into AG-UI protocol events.

## Agent Framework Implementation

### Define an Approval-Required Tool

Use `ApprovalRequiredAIFunction` to wrap any tool that requires approval:

```csharp
var deleteTool = AIFunctionFactory.Create(
    name: "deleteRecord",
    description: "Delete a record from the database",
    handler: async (string recordId) => {
        // Actual deletion logic
        db.Records.Remove(recordId);
        return "Record deleted";
    }
);

var approvalWrapper = new ApprovalRequiredAIFunction(
    function: deleteTool,
    approvalPrompt: "User is about to delete record {recordId}. Approve?" // Message shown to user
);

agent.AddFunction(approvalWrapper);
```

### How Middleware Works

1. Agent Framework detects tool is wrapped with `ApprovalRequiredAIFunction`
2. Instead of executing immediately, middleware emits an AG-UI `approvalRequest` event
3. SSE stream sends event to Blazor frontend
4. User sees approval dialog, clicks "Approve" or "Deny"
5. Blazor sends POST with approval response (via state or callback)
6. Agent resumes execution or cancels based on response

### Approval Event Structure

```json
{
  "type": "approvalRequest",
  "id": "approval-abc123",
  "toolCallId": "tool-1",
  "functionName": "deleteRecord",
  "arguments": {
    "recordId": "12345"
  },
  "prompt": "User is about to delete record 12345. Approve?"
}
```

### Approval Response (from Blazor)

Blazor sends approval response in next POST request:

```csharp
// In Blazor component
await httpClient.PostAsJsonAsync("/api/chat", new {
    conversationId = currentConversationId,
    approvalResponse = new {
        approvalId = "approval-abc123",
        approved = true,  // or false to deny
        reason = "User confirmed deletion" // optional
    }
});
```

## Blazor Implementation

### Display Approval Dialog

Parse approval-request events and show dialog:

```csharp
@page "/agent"
@implements IAsyncDisposable

<div id="chat-container">
    @foreach (var message in chatMessages)
    {
        <ChatMessage Message="message" />
    }
</div>

@if (showApprovalDialog)
{
    <ApprovalDialog 
        Prompt="currentApproval.Prompt"
        OnApprove="() => HandleApproval(true)"
        OnDeny="() => HandleApproval(false)" />
}

@code {
    private List<AgentEvent> chatMessages = new();
    private AgentEvent currentApproval;
    private bool showApprovalDialog = false;
    private EventSource eventSource;

    protected override async Task OnInitializedAsync()
    {
        // Connect to SSE stream
        eventSource = new EventSource("/api/chat?conversationId=" + conversationId);
        eventSource.OnMessage += HandleSSEEvent;
    }

    private void HandleSSEEvent(Message e)
    {
        var evt = JsonSerializer.Deserialize<AgentEvent>(e.Data);

        if (evt.Type == "approvalRequest")
        {
            currentApproval = evt;
            showApprovalDialog = true;
            StateHasChanged();
        }
        else if (evt.Type == "toolResult")
        {
            chatMessages.Add(evt);
            StateHasChanged();
        }
    }

    private async Task HandleApproval(bool approved)
    {
        showApprovalDialog = false;

        // Send approval response back to agent
        await httpClient.PostAsJsonAsync("/api/chat", new {
            conversationId = conversationId,
            approvalResponse = new {
                approvalId = currentApproval.Id,
                approved = approved
            }
        });
    }
}
```

## Best Practices

1. **Use descriptive prompts**: Include specific information in the approval message (e.g., "Delete user john@example.com?" not "Proceed?")
2. **Provide context**: Show relevant data (record ID, amount, recipient) in the dialog
3. **Handle denial gracefully**: When user denies, agent should explain why the action was cancelled
4. **Audit log**: Record all approvals (approved/denied) with timestamp and user ID for compliance
5. **Set timeouts**: Approval requests should expire after N seconds (e.g., 5 minutes) to avoid stale approvals
6. **Test workflow**: Verify both approval and denial paths work correctly

## AG-UI Protocol Events

### Full Approval Workflow

```
1. User types: "Delete user john@example.com"
   ↓
2. Agent calls deleteUser("john@example.com")
   ↓
3. Middleware detects ApprovalRequiredAIFunction
   ↓
4. SSE emits: { type: "approvalRequest", id: "approval-1", prompt: "Delete john@example.com?" }
   ↓
5. Blazor shows dialog
   ↓
6. User clicks "Approve"
   ↓
7. Blazor POST: { approvalResponse: { approvalId: "approval-1", approved: true } }
   ↓
8. Agent resumes, executes deleteUser()
   ↓
9. SSE emits: { type: "toolResult", result: "User deleted" }
   ↓
10. Blazor displays result
```

## References
- [Agent Framework: ApprovalRequiredAIFunction](https://learn.microsoft.com/en-us/agent-framework/)
- [AG-UI Protocol: approvalRequest event](https://docs.ag-ui.com/)
