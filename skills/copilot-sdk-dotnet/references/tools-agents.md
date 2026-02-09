# Custom Tools & Agents (.NET)

In-depth patterns for defining tools with type-safe schemas, validation, and creating specialized agent personas using `Microsoft.Extensions.AI`.

## Tool Definition Patterns

### Pattern 1: AIFunctionFactory (Recommended)

The recommended way to define tools in C# is using `AIFunctionFactory`. This automatically generates the JSON schema from your method signature and XML documentation or `[Description]` attributes.

#### Basic Tool

```csharp
using Microsoft.Extensions.AI;
using System.ComponentModel;
using System.ComponentModel.DataAnnotations;

public class UserTools
{
    [Description("Fetch user information by ID")]
    public async Task<string> GetUserAsync(
        [Description("Unique user identifier")] 
        [RegularExpression(@"^\d+$", ErrorMessage = "User ID must be numeric")]
        string userId,
        
        [Description("Include full profile details (default: false)")]
        bool includeDetails = false)
    {
        // Simulate DB fetch
        if (userId == "0") return "User not found";
        
        return $"User: Alice (ID: {userId}) - Details Included: {includeDetails}";
    }
}

// ... inside your session setup
var tools = new UserTools();
var toolFunction = AIFunctionFactory.Create(tools.GetUserAsync);

// Use with CopilotClient (assuming an adapter or direct AI framework usage)
```

### Pattern 2: Manual Tool Definition

If you need manual control over the schema or execution pipeline.

```csharp
using GitHub.Copilot.SDK;

var myTool = new ToolDefinition
{
    Name = "get_weather",
    Description = "Gets the current weather",
    Parameters = new ToolParameters // Define JSON schema manually
    {
        Type = "object",
        Properties = new Dictionary<string, object>
        {
            ["location"] = new { type = "string", description = "City name" }
        },
        Required = new[] { "location" }
    }
};
```

## Agent Personas

Specialized agents can be created by combining a system prompt with specific toolsets.

### Support Agent

Designed to troubleshoot issues.

**System Prompt:**
> You are a tier-2 support agent. Always check the knowledge base first before suggesting solutions. Be empathetic but concise.

**Recommended Tools:**
- `search_knowledge_base`
- `check_ticket_status`
- `escalate_ticket`

### Code Architech

Designed to plan high-level modifications.

**System Prompt:**
> You are a senior software architect. Focus on scalability, security, and maintainability. Do not write implementation code unless asked for a PoC.

**Recommended Tools:**
- `analyze_repository_structure`
- `check_dependencies`

## Handling Tool Results

When a tool executes, you should return a clear string result for the LLM.

```csharp
// In your tool method
public string GetStatus(string ticketId)
{
    try 
    {
        var status = _service.GetStatus(ticketId);
        return $"Ticket {ticketId} status: {status}";
    }
    catch (Exception ex)
    {
        // Return error as string so LLM knows it failed
        return $"Error fetching status for {ticketId}: {ex.Message}";
    }
}
```
