# Ralph V2 .NET — Task Breakdown

> Detailed implementation tasks organized by wave with dependencies and acceptance criteria.

---

## Overview

| Phase              | Wave | Tasks  |      Parallelizable       | Est. Effort |
| ------------------ | ---- | ------ | :-----------------------: | ----------- |
| Foundation         | 1    | 5      | 3 parallel, 2 sequential  | Day 1-2     |
| Tool Layer         | 2    | 4      |       All parallel        | Day 2-3     |
| Agent Factory      | 3    | 4      | 2 parallel + 2 sequential | Day 3-4     |
| State Machine      | 4    | 5      | 2 parallel + 3 sequential | Day 4-6     |
| Signals & Feedback | 5    | 4      | 2 parallel + 2 sequential | Day 6-7     |
| Integration        | 6    | 4      | 2 parallel + 2 sequential | Day 7-8     |
| **Total**          |      | **26** |                           | **~8 days** |

---

## Wave 1: Foundation

### task-1: Create .NET Console Project

**Type**: Sequential (must be first)
**Files**:
- `src/RalphV2.Console/RalphV2.Console.csproj`
- `src/RalphV2.Console/Program.cs`
- `src/RalphV2.Console/appsettings.json`

**Objective**: Scaffold a .NET 10 console project with all NuGet dependencies.

**Success Criteria**:
- [ ] Project builds successfully with `dotnet build`
- [ ] Target framework: `net10.0`
- [ ] All NuGet packages referenced: `GitHub.Copilot.SDK`, `Microsoft.Agents.AI.GitHub.Copilot`, `Microsoft.Extensions.AI`, `Microsoft.EntityFrameworkCore.Sqlite`, `Microsoft.EntityFrameworkCore.Design`, `System.CommandLine`
- [ ] `Program.cs` has minimal CLI entry point using `System.CommandLine`
- [ ] `appsettings.json` has configuration for model, concurrency, log level, and `ConnectionStrings:Ralph`

**Dependencies**: None

---

### task-2: Implement Configuration Model

**Type**: Parallelizable (after task-1)
**Files**:
- `src/RalphV2.Console/Configuration/RalphOptions.cs`
- `src/RalphV2.Console/Configuration/AgentOptions.cs`

**Objective**: Define strongly-typed configuration classes for the application.

**Success Criteria**:
- [ ] `RalphOptions` has: `SessionsDirectory`, `MaxConcurrency`, `DefaultModel`, `CopilotLogLevel`
- [ ] `AgentOptions` has: `Name`, `SystemPromptPath`, `Model`, `TimeoutSeconds`
- [ ] Loadable from `appsettings.json` via `IConfiguration`

**Dependencies**: `task-1`

---

### task-3: Implement RalphDbContext and Entities

**Type**: Parallelizable (after task-1)
**Files**:
- `src/RalphV2.Console/Data/RalphDbContext.cs`
- `src/RalphV2.Console/Data/Entities/*.cs`
- `src/RalphV2.Console/Data/Enums/*.cs`

**Objective**: EF Core DbContext with all entity classes for session artifact persistence.

**Success Criteria**:
- [ ] `RalphDbContext` with `DbSet<>` for all 13 entities: `Sessions`, `Iterations`, `PlanSnapshots`, `Tasks`, `TaskDependencies`, `TaskReports`, `Questions`, `FeedbackBatches`, `FeedbackItems`, `FeedbackAttachments`, `ReplanningDeltas`, `Signals`, `AgentInvocations`
- [ ] All entities defined per database-schema.md
- [ ] All enums: `OrchestratorState`, `TaskItemStatus`, `TaskItemType`, `AgentRole`, `QuestionCategory`, `ReviewVerdict`, `SignalType`, `FeedbackSeverity`, `InvocationStatus`, `ConfidenceLevel`, `QuestionPriority`, `QuestionStatus`
- [ ] `OnModelCreating` with indexes, unique constraints, FK relationships
- [ ] Enum-to-int conversions configured
- [ ] Initial EF Core migration created and applies successfully
- [ ] SQLite connection string configurable via `appsettings.json`

**Dependencies**: `task-1`

---

### task-4: Implement SessionRepository

**Type**: Parallelizable (after task-3)
**Files**:
- `src/RalphV2.Console/Data/Repositories/ISessionRepository.cs`
- `src/RalphV2.Console/Data/Repositories/SessionRepository.cs`

**Objective**: Typed data access layer over EF Core for orchestrator use.

**Success Criteria**:
- [ ] `CreateSessionAsync(sessionId, userRequest)` → creates Session + first Iteration
- [ ] `GetSessionAsync(sessionId)` → returns Session with related data
- [ ] `TransitionStateAsync(sessionId, newState)` → atomic state update
- [ ] `ComputeProgressAsync(sessionId)` → returns task status summary (replaces progress.md parsing)
- [ ] `GetTasksByWaveAsync(sessionId, waveNumber)` → returns tasks in a wave
- [ ] `PollSignalAsync(sessionId)` → returns and marks oldest unprocessed signal
- [ ] `DetectFeedbackAsync(sessionId, iteration)` → checks for unprocessed feedback
- [ ] All methods use async EF Core queries
- [ ] Scoped lifetime in DI

**Dependencies**: `task-3`

---

### task-5: Implement SessionTools (DB-Backed Agent Tools)

**Type**: Sequential (after task-4)
**Files**:
- `src/RalphV2.Console/Tools/SessionTools.cs`

**Objective**: AIFunction-compatible tools for agents to interact with session artifacts via EF Core.

**Success Criteria**:
- [ ] `GetPlan(sessionId)` → returns current plan content from DB
- [ ] `UpdatePlan(sessionId, content)` → updates plan content in DB
- [ ] `GetTask(sessionId, taskId)` → returns task definition as JSON
- [ ] `CreateTask(sessionId, taskId, title, objective, ...)` → inserts new TaskItem + TaskDependencies
- [ ] `GetProgress(sessionId)` → returns task status summary (computed from Tasks table)
- [ ] `SubmitReport(taskId, report, attemptNumber)` → creates TaskReport
- [ ] `SubmitReview(taskId, review, verdict)` → updates TaskReport with review + verdict
- [ ] `GetQuestions(sessionId, category)` → returns questions JSON
- [ ] `CreateQuestion(sessionId, questionId, text, ...)` → inserts new Question
- [ ] `AnswerQuestion(questionId, answer, ...)` → updates Question with answer
- [ ] All methods have `[Description]` attributes for LLM tool schema
- [ ] Returns error strings (not exceptions) for LLM consumption
- [ ] Each tool set is scoped to a `RalphDbContext` and `sessionId`

**Dependencies**: `task-4`

---

## Wave 2: Tool Layer

### task-6: Implement WorkspaceTools (File-Based)

**Type**: Parallelizable
**Files**:
- `src/RalphV2.Console/Tools/WorkspaceTools.cs`

**Objective**: AIFunction-compatible file operations for agents to interact with the actual workspace/codebase.

**Success Criteria**:
- [ ] `ReadFile(path)` — reads actual source code files
- [ ] `WriteFile(path, content)` — writes source code with auto-directory creation
- [ ] `ListDirectory(path, recursive)` — returns formatted directory listing
- [ ] `FileExists(path)` — returns boolean
- [ ] `SearchInFiles(searchPattern, directory, filePattern)` — grep-like search
- [ ] All methods have `[Description]` attributes for LLM tool schema
- [ ] Path resolution: supports both absolute and workspace-relative paths
- [ ] Returns error strings (not exceptions) for LLM consumption
- [ ] These tools operate on the workspace filesystem, NOT on session artifacts

**Dependencies**: `task-1`

---

### task-7: Implement ShellTools

**Type**: Parallelizable
**Files**:
- `src/RalphV2.Console/Tools/ShellTools.cs`

**Objective**: AIFunction-compatible command execution for subagents.

**Success Criteria**:
- [ ] `RunCommand(command, workingDirectory, timeoutSeconds)` — executes shell command
- [ ] Returns stdout, stderr, and exit code as formatted string
- [ ] Timeout support with configurable default (60s)
- [ ] Working directory defaults to session path
- [ ] Captures and returns both stdout and stderr
- [ ] Safe command execution (no arbitrary admin commands)
- [ ] `[Description]` attributes on all parameters

**Dependencies**: `task-1`

---

### task-8: Implement WebTools

**Type**: Parallelizable
**Files**:
- `src/RalphV2.Console/Tools/WebTools.cs`

**Objective**: AIFunction-compatible web search and fetch for Questioner.

**Success Criteria**:
- [ ] `WebSearch(query, maxResults)` — performs web search (via Copilot or Brave API)
- [ ] `FetchWebPage(url, query)` — fetches and extracts main content from URL
- [ ] Returns structured text results for LLM consumption
- [ ] Handles HTTP errors gracefully (returns error string)
- [ ] `[Description]` attributes on all parameters

**Dependencies**: `task-1`

---

### task-9: Implement UtilTools

**Type**: Parallelizable
**Files**:
- `src/RalphV2.Console/Tools/UtilTools.cs`

**Objective**: AIFunction-compatible utility operations.

**Success Criteria**:
- [ ] `GetTimestamp()` — returns ISO 8601 timestamp
- [ ] `[Description]` attributes on all parameters

**Dependencies**: `task-1`

---

## Wave 3: Agent Factory

### task-10: Implement CopilotClientManager

**Type**: Parallelizable
**Files**:
- `src/RalphV2.Console/Copilot/CopilotClientManager.cs`
- `src/RalphV2.Console/Copilot/ICopilotClientManager.cs`

**Objective**: Manage CopilotClient lifecycle (singleton pattern).

**Success Criteria**:
- [ ] Creates `CopilotClient` with configurable options (log level, auto-restart)
- [ ] `StartAsync()` / `StopAsync()` lifecycle
- [ ] `PingAsync()` health check
- [ ] Implements `IAsyncDisposable`
- [ ] Validates Copilot CLI availability on startup
- [ ] Exposes `CopilotClient` for agent creation

**Dependencies**: `task-2`

---

### task-11: Implement ToolSetFactory

**Type**: Parallelizable
**Files**:
- `src/RalphV2.Console/Agents/ToolSetFactory.cs`

**Objective**: Assemble role-specific tool arrays from Session Tools + Workspace Tools.

**Success Criteria**:
- [ ] `CreateToolSet(AgentRole, Guid sessionId, RalphDbContext db, string workspacePath)` returns `AIFunction[]`
- [ ] Planner: SessionTools (GetPlan, UpdatePlan, CreateTask, GetProgress) + WorkspaceTools.ReadFile + UtilTools
- [ ] Questioner: SessionTools (GetPlan, CreateQuestion, AnswerQuestion, GetProgress) + WorkspaceTools.ReadFile + WebTools + UtilTools
- [ ] Executor: SessionTools (GetTask, SubmitReport, GetProgress) + WorkspaceTools.* + ShellTools + WebTools
- [ ] Reviewer: SessionTools (GetTask, SubmitReview, GetProgress) + WorkspaceTools.* + ShellTools + UtilTools
- [ ] Each invocation gets a scoped RalphDbContext

**Dependencies**: `task-5`, `task-6`, `task-7`, `task-8`, `task-9`

---

### task-12: Implement AgentFactory

**Type**: Sequential (after task-10, task-11)
**Files**:
- `src/RalphV2.Console/Agents/AgentFactory.cs`
- `src/RalphV2.Console/Agents/IAgentFactory.cs`

**Objective**: Create role-specific `AIAgent` instances via `CopilotClient.AsAIAgent()`.

**Success Criteria**:
- [ ] `CreateAgentAsync(AgentRole, SessionContext)` returns configured `AIAgent`
- [ ] System prompts loaded from embedded resources or configuration
- [ ] Tools assembled via `ToolSetFactory`
- [ ] Model configurable per agent (default to global setting)
- [ ] Logging of agent creation events

**Dependencies**: `task-10`, `task-11`

---

### task-13: Implement AgentInvoker

**Type**: Sequential (after task-12)
**Files**:
- `src/RalphV2.Console/Agents/AgentInvoker.cs`
- `src/RalphV2.Console/Agents/IAgentInvoker.cs`
- `src/RalphV2.Console/Agents/AgentResult.cs`

**Objective**: Send prompts to agents and parse structured responses.

**Success Criteria**:
- [ ] `InvokeAsync(AgentRole, prompt, SessionContext, CancellationToken)` → `AgentResult`
- [ ] Supports both `RunAsync` (simple) and `RunStreamingAsync` (with console output)
- [ ] Timeout handling with configurable duration
- [ ] Parses JSON response from agent output when structured response expected
- [ ] Graceful error handling (returns error result, not exception)
- [ ] Logs agent invocation start/end with duration

**Dependencies**: `task-12`

---

## Wave 4: State Machine

### task-14: Implement WaveComputer

**Type**: Parallelizable
**Files**:
- `src/RalphV2.Console/Orchestration/WaveComputer.cs`

**Objective**: Compute execution waves from task dependency graph.

**Success Criteria**:
- [ ] `ComputeWaves(IReadOnlyList<TaskDefinition>)` → `List<Wave>`
- [ ] Each `Wave` contains list of task IDs that can run in parallel
- [ ] Respects `depends_on` field from task definitions
- [ ] Topological sort with cycle detection
- [ ] Wave ordering: tasks with no deps first, then dependent tasks
- [ ] Handles cancelled tasks (skip, don't block dependents)

**Dependencies**: `task-4`

---

### task-15: Implement ConcurrentBatchExecutor

**Type**: Parallelizable
**Files**:
- `src/RalphV2.Console/Orchestration/ConcurrentBatchExecutor.cs`

**Objective**: Execute a batch of tasks with bounded concurrency.

**Success Criteria**:
- [ ] `ExecuteBatchAsync(tasks, executeFunc, maxConcurrency, ct)` → `AgentResult[]`
- [ ] Uses `SemaphoreSlim` for concurrency control
- [ ] Default max concurrency: 2
- [ ] Handles individual task failures without aborting batch
- [ ] Reports progress as tasks complete
- [ ] Cancellation token support

**Dependencies**: `task-13`

---

### task-16: Implement Planning State Handlers

**Type**: Sequential
**Files**:
- `src/RalphV2.Console/Orchestration/Handlers/InitializingHandler.cs`
- `src/RalphV2.Console/Orchestration/Handlers/PlanningHandler.cs`
- `src/RalphV2.Console/Orchestration/Handlers/IStateHandler.cs`

**Objective**: Implement INITIALIZING and PLANNING state handlers.

**Success Criteria**:
- [ ] `InitializingHandler`:
  - Creates Session + Iteration in DB
  - Invokes Planner agent with INITIALIZE mode
  - Verifies plan content saved to DB via agent's `UpdatePlan` tool call
  - Returns `OrchestratorState.Planning`
- [ ] `PlanningHandler`:
  - Queries DB for next planning task (plan-brainstorm, plan-research, plan-breakdown)
  - Routes brainstorm/research → Questioner, breakdown → Planner
  - Returns `OrchestratorState.Planning` or `OrchestratorState.Batching`
- [ ] Both handlers update task status in DB after agent completion

**Dependencies**: `task-5`, `task-13`

---

### task-17: Implement Execution State Handlers

**Type**: Sequential (after task-16)
**Files**:
- `src/RalphV2.Console/Orchestration/Handlers/BatchingHandler.cs`
- `src/RalphV2.Console/Orchestration/Handlers/ExecutingBatchHandler.cs`
- `src/RalphV2.Console/Orchestration/Handlers/ReviewingBatchHandler.cs`

**Objective**: Implement BATCHING, EXECUTING_BATCH, and REVIEWING_BATCH handlers.

**Success Criteria**:
- [ ] `BatchingHandler`:
  - Uses `WaveComputer` with tasks from DB to determine current wave
  - Returns `ExecutingBatch` if wave found, `SessionReview` if none
- [ ] `ExecutingBatchHandler`:
  - Uses `ConcurrentBatchExecutor` with max 2 parallel
  - Invokes Executor agent for each task in wave
  - Updates task status in DB (NotStarted → InProgress → ReviewPending or Failed)
- [ ] `ReviewingBatchHandler`:
  - Queries DB for tasks with `ReviewPending` status
  - Uses `ConcurrentBatchExecutor` with max 2 parallel
  - Invokes Reviewer agent for each ReviewPending task
  - Updates task status in DB (ReviewPending → Completed or Failed)
  - Returns `Batching` to check for next wave

**Dependencies**: `task-14`, `task-15`, `task-16`

---

### task-18: Implement OrchestratorStateMachine

**Type**: Sequential (after task-17)
**Files**:
- `src/RalphV2.Console/Orchestration/OrchestratorStateMachine.cs`

**Objective**: Main orchestration loop tying all handlers together.

**Success Criteria**:
- [ ] Constructor takes all handler dependencies + `RalphDbContext`
- [ ] `RunAsync(Guid sessionId, string? userRequest, CancellationToken)` main loop
- [ ] Routes to correct handler based on current state
- [ ] Persists state to `Sessions.CurrentState` via DB after each transition
- [ ] Logs each state transition
- [ ] Handles `Complete` and `AwaitingFeedback` terminal states
- [ ] Session resolution: loads existing state from DB if session exists
- [ ] Polls signals from `Signals` table before each state transition

**Dependencies**: `task-16`, `task-17`

---

## Wave 5: Signals & Feedback

### task-19: Implement SignalPoller

**Type**: Parallelizable
**Files**:
- `src/RalphV2.Console/Signals/SignalPoller.cs`
- `src/RalphV2.Console/Signals/ISignalPoller.cs`

**Objective**: Implement signal polling from SQLite database.

**Success Criteria**:
- [ ] `PollAsync(sessionId)` queries `Signals` table for unprocessed signals
- [ ] Processes oldest signal first (ordered by `CreatedAt`)
- [ ] Marks signal as processed (`IsProcessed = true`, `ProcessedAt = DateTime.UtcNow`)
- [ ] Returns typed `Signal` entity (null if no pending signals)
- [ ] Atomic update via EF Core (handles concurrent access)

**Dependencies**: `task-3`

---

### task-20: Implement Signal Handlers

**Type**: Parallelizable
**Files**:
- `src/RalphV2.Console/Signals/SignalHandler.cs`

**Objective**: Process signals and affect orchestrator state.

**Success Criteria**:
- [ ] `HandleAsync(Signal)` modifies orchestrator state or context
- [ ] STEER: Updates context notes, logs message
- [ ] PAUSE: Sets state to `Paused`, blocks until resume
- [ ] STOP: Sets state to `Stopped`, triggers graceful shutdown
- [ ] INFO: Logs message only
- [ ] `SignalCommand` CLI creates new Signal rows in DB for user-initiated signals

**Dependencies**: `task-19`

---

### task-21: Implement FeedbackDetector

**Type**: Sequential (after task-19)
**Files**:
- `src/RalphV2.Console/Feedback/FeedbackDetector.cs`

**Objective**: Detect new feedback in DB and trigger replanning.

**Success Criteria**:
- [ ] `DetectFeedbackAsync(sessionId, currentIteration)` → `bool`
- [ ] Queries `FeedbackBatches` for unprocessed feedback in next iteration
- [ ] Returns false if no unprocessed feedback exists
- [ ] `FeedbackCommand` CLI creates `FeedbackBatch` + `FeedbackItem` + `FeedbackAttachment` rows

**Dependencies**: `task-3`

---

### task-22: Implement ReplanningHandler

**Type**: Sequential (after task-21)
**Files**:
- `src/RalphV2.Console/Orchestration/Handlers/ReplanningHandler.cs`

**Objective**: Implement REPLANNING state handler with full re-brainstorm workflow.

**Success Criteria**:
- [ ] Tracks replanning sub-tasks: rebrainstorm, reresearch, update, rebreakdown
- [ ] Routes to Questioner (feedback-analysis), Questioner (research), Planner (UPDATE), Planner (REBREAKDOWN)
- [ ] Agent reads feedback from DB via `GetFeedback` session tool
- [ ] Resets failed tasks (`[F]` → `[ ]`) via DB status update after rebreakdown
- [ ] Creates `PlanSnapshot` and `ReplanningDelta` in DB
- [ ] Returns `Batching` when all replanning tasks complete

**Dependencies**: `task-16`, `task-21`

---

## Wave 6: Integration & Polish

### task-23: Wire CLI Commands

**Type**: Parallelizable  
**Files**:
- `src/RalphV2.Console/Commands/NewCommand.cs`
- `src/RalphV2.Console/Commands/ResumeCommand.cs`
- `src/RalphV2.Console/Commands/StatusCommand.cs`
- `src/RalphV2.Console/Commands/SignalCommand.cs`
- `src/RalphV2.Console/Commands/FeedbackCommand.cs`
- `src/RalphV2.Console/Program.cs` (update)

**Objective**: Implement all CLI commands using System.CommandLine.

**Success Criteria**:
- [ ] `ralph new --request "..." [--session-id <id>] [--model <model>] [--max-parallel <n>]`
- [ ] `ralph resume --session <id>`
- [ ] `ralph status --session <id>` (prints progress.md summary)
- [ ] `ralph signal --session <id> --type <STEER|PAUSE|STOP|INFO> --message "..."`
- [ ] `ralph feedback --session <id> --files <file1,file2,...>`
- [ ] All commands validate session existence
- [ ] Help text for all commands and options

**Dependencies**: `task-18`

---

### task-24: Implement SessionReviewHandler and CompleteHandler

**Type**: Parallelizable
**Files**:
- `src/RalphV2.Console/Orchestration/Handlers/SessionReviewHandler.cs`
- `src/RalphV2.Console/Orchestration/Handlers/CompleteHandler.cs`

**Objective**: Implement SESSION_REVIEW and COMPLETE state handlers.

**Success Criteria**:
- [ ] `SessionReviewHandler`:
  - Invokes Reviewer in SESSION_REVIEW mode
  - Stores review content in `Iteration.ReviewContent` in DB
  - Returns `Complete`
- [ ] `CompleteHandler`:
  - Queries DB for task statuses
  - All tasks Completed or Cancelled → success
  - Any tasks Failed → `AwaitingFeedback`
  - Updates `Session.CompletedAt` and `Iteration.CompletedAt` in DB

**Dependencies**: `task-17`

---

### task-25: Implement DI Container and Composition Root

**Type**: Sequential (after task-23, task-24)
**Files**:
- `src/RalphV2.Console/Startup.cs`
- `src/RalphV2.Console/Program.cs` (final update)

**Objective**: Wire all components with dependency injection.

**Success Criteria**:
- [ ] `Microsoft.Extensions.DependencyInjection` used for service registration
- [ ] `RalphDbContext` registered with `AddDbContext` (scoped lifetime)
- [ ] Auto-migration on startup via `db.Database.MigrateAsync()`
- [ ] All interfaces registered with correct lifetimes
- [ ] `ILogger` configured via `Microsoft.Extensions.Logging`
- [ ] Configuration loaded from `appsettings.json` + CLI overrides
- [ ] `CopilotClientManager` registered as singleton
- [ ] Clean startup/shutdown sequence

**Dependencies**: `task-23`, `task-24`

---

### task-26: End-to-End Smoke Test

**Type**: Sequential (after task-25)
**Files**:
- `src/RalphV2.Console/Tests/SmokeTest.md` (manual test plan)
- `src/RalphV2.Console/Tests/test-scenario.ps1` (optional automation)

**Objective**: Manual end-to-end test of the full workflow.

**Success Criteria**:
- [ ] `ralph new --request "Create a hello world script"` completes through all states
- [ ] Session directory created with correct structure
- [ ] Plan, tasks, reports generated
- [ ] Progress.md reflects correct status markers
- [ ] `ralph status` shows accurate summary
- [ ] `ralph signal --type STOP` gracefully stops execution
- [ ] Feedback loop smoke test (if time permits)

**Dependencies**: `task-25`

---

## Dependency Graph

```
Wave 1:  task-1 ──┬── task-2 ──── task-10
                  ├── task-3 ──┬─ task-4 ── task-5 ──┐
                  │           │                       │── task-11 ── task-12 ── task-13
                  │           │                       │
Wave 2:           │           │   task-6 ────────────┘
                  │           │   task-7 ────────────┘
                  │           │   task-8 ────────────┘
                  │           │   task-9 ────────────┘
                  │           │
Wave 3:           │           task-14
                  │           task-15
                  │
Wave 4:           task-16 ── task-17 ── task-18
                  task-19 ── task-20
                  task-21 ── task-22

Wave 6:           task-23 ─┐
                  task-24 ─┤── task-25 ── task-26
```

> **Key change from v1**: `task-3` (RalphDbContext) replaced ArtifactManager; `task-4` (SessionRepository) replaced Session State Models; `task-5` (SessionTools) replaced ProgressParser. All file-based artifact parsing is eliminated in favor of EF Core queries.
