# Ralph SDK Migration Guide

This guide documents how to migrate the Ralph agent system from VS Code (`runSubagent`) to the GitHub Copilot SDK for custom C# applications.

---

## Overview

| Aspect       | VS Code Implementation          | SDK Implementation                 |
| ------------ | ------------------------------- | ---------------------------------- |
| Orchestrator | `ralph.agent.md` (prompt-based) | C# code with routing logic         |
| Subagents    | `.agent.md` files               | `CustomAgent` configurations       |
| Invocation   | `runSubagent` tool              | `session.SendAndWaitAsync()`       |
| State        | File-based (`.ralph-sessions/`) | File-based OR abstracted interface |

---

## Architecture Comparison

### VS Code Architecture

```
User Request
    ↓
ralph.agent.md (Orchestrator)
    ↓ runSubagent()
┌─────────────────────────────────────────────┐
│  .agent.md files (Planner, Executor, etc.)  │
└─────────────────────────────────────────────┘
    ↓
.ralph-sessions/<SESSION_ID>/ (File State)
```

### SDK Architecture

```txt
User Request
    ↓
RalphOrchestrator.cs (C# State Machine)
    ↓ session.SendAndWaitAsync()
┌─────────────────────────────────────────────┐
│  CustomAgent configs (loaded from .md or C#)│
└─────────────────────────────────────────────┘
    ↓
ISessionStateProvider (Abstracted State)
```

---

## Key Mapping: `runSubagent` to SDK

### VS Code Pattern

```markdown
#tool:agent/runSubagent
agentName: "Ralph-Executor"
description: "Implementation of task: task-1 [Attempt #1]"
prompt: |
  SESSION_PATH: .ralph-sessions/260131-144400/
  TASK_ID: task-1
  ATTEMPT_NUMBER: 1
```

### SDK Pattern (C#)

```csharp
// 1. Define the agent configuration
var executorAgent = new CustomAgent
{
    Name = "Ralph-Executor",
    Description = "Specialized execution agent for task implementation",
    Prompt = await File.ReadAllTextAsync("agents/ralph-executor.agent.md"),
    Tools = new[] { "Read", "Edit", "Search", "RunInTerminal" }
};

// 2. Create session with the agent
var session = await client.CreateSessionAsync(new SessionConfig
{
    Model = "gpt-5",
    CustomAgents = new[] { executorAgent }
});

// 3. Invoke with structured prompt
var result = await session.SendAndWaitAsync($"""
    @Ralph-Executor
    SESSION_PATH: {sessionPath}
    TASK_ID: {taskId}
    ATTEMPT_NUMBER: {attemptNumber}
    
    Read tasks.md to identify the Type, Files, Objective, and Success Criteria for this task.
    Implement the task, verify it meets ALL Success Criteria, update progress.md to [P] if met.
    Create the report file with PART 1: IMPLEMENTATION REPORT.
    """);

// 4. Parse response
var output = ParseExecutorResponse(result.Content);
```

---

## Loading Agent Definitions

### Option 1: Load from .agent.md files

```csharp
public class AgentLoader
{
    public async Task<CustomAgent> LoadFromMarkdownAsync(string agentPath)
    {
        var content = await File.ReadAllTextAsync(agentPath);
        var (frontmatter, body) = ParseMarkdownFrontmatter(content);
        
        return new CustomAgent
        {
            Name = frontmatter["name"],
            Description = frontmatter["description"],
            Prompt = body,
            Tools = ParseTools(frontmatter["tools"])
        };
    }
    
    private (Dictionary<string, string> frontmatter, string body) ParseMarkdownFrontmatter(string content)
    {
        // Parse YAML frontmatter between --- markers
        var match = Regex.Match(content, @"^---\s*\n(.*?)\n---\s*\n(.*)$", RegexOptions.Singleline);
        if (!match.Success) throw new FormatException("Invalid agent file format");
        
        var yaml = new YamlDotNet.Serialization.Deserializer()
            .Deserialize<Dictionary<string, string>>(match.Groups[1].Value);
        
        return (yaml, match.Groups[2].Value);
    }
}
```

### Option 2: Define agents in C#

```csharp
public static class RalphAgents
{
    public static CustomAgent Planner => new()
    {
        Name = "Ralph-Planner",
        Description = "Session initialization, task breakdown, Q&A coordination",
        Prompt = """
            You are a specialized planning agent...
            [Full prompt content]
            """,
        Tools = new[] { "Read", "Edit", "Search", "Agent" }
    };
    
    public static CustomAgent Executor => new()
    {
        Name = "Ralph-Executor",
        Description = "Task implementation across coding, research, documentation",
        Prompt = """
            You are a specialized execution agent...
            """,
        Tools = new[] { "Read", "Edit", "Search", "RunInTerminal", "WebFetch" }
    };
    
    // ... Reviewer, Questioner
}
```

---

## State Management Abstraction

### Interface Definition

```csharp
public interface ISessionStateProvider
{
    Task<string> GetSessionPathAsync(string sessionId);
    Task<Plan> ReadPlanAsync(string sessionPath);
    Task WritePlanAsync(string sessionPath, Plan plan);
    Task<TaskList> ReadTasksAsync(string sessionPath);
    Task WriteTasksAsync(string sessionPath, TaskList tasks);
    Task<Progress> ReadProgressAsync(string sessionPath);
    Task WriteProgressAsync(string sessionPath, Progress progress);
    Task<TaskReport> ReadReportAsync(string sessionPath, string taskId, int attempt);
    Task WriteReportAsync(string sessionPath, string taskId, int attempt, TaskReport report);
}
```

### File-Based Implementation

```csharp
public class FileBasedStateProvider : ISessionStateProvider
{
    private readonly string _basePath;
    
    public FileBasedStateProvider(string basePath = ".ralph-sessions")
    {
        _basePath = basePath;
    }
    
    public async Task<string> GetSessionPathAsync(string sessionId)
    {
        var path = Path.Combine(_basePath, sessionId);
        Directory.CreateDirectory(path);
        return path;
    }
    
    public async Task<Plan> ReadPlanAsync(string sessionPath)
    {
        var content = await File.ReadAllTextAsync(Path.Combine(sessionPath, "plan.md"));
        return Plan.ParseFromMarkdown(content);
    }
    
    public async Task WritePlanAsync(string sessionPath, Plan plan)
    {
        await File.WriteAllTextAsync(
            Path.Combine(sessionPath, "plan.md"),
            plan.ToMarkdown()
        );
    }
    
    // ... other implementations
}
```

### Database Implementation (Example)

```csharp
public class DatabaseStateProvider : ISessionStateProvider
{
    private readonly RalphDbContext _db;
    
    public async Task<Plan> ReadPlanAsync(string sessionPath)
    {
        var session = await _db.Sessions
            .Include(s => s.Plan)
            .FirstOrDefaultAsync(s => s.Path == sessionPath);
        return session?.Plan;
    }
    
    // ... other implementations
}
```

---

## Orchestrator State Machine (C#)

```csharp
public class RalphOrchestrator
{
    private readonly CopilotClient _client;
    private readonly ISessionStateProvider _state;
    private readonly AgentLoader _agentLoader;
    
    public enum State { Initializing, Planning, Executing, Reviewing, Complete, Failed }
    
    public async Task<OrchestratorResult> RunAsync(string userRequest, string? sessionId = null)
    {
        var currentState = State.Initializing;
        string sessionPath;
        
        // State machine loop
        while (currentState != State.Complete && currentState != State.Failed)
        {
            currentState = currentState switch
            {
                State.Initializing => await HandleInitializingAsync(userRequest, sessionId, out sessionPath),
                State.Planning => await HandlePlanningAsync(sessionPath),
                State.Executing => await HandleExecutingAsync(sessionPath),
                State.Reviewing => await HandleReviewingAsync(sessionPath),
                _ => throw new InvalidOperationException($"Unknown state: {currentState}")
            };
        }
        
        return new OrchestratorResult { State = currentState, SessionPath = sessionPath };
    }
    
    private async Task<State> HandleInitializingAsync(string userRequest, string? sessionId, out string sessionPath)
    {
        sessionId ??= DateTime.Now.ToString("yyMMdd-HHmmss");
        sessionPath = await _state.GetSessionPathAsync(sessionId);
        
        // Invoke Ralph-Planner
        var plannerAgent = await _agentLoader.LoadFromMarkdownAsync("agents/ralph-planner.agent.md");
        var session = await _client.CreateSessionAsync(new SessionConfig
        {
            CustomAgents = new[] { plannerAgent }
        });
        
        var result = await session.SendAndWaitAsync($"""
            @Ralph-Planner
            SESSION_PATH: {sessionPath}
            MODE: INITIALIZE
            USER_REQUEST: {userRequest}
            """);
        
        var output = ParsePlannerResponse(result.Content);
        
        return output.Status switch
        {
            "completed" => State.Executing,
            "needs_discovery_cycle" => State.Planning,
            "blocked" => State.Failed,
            _ => State.Planning
        };
    }
    
    private async Task<State> HandleExecutingAsync(string sessionPath)
    {
        var progress = await _state.ReadProgressAsync(sessionPath);
        var nextTask = progress.GetNextUncompletedTask();
        
        if (nextTask == null)
            return State.Complete;
        
        var attemptNumber = await DetermineAttemptNumber(sessionPath, nextTask.Id);
        
        // Invoke Ralph-Executor
        var executorAgent = await _agentLoader.LoadFromMarkdownAsync("agents/ralph-executor.agent.md");
        var session = await _client.CreateSessionAsync(new SessionConfig
        {
            CustomAgents = new[] { executorAgent }
        });
        
        var result = await session.SendAndWaitAsync($"""
            @Ralph-Executor
            SESSION_PATH: {sessionPath}
            TASK_ID: {nextTask.Id}
            ATTEMPT_NUMBER: {attemptNumber}
            """);
        
        var output = ParseExecutorResponse(result.Content);
        
        return output.Status == "completed" ? State.Reviewing : State.Executing;
    }
    
    private async Task<State> HandleReviewingAsync(string sessionPath)
    {
        var progress = await _state.ReadProgressAsync(sessionPath);
        var reviewPendingTask = progress.GetReviewPendingTask();
        
        if (reviewPendingTask == null)
            return State.Executing;
        
        // Invoke Ralph-Reviewer
        var reviewerAgent = await _agentLoader.LoadFromMarkdownAsync("agents/ralph-reviewer.agent.md");
        var session = await _client.CreateSessionAsync(new SessionConfig
        {
            CustomAgents = new[] { reviewerAgent }
        });
        
        var result = await session.SendAndWaitAsync($"""
            @Ralph-Reviewer
            SESSION_PATH: {sessionPath}
            TASK_ID: {reviewPendingTask.Id}
            REPORT_PATH: {reviewPendingTask.ReportPath}
            """);
        
        var output = ParseReviewerResponse(result.Content);
        
        // Update progress based on verdict
        if (output.Verdict == "Qualified")
        {
            progress.MarkCompleted(reviewPendingTask.Id);
        }
        else
        {
            progress.MarkForRework(reviewPendingTask.Id);
        }
        
        await _state.WriteProgressAsync(sessionPath, progress);
        
        return State.Executing;
    }
}
```

---

## Contract-Based Response Parsing

```csharp
public record ExecutorOutput
{
    public string Status { get; init; } = "completed";
    public string ReportPath { get; init; } = "";
    public bool SuccessCriteriaMet { get; init; }
    public List<DiscoveredTask> DiscoveredTasks { get; init; } = new();
    public List<string> Blockers { get; init; } = new();
}

public record ReviewerOutput
{
    public string Status { get; init; } = "completed";
    public string Verdict { get; init; } = "Qualified"; // or "Failed"
    public List<CriterionResult> CriteriaResults { get; init; } = new();
    public string QualityAssessment { get; init; } = "";
    public List<string> Issues { get; init; } = new();
    public string Feedback { get; init; } = "";
}

// Parser that extracts structured data from agent responses
public static class ResponseParser
{
    public static ExecutorOutput ParseExecutorResponse(string content)
    {
        // Parse structured output from response
        // Implementation depends on how agents format their responses
        // Could use JSON blocks, structured markdown, or regex patterns
    }
}
```

---

## Testing the SDK Implementation

```csharp
[TestClass]
public class RalphOrchestratorTests
{
    [TestMethod]
    public async Task GivenNewSession_WhenInitializing_ThenInvokesPlanner()
    {
        // Arrange
        var mockClient = new Mock<ICopilotClient>();
        var mockState = new Mock<ISessionStateProvider>();
        
        mockClient.Setup(c => c.CreateSessionAsync(It.IsAny<SessionConfig>()))
            .ReturnsAsync(new MockSession());
        
        var orchestrator = new RalphOrchestrator(mockClient.Object, mockState.Object);
        
        // Act
        var result = await orchestrator.RunAsync("Create a new feature");
        
        // Assert
        mockClient.Verify(c => c.CreateSessionAsync(
            It.Is<SessionConfig>(cfg => cfg.CustomAgents.Any(a => a.Name == "Ralph-Planner"))
        ), Times.Once);
    }
}
```

---

## Migration Checklist

- [ ] Install GitHub Copilot SDK NuGet package
- [ ] Create `ISessionStateProvider` interface and implementation
- [ ] Create `AgentLoader` to load `.agent.md` files
- [ ] Implement `RalphOrchestrator` state machine
- [ ] Define response parsers for each subagent contract
- [ ] Add error handling and retry logic
- [ ] Create unit tests for orchestrator logic
- [ ] Test with real Copilot SDK connection

---

## References

- [GitHub Copilot SDK](https://github.com/github/copilot-sdk)
- [Ralph Subagent Contracts](ralph-subagent-contracts.md)
- [Ralph Artifact Templates](ralph-artifact-templates.md)
- [Copilot SDK Mental Model](../explanation/copilot-sdk-acp-mental-model.md)
