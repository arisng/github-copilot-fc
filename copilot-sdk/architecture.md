# Ralph V2 .NET Architecture

> Component design, state machine, agent mapping, tool catalog, and data flow diagrams.

---

## Table of Contents

- [Component Overview](#component-overview)
- [Agent Mapping: VS Code → .NET](#agent-mapping-vs-code--net)
- [State Machine Design](#state-machine-design)
- [Tool Catalog](#tool-catalog)
- [Data Flow](#data-flow)
- [Session Artifact Structure](#session-artifact-structure)
- [CopilotClient Lifecycle](#copilotclient-lifecycle)
- [Concurrency Model](#concurrency-model)

---

## Component Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         RalphV2.Console                            │
│                                                                     │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────────────────┐  │
│  │ CLI Commands │  │ Orchestrator │  │    CopilotClientManager   │  │
│  │ (CommandLine)│──▶ StateMachine │──▶ CopilotClient.AsAIAgent() │  │
│  └─────────────┘  └──────┬───────┘  └───────────────────────────┘  │
│                          │                                          │
│  ┌───────────────────────▼────────────────────────────────────────┐ │
│  │                    Service Layer                               │ │
│  │  ┌──────────────────┐ ┌─────────────┐ ┌────────────────────┐  │ │
│  │  │SessionRepository │ │AgentFactory │ │   AgentInvoker     │  │ │
│  │  │(EF Core/SQLite)  │ │(Prompt+Tool)│ │(Send+Parse Resp.)  │  │ │
│  │  └──────────────────┘ └─────────────┘ └────────────────────┘  │ │
│  │  ┌──────────────────┐ ┌─────────────┐ ┌────────────────────┐  │ │
│  │  │ RalphDbContext   │ │SignalPoller │ │   WaveComputer     │  │ │
│  │  │ (EF Core)        │ │(DB Query)   │ │(Topo-sort tasks)   │  │ │
│  │  └──────────────────┘ └─────────────┘ └────────────────────┘  │ │
│  └───────────────────────────────────────────────────────────────┘ │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │                     Tool Layer                                │ │
│  │  SessionTools (DB) | WorkspaceTools (File) | ShellTools       │ │
│  │  WebTools | UtilTools                                         │ │
│  │  (AIFunctionFactory.Create → AIFunction[])                    │ │
│  └───────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component                  | Responsibility                                         | LLM-Powered? |
| -------------------------- | ------------------------------------------------------ | :----------: |
| `CLI Commands`             | Parse CLI args, dispatch to orchestrator               |      No      |
| `OrchestratorStateMachine` | State transitions, routing decisions, progress updates |      No      |
| `CopilotClientManager`     | CopilotClient lifecycle (start/stop/sessions)          |      No      |
| `AgentFactory`             | Create `AIAgent` with system prompt + tools per role   |      No      |
| `AgentInvoker`             | Send prompts to agents, parse structured responses     |      No      |
| `RalphDbContext`           | EF Core context for all session entities               |      No      |
| `SessionRepository`        | Typed data access layer over EF Core                   |      No      |
| `SignalPoller`             | Query unprocessed signals from DB                      |      No      |
| `WaveComputer`             | Topological sort of task dependencies into waves       |      No      |
| `Planner AIAgent`          | Plan creation, task breakdown, replanning              |   **Yes**    |
| `Questioner AIAgent`       | Question generation, research, feedback analysis       |   **Yes**    |
| `Executor AIAgent`         | Task implementation, coding, testing                   |   **Yes**    |
| `Reviewer AIAgent`         | Quality validation, criteria checking                  |   **Yes**    |

---

## Agent Mapping: VS Code → .NET

### Current VS Code Architecture
```
User → VS Code Chat → Ralph-v2 (Chat Agent) → runSubagent() → Subagent (Chat Agent)
         ↕                    ↕                                      ↕
      VS Code Tools      File System                           VS Code Tools
```

### Proposed .NET Architecture
```
User → Console CLI → Orchestrator (C# Code) → AIAgent.RunAsync() → CopilotClient
         ↕                   ↕                        ↕                    ↕
      CLI Args          File System            AIFunction Tools      Copilot CLI
```

### Agent Configuration Mapping

| Agent          | VS Code Tools                                         | .NET Tools (AIFunction)                                                                                      | System Prompt Source           |
| -------------- | ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ | ------------------------------ |
| **Planner**    | `read`, `edit`, `search`, `web/fetch`                 | `SessionTools.GetPlan/UpdatePlan/CreateTask`, `WorkspaceTools.ReadFile`, `UtilTools.*`                       | `ralph-v2-planner.agent.md`    |
| **Questioner** | `read`, `edit`, `search`, `web/fetch`, `brave-search` | `SessionTools.GetPlan/CreateQuestion/AnswerQuestion`, `WorkspaceTools.ReadFile`, `WebTools.*`, `UtilTools.*` | `ralph-v2-questioner.agent.md` |
| **Executor**   | `read`, `edit`, `search`, `execute/*`, `web/fetch`    | `SessionTools.GetTask/SubmitReport/GetProgress`, `WorkspaceTools.*`, `ShellTools.*`, `WebTools.*`            | `ralph-v2-executor.agent.md`   |
| **Reviewer**   | `read`, `edit`, `search`, `execute/*`, `web/fetch`    | `SessionTools.GetTask/SubmitReview/GetProgress`, `WorkspaceTools.*`, `ShellTools.*`, `UtilTools.*`           | `ralph-v2-reviewer.agent.md`   |

### Prompt Strategy

Each subagent's system prompt is derived from its `.agent.md` file with adaptations:

1. **Strip VS Code-specific references** (e.g., `runSubagent`, VS Code tool names)
2. **Map tool references** to AIFunction names (e.g., `ReadFile(tasks/...)` → `GetTask(taskId)`)
3. **Add .NET-specific instructions** (e.g., "Return JSON response to the orchestrator")
4. **Replace file I/O with Session Tool calls** (e.g., "Use GetPlan to read plan, UpdatePlan to write")
5. **Preserve workflow logic** (the step-by-step execution workflow)

Example system prompt transformation:
```
# VS Code Version
"Read task definition from tasks/<TASK_ID>.md"
→ Use read/readFile tool

# .NET Version  
"Get task definition for <TASK_ID>"
→ Use GetTask tool with taskId parameter
```

---

## State Machine Design

### States

```csharp
public enum OrchestratorState
{
    Initializing,     // No session exists, invoke Planner(INITIALIZE)
    Planning,         // Execute planning tasks (brainstorm, research, breakdown)
    Batching,         // Compute next wave from task dependencies
    ExecutingBatch,   // Execute current wave's tasks
    ReviewingBatch,   // Review completed tasks
    SessionReview,    // Final holistic review  
    Complete,         // All tasks done
    Replanning,       // Feedback-driven replanning (iteration >= 2)
    AwaitingFeedback, // Waiting for human feedback on failed tasks
    Paused,           // Paused by live signal
    Stopped           // Stopped by live signal
}
```

### Transition Table

```
┌──────────────────┬─────────────────────┬────────────────────────────────────┐
│ From State       │ To State            │ Trigger                            │
├──────────────────┼─────────────────────┼────────────────────────────────────┤
│ (entry)          │ Initializing        │ No session directory exists        │
│ (entry)          │ <restored state>    │ metadata.yaml exists               │
│ Initializing     │ Planning            │ Planner(INITIALIZE) completes      │
│ Planning         │ Planning            │ More planning tasks remain         │
│ Planning         │ Batching            │ All planning tasks [x]             │
│ Batching         │ ExecutingBatch      │ Wave with pending tasks found      │
│ Batching         │ SessionReview       │ No more waves                      │
│ ExecutingBatch   │ ReviewingBatch      │ All wave tasks executed            │
│ ReviewingBatch   │ Batching            │ All reviews complete               │
│ SessionReview    │ Complete            │ Review passes                      │
│ Complete         │ AwaitingFeedback    │ Some tasks [F]                     │
│ AwaitingFeedback │ Replanning          │ Feedback files detected            │
│ Replanning       │ Replanning          │ More replanning tasks remain       │
│ Replanning       │ Batching            │ All replanning tasks [x]           │
│ Any              │ Paused              │ PAUSE signal received              │
│ Paused           │ <previous state>    │ Resume signal or new user message  │
│ Any              │ Stopped             │ STOP signal received               │
└──────────────────┴─────────────────────┴────────────────────────────────────┘
```

### State Machine Core Logic

```csharp
public class OrchestratorStateMachine
{
    private OrchestratorState _state;
    private readonly RalphDbContext _db;
    private readonly AgentInvoker _invoker;
    private readonly SemaphoreSlim _concurrency = new(2); // Max 2 parallel
    
    public async Task RunAsync(Guid sessionId, CancellationToken ct)
    {
        while (_state is not (OrchestratorState.Complete 
                           or OrchestratorState.Stopped 
                           or OrchestratorState.AwaitingFeedback))
        {
            // Poll signals from DB before each state transition
            var signal = await _db.Signals
                .Where(s => s.SessionId == sessionId && !s.IsProcessed)
                .OrderBy(s => s.CreatedAt)
                .FirstOrDefaultAsync(ct);
            
            _state = _state switch
            {
                OrchestratorState.Initializing   => await HandleInitializingAsync(ct),
                OrchestratorState.Planning        => await HandlePlanningAsync(ct),
                OrchestratorState.Batching        => await HandleBatchingAsync(ct),
                OrchestratorState.ExecutingBatch   => await HandleExecutingAsync(ct),
                OrchestratorState.ReviewingBatch   => await HandleReviewingAsync(ct),
                OrchestratorState.SessionReview    => await HandleSessionReviewAsync(ct),
                OrchestratorState.Replanning       => await HandleReplanningAsync(ct),
                OrchestratorState.Paused           => await HandlePausedAsync(ct),
                _ => throw new InvalidOperationException($"Unexpected state: {_state}")
            };
            
            // Persist state after each transition
            var session = await _db.Sessions.FindAsync([sessionId], ct);
            session!.CurrentState = _state;
            session.UpdatedAt = DateTime.UtcNow;
            await _db.SaveChangesAsync(ct);
        }
    }
}
```

---

## Tool Catalog

### Session Tools (Database-Backed)

These tools interact with session artifacts stored in SQLite via EF Core. Used by agents for orchestration state.

| Tool Name          | Parameters                                 | Returns               | Used By           |
| ------------------ | ------------------------------------------ | --------------------- | ----------------- |
| `GetPlan`          | `sessionId`                                | Plan content string   | All agents        |
| `UpdatePlan`       | `sessionId, content`                       | Success confirmation  | Planner           |
| `GetTask`          | `sessionId, taskId`                        | Task JSON             | All agents        |
| `CreateTask`       | `sessionId, taskId, title, objective, ...` | Success confirmation  | Planner           |
| `GetProgress`      | `sessionId`                                | Progress summary JSON | All agents        |
| `UpdateTaskStatus` | `taskId, status`                           | Success confirmation  | Orchestrator only |
| `SubmitReport`     | `taskId, report, attemptNumber`            | Success confirmation  | Executor          |
| `SubmitReview`     | `taskId, review, verdict`                  | Success confirmation  | Reviewer          |
| `GetQuestions`     | `sessionId, category`                      | Questions JSON        | All agents        |
| `CreateQuestion`   | `sessionId, questionId, text, ...`         | Success confirmation  | Questioner        |
| `AnswerQuestion`   | `questionId, answer, ...`                  | Success confirmation  | Questioner        |
| `GetTimestamp`     | —                                          | ISO 8601 timestamp    | All agents        |

> See [Database Schema](database-schema.md) for entity definitions and full implementation.

### Workspace Tools (File-System)

These tools interact with the actual workspace/codebase. Unchanged from file-based operations.

| Tool Name       | Parameters                           | Returns                | Used By            |
| --------------- | ------------------------------------ | ---------------------- | ------------------ |
| `ReadFile`      | `path: string`                       | File content as string | Executor, Reviewer |
| `WriteFile`     | `path: string, content: string`      | Success confirmation   | Executor           |
| `ListDirectory` | `path: string, recursive: bool`      | Directory listing      | Executor, Reviewer |
| `SearchInFiles` | `pattern: string, directory: string` | Matching lines         | Executor, Reviewer |
| `FileExists`    | `path: string`                       | Boolean result         | Executor, Reviewer |

### ShellTools

| Tool Name    | Parameters                                          | Returns            | Used By            |
| ------------ | --------------------------------------------------- | ------------------ | ------------------ |
| `RunCommand` | `command: string, workingDir: string, timeout: int` | stdout + exit code | Executor, Reviewer |

### WebTools

| Tool Name      | Parameters                       | Returns        | Used By    |
| -------------- | -------------------------------- | -------------- | ---------- |
| `WebSearch`    | `query: string, maxResults: int` | Search results | Questioner |
| `FetchWebPage` | `url: string, query: string`     | Page content   | Questioner |

### UtilTools

| Tool Name      | Parameters | Returns            | Used By    |
| -------------- | ---------- | ------------------ | ---------- |
| `GetTimestamp` | —          | ISO 8601 timestamp | All agents |

### Tool Implementation Pattern

Session tools use EF Core for database access:

```csharp
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
            // ... more session tools (see database-schema.md)
        ];
    }
}
```

Workspace tools remain file-based:

```csharp
public static class WorkspaceTools
{
    [Description("Read the contents of a file at the given path")]
    public static async Task<string> ReadFile(
        [Description("Absolute or workspace-relative file path")] string path)
    {
        if (!File.Exists(path))
            return $"Error: File not found: {path}";
        return await File.ReadAllTextAsync(path);
    }
    
    [Description("Write content to a file, creating directories if needed")]
    public static async Task<string> WriteFile(
        [Description("Absolute or workspace-relative file path")] string path,
        [Description("Content to write to the file")] string content)
    {
        var dir = Path.GetDirectoryName(path);
        if (dir != null) Directory.CreateDirectory(dir);
        await File.WriteAllTextAsync(path, content);
        return $"Successfully wrote {content.Length} characters to {path}";
    }
}

// Registration:
var sessionTools = SessionTools.CreateTools(db, sessionId);
var workspaceTools = new[]
{
    AIFunctionFactory.Create(WorkspaceTools.ReadFile),
    AIFunctionFactory.Create(WorkspaceTools.WriteFile),
    // ... more workspace tools
};
var allTools = sessionTools.Concat(workspaceTools).ToArray();
```

---

## Data Flow

### Happy Path: New Session

```
User: "ralph new --request 'Build a REST API for todo items'"

1. CLI → Orchestrator: STATE = INITIALIZING
   │
2. Orchestrator → AgentFactory: Create Planner AIAgent
   │  SystemPrompt: planner.agent.md (INITIALIZE mode)
   │  Tools: FileTools.*, UtilTools.*
   │
3. Orchestrator → Planner AIAgent:
   │  "Initialize session SESSION_ID
   │   USER_REQUEST: Build a REST API for todo items
   │   ITERATION: 1"
   │
4. Planner AIAgent (LLM) → [Tool Calls]:
   │  UpdatePlan("Goal: Build REST API...")
   │  CreateTask("task-1", "Setup project", ...)
   │  CreateTask("task-2", "Design API models", ...)
   │
5. Orchestrator: STATE = PLANNING
   │
6. Orchestrator → Questioner AIAgent (brainstorm):
   │  "Generate questions for category: technical..."
   │  → CreateQuestion("Q-TECH-001", "What framework?", ...)
   │
7. Orchestrator → Questioner AIAgent (research):
   │  "Research unanswered questions..."
   │  → WebSearch("REST API best practices .NET")
   │  → AnswerQuestion("Q-TECH-001", "Use ASP.NET Core...")
   │
8. Orchestrator → Planner AIAgent (TASK_BREAKDOWN):
   │  "Break plan into tasks..."
   │  → CreateTask("task-1", ..., dependsOn: [])
   │  → CreateTask("task-2", ..., dependsOn: [])
   │  → CreateTask("task-3", ..., dependsOn: ["task-1"])
   │
9. Orchestrator: STATE = BATCHING
   │  Wave 1: [task-1, task-2] (parallel, no deps)
   │  Wave 2: [task-3] (depends on task-1)
   │
10. Orchestrator: STATE = EXECUTING_BATCH (Wave 1)
    │  ┌─ SemaphoreSlim(2) ─┐
    │  │ Executor(task-1)    │  ← parallel
    │  │ Executor(task-2)    │  ← parallel
    │  └─────────────────────┘
    │
11. Orchestrator: STATE = REVIEWING_BATCH
    │  ┌─ SemaphoreSlim(2) ─┐
    │  │ Reviewer(task-1)    │  ← parallel
    │  │ Reviewer(task-2)    │  ← parallel
    │  └─────────────────────┘
    │
12. Orchestrator: STATE = BATCHING → EXECUTING (Wave 2) → REVIEWING
    │
13. Orchestrator: STATE = SESSION_REVIEW → COMPLETE
```

### Feedback Loop Flow

```
User: "ralph feedback --session todo-api --files bug-report.md,screenshot.png"

1. CLI → Create FeedbackBatch + FeedbackItems in DB
   │  Read structured feedback, store attachments as blobs
   │
2. User: "ralph resume --session todo-api"
   │
3. Orchestrator: Detect feedback in DB → STATE = REPLANNING, ITERATION = 2
   │
4. Orchestrator → Questioner (feedback-analysis):
   │  "Analyze feedback, generate improvement questions"
   │  → Uses GetFeedback, CreateQuestion tools
   │
5. Orchestrator → Questioner (research):
   │  "Research solutions to feedback issues"
   │
6. Orchestrator → Planner (UPDATE):
   │  "Update plan based on feedback"
   │  → Snapshot current plan to PlanSnapshots
   │  → UpdatePlan with revised content
   │
7. Orchestrator → Planner (REBREAKDOWN):
   │  "Update failed tasks, create new tasks if needed"
   │  → CreateTask for new tasks
   │  → Orchestrator resets [F] → [ ] via DB update
   │
8. Orchestrator: STATE = BATCHING → ... (normal flow)
```

---

## Session Persistence

All orchestration state is stored in a single SQLite database:

```
.ralph-sessions/
└── ralph.db              ← Single EF Core SQLite database for all sessions
```

### Database Tables (summary)

| Table                 | Purpose                                            |
| --------------------- | -------------------------------------------------- |
| `Sessions`            | Session metadata, current plan content, state      |
| `Iterations`          | Per-iteration state and timing                     |
| `PlanSnapshots`       | Immutable plan copies per iteration                |
| `Tasks`               | Task definitions with status                       |
| `TaskDependencies`    | Dependency graph (many-to-many)                    |
| `TaskReports`         | Implementation reports (Part 1) + reviews (Part 2) |
| `Questions`           | Q&A per category with answers                      |
| `FeedbackBatches`     | Grouped feedback per iteration                     |
| `FeedbackItems`       | Individual issues within a batch                   |
| `FeedbackAttachments` | Binary attachments (logs, screenshots)             |
| `ReplanningDeltas`    | Replanning summary per iteration                   |
| `Signals`             | Live signals (STEER/PAUSE/STOP/INFO)               |
| `AgentInvocations`    | Audit log of all agent calls                       |

> See [Database Schema](database-schema.md) for full entity definitions, DbContext, and migration strategy.

### What Remains on File System

The workspace/codebase being worked on stays on disk:

```
<project-root>/               ← Workspace that Executor/Reviewer operate on
├── src/
├── tests/
└── ...                        ← Actual source code, configs, build output
```

---

## CopilotClient Lifecycle

```csharp
// Startup: Create and start client once
await using var client = new CopilotClient(new CopilotClientOptions
{
    LogLevel = "warning",
    AutoStart = true,
    AutoRestart = true
});
await client.StartAsync();

// Per-invocation: Create AIAgent with role-specific config
AIAgent plannerAgent = client.AsAIAgent(
    instructions: plannerSystemPrompt,
    tools: plannerTools
);

// Execute: Send task and get response
string response = await plannerAgent.RunAsync(taskPrompt);

// Streaming alternative (for long tasks):
await foreach (var update in plannerAgent.RunStreamingAsync(taskPrompt))
{
    Console.Write(update);
}

// Shutdown: Dispose handles cleanup
// (CopilotClient implements IAsyncDisposable)
```

### Session Reuse Strategy

- **Within a wave**: Each agent invocation creates a fresh `AIAgent` (new session per invocation), with a scoped `RalphDbContext`
- **Across waves**: No session reuse — each task invocation is independent
- **Rationale**: Agents should not carry context between different tasks; their context comes from Session Tools querying the DB

---

## Concurrency Model

```csharp
public class ConcurrentBatchExecutor
{
    private readonly SemaphoreSlim _semaphore;
    
    public ConcurrentBatchExecutor(int maxConcurrency = 2)
    {
        _semaphore = new SemaphoreSlim(maxConcurrency);
    }
    
    public async Task<AgentResult[]> ExecuteBatchAsync(
        IReadOnlyList<TaskDefinition> tasks,
        Func<TaskDefinition, Task<AgentResult>> executeFunc,
        CancellationToken ct)
    {
        var results = new AgentResult[tasks.Count];
        var taskList = tasks.Select(async (task, index) =>
        {
            await _semaphore.WaitAsync(ct);
            try
            {
                results[index] = await executeFunc(task);
            }
            finally
            {
                _semaphore.Release();
            }
        });
        
        await Task.WhenAll(taskList);
        return results;
    }
}
```

### Concurrency Rules

1. **Max 2 concurrent subagents** (configurable via `--max-parallel` CLI flag)
2. **No two reviewers on the same task** (enforced by task assignment)
3. **Planning tasks are sequential** (brainstorm → research → breakdown)
4. **Replanning tasks are sequential** (same as planning)
5. **Execution and review are parallelizable** (within wave constraints)
