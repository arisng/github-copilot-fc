# Ralph V2 .NET — Prototype Scaffold

> Console app project structure, NuGet packages, key code patterns, and getting-started guide.

---

## Project Structure

```
src/
├── RalphV2.Console/
│   ├── RalphV2.Console.csproj
│   ├── Program.cs
│   ├── Startup.cs
│   ├── appsettings.json
│   │
│   ├── Configuration/
│   │   ├── RalphOptions.cs
│   │   └── AgentOptions.cs
│   │
│   ├── Data/
│   │   ├── RalphDbContext.cs
│   │   ├── Enums/
│   │   │   ├── OrchestratorState.cs
│   │   │   ├── TaskItemStatus.cs
│   │   │   ├── TaskItemType.cs
│   │   │   ├── AgentRole.cs
│   │   │   ├── QuestionCategory.cs
│   │   │   ├── ReviewVerdict.cs
│   │   │   ├── SignalType.cs
│   │   │   └── FeedbackSeverity.cs
│   │   ├── Entities/
│   │   │   ├── Session.cs
│   │   │   ├── Iteration.cs
│   │   │   ├── PlanSnapshot.cs
│   │   │   ├── TaskItem.cs
│   │   │   ├── TaskDependency.cs
│   │   │   ├── TaskReport.cs
│   │   │   ├── Question.cs
│   │   │   ├── FeedbackBatch.cs
│   │   │   ├── FeedbackItem.cs
│   │   │   ├── FeedbackAttachment.cs
│   │   │   ├── ReplanningDelta.cs
│   │   │   ├── Signal.cs
│   │   │   └── AgentInvocation.cs
│   │   └── Repositories/
│   │       ├── ISessionRepository.cs
│   │       └── SessionRepository.cs
│   │
│   ├── Tools/
│   │   ├── SessionTools.cs            # DB-backed session artifact tools
│   │   ├── WorkspaceTools.cs          # File-based workspace tools
│   │   ├── ShellTools.cs
│   │   ├── WebTools.cs
│   │   └── UtilTools.cs
│   │
│   ├── Copilot/
│   │   ├── ICopilotClientManager.cs
│   │   └── CopilotClientManager.cs
│   │
│   ├── Agents/
│   │   ├── ToolSetFactory.cs
│   │   ├── IAgentFactory.cs
│   │   ├── AgentFactory.cs
│   │   ├── IAgentInvoker.cs
│   │   └── AgentInvoker.cs
│   │
│   ├── Orchestration/
│   │   ├── OrchestratorStateMachine.cs
│   │   ├── WaveComputer.cs
│   │   ├── ConcurrentBatchExecutor.cs
│   │   └── Handlers/
│   │       ├── IStateHandler.cs
│   │       ├── InitializingHandler.cs
│   │       ├── PlanningHandler.cs
│   │       ├── BatchingHandler.cs
│   │       ├── ExecutingBatchHandler.cs
│   │       ├── ReviewingBatchHandler.cs
│   │       ├── SessionReviewHandler.cs
│   │       ├── CompleteHandler.cs
│   │       └── ReplanningHandler.cs
│   │
│   ├── Commands/
│   │   ├── NewCommand.cs
│   │   ├── ResumeCommand.cs
│   │   ├── StatusCommand.cs
│   │   ├── SignalCommand.cs
│   │   └── FeedbackCommand.cs
│   │
│   └── Prompts/
│       ├── PlannerPrompt.cs          # Embedded system prompts
│       ├── QuestionerPrompt.cs
│       ├── ExecutorPrompt.cs
│       └── ReviewerPrompt.cs
│
└── RalphV2.Tests/                    # Future: unit tests
    └── RalphV2.Tests.csproj
```

---

## .csproj File

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <RootNamespace>RalphV2.Console</RootNamespace>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>

  <ItemGroup>
    <!-- GitHub Copilot SDK -->
    <PackageReference Include="GitHub.Copilot.SDK" Version="*" />
    
    <!-- Microsoft Agent Framework for Copilot -->
    <PackageReference Include="Microsoft.Agents.AI.GitHub.Copilot" Version="*-*" />
    
    <!-- AI Function Factory -->
    <PackageReference Include="Microsoft.Extensions.AI" Version="*" />
    
    <!-- EF Core + SQLite -->
    <PackageReference Include="Microsoft.EntityFrameworkCore.Sqlite" Version="10.*" />
    <PackageReference Include="Microsoft.EntityFrameworkCore.Design" Version="10.*">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers</IncludeAssets>
    </PackageReference>
    
    <!-- CLI framework -->
    <PackageReference Include="System.CommandLine" Version="2.*" />
    
    <!-- Dependency injection & logging -->
    <PackageReference Include="Microsoft.Extensions.DependencyInjection" Version="10.*" />
    <PackageReference Include="Microsoft.Extensions.Logging.Console" Version="10.*" />
    <PackageReference Include="Microsoft.Extensions.Configuration.Json" Version="10.*" />
    <PackageReference Include="Microsoft.Extensions.Options.ConfigurationExtensions" Version="10.*" />
  </ItemGroup>

</Project>
```

---

## appsettings.json

```json
{
  "ConnectionStrings": {
    "Ralph": "Data Source=.ralph-sessions/ralph.db"
  },
  "Ralph": {
    "SessionsDirectory": ".ralph-sessions",
    "MaxConcurrency": 2,
    "DefaultModel": "gpt-5",
    "CopilotLogLevel": "warning",
    "AgentTimeoutSeconds": 300,
    "StreamingEnabled": true
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "RalphV2": "Debug"
    }
  }
}
```

---

## Key Code Patterns

### Pattern 1: Program.cs Entry Point

```csharp
using System.CommandLine;
using Microsoft.Extensions.DependencyInjection;
using RalphV2.Console;
using RalphV2.Console.Commands;

var services = Startup.ConfigureServices();
await using var serviceProvider = services.BuildServiceProvider();

var rootCommand = new RootCommand("Ralph V2 - Multi-agent orchestration CLI");

rootCommand.AddCommand(NewCommand.Create(serviceProvider));
rootCommand.AddCommand(ResumeCommand.Create(serviceProvider));
rootCommand.AddCommand(StatusCommand.Create(serviceProvider));
rootCommand.AddCommand(SignalCommand.Create(serviceProvider));
rootCommand.AddCommand(FeedbackCommand.Create(serviceProvider));

return await rootCommand.InvokeAsync(args);
```

### Pattern 2: CopilotClientManager

```csharp
using GitHub.Copilot.SDK;
using Microsoft.Extensions.Options;

namespace RalphV2.Console.Copilot;

public class CopilotClientManager : ICopilotClientManager, IAsyncDisposable
{
    private readonly CopilotClient _client;
    private readonly ILogger<CopilotClientManager> _logger;
    private bool _started;

    public CopilotClientManager(IOptions<RalphOptions> options, ILogger<CopilotClientManager> logger)
    {
        _logger = logger;
        _client = new CopilotClient(new CopilotClientOptions
        {
            LogLevel = options.Value.CopilotLogLevel,
            AutoStart = false,  // We manage lifecycle explicitly
            AutoRestart = true
        });
    }

    public async Task StartAsync()
    {
        if (_started) return;
        _logger.LogInformation("Starting CopilotClient...");
        await _client.StartAsync();
        _started = true;
        
        var ping = await _client.PingAsync();
        _logger.LogInformation("CopilotClient connected. Ping: {Latency}ms", ping.Latency);
    }

    public CopilotClient Client => _started 
        ? _client 
        : throw new InvalidOperationException("CopilotClient not started");

    public async ValueTask DisposeAsync()
    {
        if (_started)
        {
            await _client.StopAsync();
            _started = false;
        }
        await _client.DisposeAsync();
    }
}
```

### Pattern 3: AgentFactory with Role-Specific Tools

```csharp
using GitHub.Copilot.SDK;
using Microsoft.Agents.AI;
using Microsoft.Extensions.AI;

namespace RalphV2.Console.Agents;

public class AgentFactory : IAgentFactory
{
    private readonly ICopilotClientManager _clientManager;
    private readonly ToolSetFactory _toolSetFactory;
    private readonly ILogger<AgentFactory> _logger;

    public AgentFactory(
        ICopilotClientManager clientManager,
        ToolSetFactory toolSetFactory,
        ILogger<AgentFactory> logger)
    {
        _clientManager = clientManager;
        _toolSetFactory = toolSetFactory;
        _logger = logger;
    }

    public AIAgent CreateAgent(AgentRole role, Guid sessionId, RalphDbContext db, string workspacePath)
    {
        var tools = _toolSetFactory.CreateToolSet(role, sessionId, db, workspacePath);
        var prompt = GetSystemPrompt(role);
        
        _logger.LogDebug("Creating {Role} agent with {ToolCount} tools", role, tools.Length);
        
        return _clientManager.Client.AsAIAgent(
            instructions: prompt,
            tools: tools
        );
    }

    private string GetSystemPrompt(AgentRole role) => role switch
    {
        AgentRole.Planner    => PlannerPrompt.SystemPrompt,
        AgentRole.Questioner => QuestionerPrompt.SystemPrompt,
        AgentRole.Executor   => ExecutorPrompt.SystemPrompt,
        AgentRole.Reviewer   => ReviewerPrompt.SystemPrompt,
        _ => throw new ArgumentOutOfRangeException(nameof(role))
    };
}
```

### Pattern 4: AgentInvoker with Structured Response Parsing

```csharp
using Microsoft.Agents.AI;
using System.Text.Json;

namespace RalphV2.Console.Agents;

public class AgentInvoker : IAgentInvoker
{
    private readonly IAgentFactory _agentFactory;
    private readonly ILogger<AgentInvoker> _logger;

    public async Task<AgentResult> InvokeAsync(
        AgentRole role,
        string prompt,
        string sessionPath,
        CancellationToken ct = default)
    {
        _logger.LogInformation("Invoking {Role} agent...", role);
        var sw = Stopwatch.StartNew();

        try
        {
            var agent = _agentFactory.CreateAgent(role, sessionPath);
            
            // Use streaming for console output
            var responseBuilder = new StringBuilder();
            await foreach (var update in agent.RunStreamingAsync(prompt).WithCancellation(ct))
            {
                Console.Write(update);
                responseBuilder.Append(update);
            }
            Console.WriteLine();
            
            sw.Stop();
            _logger.LogInformation("{Role} agent completed in {Duration}ms", role, sw.ElapsedMilliseconds);
            
            var response = responseBuilder.ToString();
            return ParseAgentResponse(response);
        }
        catch (OperationCanceledException)
        {
            return AgentResult.Cancelled(role);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "{Role} agent failed", role);
            return AgentResult.Failed(role, ex.Message);
        }
    }

    private AgentResult ParseAgentResponse(string response)
    {
        // Try to extract JSON block from response (agents output JSON in code blocks)
        var jsonMatch = Regex.Match(response, @"```json\s*(.*?)\s*```", RegexOptions.Singleline);
        if (jsonMatch.Success)
        {
            try
            {
                return JsonSerializer.Deserialize<AgentResult>(jsonMatch.Groups[1].Value)!;
            }
            catch { /* Fall through to raw response */ }
        }
        
        return new AgentResult
        {
            Status = "completed",
            RawResponse = response
        };
    }
}
```

### Pattern 5: OrchestratorStateMachine Core Loop

```csharp
namespace RalphV2.Console.Orchestration;

public class OrchestratorStateMachine
{
    private readonly Dictionary<OrchestratorState, IStateHandler> _handlers;
    private readonly RalphDbContext _db;
    private readonly ILogger<OrchestratorStateMachine> _logger;

    public async Task<OrchestratorResult> RunAsync(
        Guid sessionId,
        string? userRequest = null,
        CancellationToken ct = default)
    {
        var state = await ResolveInitialStateAsync(sessionId);
        _logger.LogInformation("Starting orchestration at state: {State}", state);

        while (state is not (OrchestratorState.Complete 
                          or OrchestratorState.Stopped 
                          or OrchestratorState.AwaitingFeedback))
        {
            ct.ThrowIfCancellationRequested();
            
            // Poll live signals from DB
            var signal = await _db.Signals
                .Where(s => s.SessionId == sessionId && !s.IsProcessed)
                .OrderBy(s => s.CreatedAt)
                .FirstOrDefaultAsync(ct);
            if (signal is not null)
            {
                signal.IsProcessed = true;
                signal.ProcessedAt = DateTime.UtcNow;
                await _db.SaveChangesAsync(ct);
                state = await HandleSignalAsync(signal, state);
                if (state is OrchestratorState.Stopped or OrchestratorState.Paused)
                    continue;
            }

            // Execute state handler
            if (!_handlers.TryGetValue(state, out var handler))
                throw new InvalidOperationException($"No handler for state: {state}");

            _logger.LogInformation("Executing handler for state: {State}", state);
            var nextState = await handler.HandleAsync(sessionId, ct);
            
            // Persist state transition to DB
            var session = await _db.Sessions.FindAsync([sessionId], ct);
            session!.CurrentState = nextState;
            session.UpdatedAt = DateTime.UtcNow;
            await _db.SaveChangesAsync(ct);
            _logger.LogInformation("State transition: {From} → {To}", state, nextState);
            
            state = nextState;
        }

        return new OrchestratorResult(state, sessionId.ToString());
    }

    private async Task<OrchestratorState> ResolveInitialStateAsync(Guid sessionId)
    {
        var session = await _db.Sessions.FindAsync(sessionId);
        if (session is null)
            return OrchestratorState.Initializing;

        // Check for unprocessed feedback
        var nextIteration = session.CurrentIteration + 1;
        var hasFeedback = await _db.FeedbackBatches
            .AnyAsync(fb => fb.Iteration.SessionId == sessionId 
                         && fb.Iteration.IterationNumber == nextIteration);
        if (hasFeedback)
            return OrchestratorState.Replanning;

        return session.CurrentState;
    }
}
```

### Pattern 6: SessionTools (Database-Backed) + WorkspaceTools (File-Based)

```csharp
using System.ComponentModel;
using Microsoft.Extensions.AI;
using Microsoft.EntityFrameworkCore;

namespace RalphV2.Console.Tools;

/// <summary>
/// Session artifact tools backed by SQLite via EF Core.
/// Agents use these to interact with orchestration state.
/// </summary>
public static class SessionTools
{
    public static AIFunction[] CreateTools(RalphDbContext db, Guid sessionId)
    {
        return
        [
            AIFunctionFactory.Create(
                async () =>
                {
                    var session = await db.Sessions.FindAsync(sessionId);
                    return session?.CurrentPlanContent ?? "No plan exists yet.";
                },
                "GetPlan",
                "Get the current session plan content"
            ),

            AIFunctionFactory.Create(
                async ([Description("Updated plan content")] string content) =>
                {
                    var session = await db.Sessions.FindAsync(sessionId);
                    if (session is null) return "Error: Session not found";
                    session.CurrentPlanContent = content;
                    session.UpdatedAt = DateTime.UtcNow;
                    await db.SaveChangesAsync();
                    return "Plan updated successfully.";
                },
                "UpdatePlan",
                "Update the current session plan with new content"
            ),

            AIFunctionFactory.Create(
                async ([Description("Task ID, e.g., 'task-1'")] string taskId) =>
                {
                    var task = await db.Tasks
                        .Include(t => t.DependsOn)
                        .ThenInclude(d => d.DependsOnTaskItem)
                        .FirstOrDefaultAsync(t => t.SessionId == sessionId && t.TaskId == taskId);
                    if (task is null) return $"Error: Task {taskId} not found.";
                    return System.Text.Json.JsonSerializer.Serialize(new
                    {
                        task.TaskId, task.Title, task.Objective,
                        Status = task.Status.ToString(),
                        DependsOn = task.DependsOn.Select(d => d.DependsOnTaskItem.TaskId)
                    }, new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
                },
                "GetTask",
                "Get a task definition by its ID"
            ),

            AIFunctionFactory.Create(
                async () =>
                {
                    var tasks = await db.Tasks
                        .Where(t => t.SessionId == sessionId)
                        .OrderBy(t => t.WaveNumber).ThenBy(t => t.TaskId)
                        .Select(t => new { t.TaskId, t.Title, Status = t.Status.ToString(), t.WaveNumber })
                        .ToListAsync();
                    var summary = tasks.GroupBy(t => t.Status)
                        .ToDictionary(g => g.Key, g => g.Count());
                    return System.Text.Json.JsonSerializer.Serialize(
                        new { Tasks = tasks, Summary = summary },
                        new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
                },
                "GetProgress",
                "Get a progress summary of all tasks in the session"
            ),

            // ... more tools: CreateTask, SubmitReport, SubmitReview, etc.
            // See database-schema.md for full implementation
        ];
    }
}

/// <summary>
/// Workspace tools for interacting with the actual codebase.
/// Agents use these to read/write source code, run commands, etc.
/// </summary>
public static class WorkspaceTools
{
    public static AIFunction[] CreateTools(string workspacePath)
    {
        return
        [
            AIFunctionFactory.Create(
                ([Description("File path (absolute or relative to workspace)")] string path) =>
                {
                    var fullPath = ResolvePath(workspacePath, path);
                    if (!File.Exists(fullPath))
                        return $"Error: File not found: {fullPath}";
                    return File.ReadAllText(fullPath);
                },
                "ReadFile",
                "Read the contents of a file at the given path"
            ),

            AIFunctionFactory.Create(
                ([Description("File path")] string path,
                 [Description("Content to write")] string content) =>
                {
                    var fullPath = ResolvePath(workspacePath, path);
                    var dir = Path.GetDirectoryName(fullPath);
                    if (dir is not null) Directory.CreateDirectory(dir);
                    File.WriteAllText(fullPath, content);
                    return $"Successfully wrote {content.Length} chars to {fullPath}";
                },
                "WriteFile",
                "Write content to a file, creating directories if needed"
            ),

            AIFunctionFactory.Create(
                ([Description("Directory path")] string path,
                 [Description("Recurse into subdirectories")] bool recursive = false) =>
                {
                    var fullPath = ResolvePath(workspacePath, path);
                    if (!Directory.Exists(fullPath))
                        return $"Error: Directory not found: {fullPath}";
                    var option = recursive
                        ? SearchOption.AllDirectories
                        : SearchOption.TopDirectoryOnly;
                    var entries = Directory.GetFileSystemEntries(fullPath, "*", option)
                        .Select(e => Path.GetRelativePath(fullPath, e) +
                                     (Directory.Exists(e) ? "/" : ""));
                    return string.Join("\n", entries);
                },
                "ListDirectory",
                "List files and directories at the given path"
            ),

            AIFunctionFactory.Create(
                ([Description("Text pattern to search for")] string searchPattern,
                 [Description("Directory to search in")] string directory,
                 [Description("File glob pattern (e.g., *.cs)")] string filePattern = "*") =>
                {
                    var fullDir = ResolvePath(workspacePath, directory);
                    if (!Directory.Exists(fullDir))
                        return $"Error: Directory not found: {fullDir}";
                    var results = new List<string>();
                    foreach (var file in Directory.GetFiles(fullDir, filePattern, SearchOption.AllDirectories))
                    {
                        var lines = File.ReadAllLines(file);
                        for (int i = 0; i < lines.Length; i++)
                        {
                            if (lines[i].Contains(searchPattern, StringComparison.OrdinalIgnoreCase))
                            {
                                var relPath = Path.GetRelativePath(workspacePath, file);
                                results.Add($"{relPath}:{i + 1}: {lines[i].Trim()}");
                            }
                        }
                    }
                    return results.Count > 0
                        ? string.Join("\n", results)
                        : "No matches found.";
                },
                "SearchInFiles",
                "Search for a text pattern across files in a directory"
            )
        ];
    }

    private static string ResolvePath(string workspacePath, string path)
    {
        if (Path.IsPathFullyQualified(path)) return path;
        return Path.GetFullPath(Path.Combine(workspacePath, path));
    }
}
```

### Pattern 7: ConcurrentBatchExecutor

```csharp
namespace RalphV2.Console.Orchestration;

public class ConcurrentBatchExecutor
{
    private readonly int _maxConcurrency;
    private readonly ILogger<ConcurrentBatchExecutor> _logger;

    public ConcurrentBatchExecutor(int maxConcurrency, ILogger<ConcurrentBatchExecutor> logger)
    {
        _maxConcurrency = maxConcurrency;
        _logger = logger;
    }

    public async Task<AgentResult[]> ExecuteAsync(
        IReadOnlyList<string> taskIds,
        Func<string, Task<AgentResult>> executeFunc,
        CancellationToken ct)
    {
        var semaphore = new SemaphoreSlim(_maxConcurrency);
        var results = new AgentResult[taskIds.Count];

        _logger.LogInformation(
            "Executing {Count} tasks with max {Max} concurrent",
            taskIds.Count, _maxConcurrency);

        var tasks = taskIds.Select(async (taskId, index) =>
        {
            await semaphore.WaitAsync(ct);
            try
            {
                _logger.LogInformation("Starting task: {TaskId}", taskId);
                results[index] = await executeFunc(taskId);
                _logger.LogInformation("Completed task: {TaskId} → {Status}", 
                    taskId, results[index].Status);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Task {TaskId} threw exception", taskId);
                results[index] = AgentResult.Failed(AgentRole.Executor, ex.Message);
            }
            finally
            {
                semaphore.Release();
            }
        });

        await Task.WhenAll(tasks);
        return results;
    }
}
```

---

## Getting Started (Quick Start)

### Prerequisites

1. **Copilot CLI** installed and authenticated:
   ```powershell
   copilot --version
   copilot auth login
   ```

2. **.NET 10 SDK**:
   ```powershell
   dotnet --version  # Should be 10.0+
   ```

3. **EF Core CLI tools**:
   ```powershell
   dotnet tool install --global dotnet-ef
   ```

### Create the Project

```powershell
# From workspace root
cd src
dotnet new console -n RalphV2.Console
cd RalphV2.Console

# Add packages
dotnet add package GitHub.Copilot.SDK
dotnet add package Microsoft.Agents.AI.GitHub.Copilot --prerelease
dotnet add package Microsoft.Extensions.AI
dotnet add package Microsoft.EntityFrameworkCore.Sqlite
dotnet add package Microsoft.EntityFrameworkCore.Design
dotnet add package System.CommandLine
dotnet add package Microsoft.Extensions.DependencyInjection
dotnet add package Microsoft.Extensions.Logging.Console
dotnet add package Microsoft.Extensions.Configuration.Json
dotnet add package Microsoft.Extensions.Options.ConfigurationExtensions

# Create initial EF Core migration
dotnet ef migrations add InitialCreate
```

### Verify SDK Connection

```csharp
// Minimal Program.cs to verify Copilot SDK works
using GitHub.Copilot.SDK;
using Microsoft.Agents.AI;

await using var client = new CopilotClient();
await client.StartAsync();

Console.WriteLine($"Client state: {client.State}");
var ping = await client.PingAsync();
Console.WriteLine($"Ping: {ping.Latency}ms");

// Test AIAgent
var agent = client.AsAIAgent(instructions: "You are a helpful assistant.");
var response = await agent.RunAsync("Say 'Ralph V2 is online!' and nothing else.");
Console.WriteLine($"Agent response: {response}");

await client.StopAsync();
```

### Run

```powershell
dotnet run
```

---

## Agent Prompt Strategy

The system prompts for each subagent are derived from the existing `.agent.md` files in `agents/ralph-v2/`. The key adaptations:

### What to Keep

- Persona description
- Workflow steps (step-by-step instructions)
- Artifact file structure expectations
- Report format templates
- Rules & constraints
- Contract (input/output JSON spec)

### What to Change

| Original (VS Code) | Adapted (.NET) |
|---------------------|----------------|
| `read/readFile` tool (for artifacts) → | `GetPlan` / `GetTask` / `GetProgress` AIFunction |
| `read/readFile` tool (for code) → | `ReadFile` AIFunction (WorkspaceTools) |
| `edit/createFile` tool (for artifacts) → | `UpdatePlan` / `CreateTask` / `SubmitReport` AIFunction |
| `edit/createFile` tool (for code) → | `WriteFile` AIFunction (WorkspaceTools) |
| `edit/editFiles` tool → | `WriteFile` AIFunction (WorkspaceTools) |
| `search/grep` tool → | `SearchInFiles` AIFunction (WorkspaceTools) |
| `execute/runInTerminal` tool → | `RunCommand` AIFunction |
| `web/fetch` tool → | `FetchWebPage` AIFunction |
| `brave-search/brave_web_search` → | `WebSearch` AIFunction |
| "Poll signals/inputs/" → | Remove (orchestrator queries DB for signals) |
| "Read progress.md" → | `GetProgress` (queries Tasks table, no file parsing) |
| "Write to questions/*.md" → | `CreateQuestion` / `AnswerQuestion` AIFunction |
| Skills directory resolution → | Remove (not applicable in headless mode) |
| `playwright-cli` references → | Remove (no browser in console app) |

### Prompt Size Optimization

The original `.agent.md` files are quite long (300-400 lines). For the system prompt passed to `AsAIAgent()`:

1. **Strip markdown formatting** not needed for LLM (table borders, horizontal rules)
2. **Remove meta-instructions** about VS Code-specific behavior
3. **Keep workflow logic** and artifact templates verbatim
4. **Add tool name mapping** section explaining available tools
5. **Target**: ~2000-3000 tokens per prompt (vs. ~4000-5000 tokens in original)

---

## Configuration Reference

| Setting | Default | Description |
|---------|---------|-------------|
| `ConnectionStrings:Ralph` | `Data Source=.ralph-sessions/ralph.db` | SQLite connection string |
| `Ralph:SessionsDirectory` | `.ralph-sessions` | Root directory for DB file |
| `Ralph:MaxConcurrency` | `2` | Max parallel subagent invocations |
| `Ralph:DefaultModel` | `gpt-5` | LLM model for all agents |
| `Ralph:CopilotLogLevel` | `warning` | Copilot CLI log level |
| `Ralph:AgentTimeoutSeconds` | `300` | Max time per agent invocation (5 min) |
| `Ralph:StreamingEnabled` | `true` | Stream agent responses to console |
