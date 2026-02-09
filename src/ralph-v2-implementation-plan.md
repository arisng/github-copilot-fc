# Ralph V2 .NET Implementation Plan

> **Objective**: Implement the Ralph V2 multi-agent orchestration workflow as a .NET console application using GitHub Copilot CLI SDK (`GitHub.Copilot.SDK`) and Microsoft Agent Framework (`Microsoft.Agents.AI.GitHub.Copilot`).

---

## Table of Contents

- [Executive Summary](#executive-summary)
- [Goals & Non-Goals](#goals--non-goals)
- [Technology Stack](#technology-stack)
- [Approach](#approach)
- [Key Constraints](#key-constraints)
- [Implementation Phases](#implementation-phases)
- [Risk Assessment](#risk-assessment)
- [Related Documents](#related-documents)

---

## Executive Summary

Ralph V2 is a multi-agent orchestration system with 5 agents (Orchestrator, Planner, Questioner, Executor, Reviewer) that collaborate through a file-based artifact system with structured feedback loops. Today it runs as VS Code Chat Agents using natural-language routing. This plan migrates the workflow to a standalone .NET application where:

- The **Orchestrator** becomes deterministic C# code (state machine, not LLM)
- The **Subagents** become `AIAgent` instances powered by GitHub Copilot via the SDK
- The **Artifact system** is persisted in SQLite via EF Core (replacing file-based artifacts)
- The **State machine** (INITIALIZING → PLANNING → BATCHING → EXECUTING → REVIEWING → COMPLETE/REPLANNING) is implemented in C#

This approach decouples the workflow from VS Code, enables headless execution, programmatic testing, and composability with other .NET systems.

---

## Goals & Non-Goals

### Goals

| ID | Goal |
|----|------|
| G1 | Faithfully replicate Ralph V2 state machine and artifact structure |
| G2 | Use `CopilotClient` + `AsAIAgent()` for subagent LLM interactions |
| G3 | Expose file I/O, search, and shell operations as custom tools via `AIFunctionFactory` |
| G4 | Support configurable concurrency (default: 2 parallel subagents) |
| G5 | Implement Live Signals protocol (STEER/PAUSE/STOP/INFO) |
| G6 | Console app with CLI arguments for session management |
| G7 | Use SQLite as durable persistent memory for all session artifacts |
| G8 | Workspace files (source code, tests) remain on file system; orchestration state in DB |

### Non-Goals

| ID | Non-Goal | Rationale |
|----|----------|-----------|
| NG1 | GUI/Web frontend | Console app is sufficient for prototyping |
| NG2 | MCP server hosting | Tools will be direct `AIFunction`s, not MCP |
| NG3 | Multi-model routing | All agents use the same model initially |
| NG4 | Production-grade error recovery | Prototype-level retry logic only |
| NG5 | VS Code extension compatibility | This is a standalone application |

---

## Technology Stack

| Layer | Technology | Package |
|-------|-----------|---------|
| Runtime | .NET 10 | — |
| Copilot SDK | GitHub Copilot CLI SDK | `GitHub.Copilot.SDK` |
| Agent Framework | Microsoft Agent Framework | `Microsoft.Agents.AI.GitHub.Copilot --prerelease` |
| Tool Definitions | AIFunctionFactory | `Microsoft.Extensions.AI` |
| ORM / Persistence | EF Core + SQLite | `Microsoft.EntityFrameworkCore.Sqlite` |
| CLI Framework | System.CommandLine | `System.CommandLine` |
| Logging | Microsoft.Extensions.Logging | Built-in |
| Concurrency | SemaphoreSlim | Built-in |

---

## Approach

### Architectural Split

```
┌──────────────────────────────────────────────────────┐
│                   Console App (CLI)                  │
│  Commands: new | resume | status | signal | feedback │
└────────────────────┬─────────────────────────────────┘
                     │
┌────────────────────▼─────────────────────────────────┐
│              Orchestrator (C# State Machine)         │
│  • Reads/writes session artifacts via EF Core/SQLite │
│  • Manages state transitions                         │
│  • Controls concurrency (SemaphoreSlim)              │
│  • Polls live signals                                │
└──────┬──────────┬──────────┬──────────┬──────────────┘
       │          │          │          │
  ┌────▼───┐ ┌───▼────┐ ┌───▼────┐ ┌───▼─────┐
  │Planner │ │Question│ │Executor│ │Reviewer │
  │AIAgent │ │AIAgent │ │AIAgent │ │AIAgent  │
  └────┬───┘ └───┬────┘ └───┬────┘ └───┬─────┘
       │         │          │          │
  ┌────▼─────────▼──────────▼──────────▼──────┐
  │         Tool Layer (AIFunctionFactory)           │
  │  Session Tools (DB): GetPlan | GetTask | etc.    │
  │  Workspace Tools: ReadFile | WriteFile | RunCmd  │
  └──────────────────────────────────────────────────┘
       │
  ┌────▼──────────────────────────────────────┐
  │          CopilotClient (Shared)           │
  │  • Single client, multiple sessions       │
  │  • Stdio transport to Copilot CLI         │
  └───────────────────────────────────────────┘
```

### Key Design Decisions

1. **Orchestrator is NOT an LLM agent** — It's deterministic C# that reads file state, decides routing, and invokes subagents. This eliminates LLM hallucination in state transitions.

2. **Subagents ARE LLM agents** — Each gets a system prompt (derived from the `.agent.md` files) and a curated tool set. The LLM decides tool invocations within its scope.

3. **Single CopilotClient, multiple sessions** — One `CopilotClient` manages the connection to Copilot CLI. Each subagent invocation creates (or resumes) an `AIAgent` session.

4. **Tools are scoped per agent** — Planner gets read/write tools. Executor gets read/write/shell tools. Questioner gets read/write/search tools. Reviewer gets read/write/shell tools.

5. **SQLite database is the durable persistence layer** — Agents communicate through typed DB operations (GetPlan, GetTask, SubmitReport, etc.) via Session Tools. The orchestrator accesses the DB directly via EF Core.

---

## Key Constraints

| Constraint | Impact | Mitigation |
|-----------|--------|------------|
| Max 2 concurrent subagents | Rate limiting from Copilot API | `SemaphoreSlim(2)` throttle |
| Copilot CLI must be installed | Runtime dependency | Validate on startup, clear error message |
| SDK is technical preview | Breaking changes possible | Pin package versions, isolate SDK surface |
| Stdio transport | Single-process communication | Use default transport, avoid TCP complexity |
| Tool timeout 30s default | Long file operations may timeout | Increase timeout for shell tools |

---

## Implementation Phases

### Phase 1: Foundation (Wave 1)
> Project setup, EF Core + SQLite, core infrastructure, CopilotClient lifecycle

- Create .NET 10 console project with dependencies (EF Core, SQLite)
- Implement `RalphDbContext` with all entity classes and configuration
- Implement `SessionRepository` (typed data access over EF Core)
- Implement `CopilotClientManager` (client lifecycle)
- Write basic CLI with `new` and `resume` commands

### Phase 2: Tool Layer (Wave 2)
> Custom tools via AIFunctionFactory

- Implement `SessionTools` (GetPlan, UpdatePlan, GetTask, CreateTask, SubmitReport, SubmitReview, GetProgress, etc.)
- Implement `WorkspaceTools` (ReadFile, WriteFile, ListDirectory, SearchInFile)
- Implement `ShellTools` (RunCommand with permission scoping)
- Implement `WebTools` (WebSearch, FetchPage)
- Create `ToolSetFactory` that assembles tool sets per agent role

### Phase 3: Agent Factory (Wave 3)
> Subagent creation with system prompts and tools

- Implement `AgentFactory` creating `AIAgent` via `CopilotClient.AsAIAgent()`
- Extract system prompts from `.agent.md` files (or embed inline)
- Map agent roles to tool sets
- Implement `AgentInvoker` with timeout, error handling, response parsing

### Phase 4: State Machine (Wave 4)
> Orchestrator core logic

- Implement `OrchestratorStateMachine` with all states
- Implement state transitions with validation
- Implement wave computation (topological sort of task dependencies)
- Implement batching logic with `SemaphoreSlim(2)` concurrency
- Implement progress tracking (parse/update progress.md)

### Phase 5: Live Signals & Feedback (Wave 5)
> Signal polling and feedback loop

- Implement `SignalPoller` (file system polling in signals/inputs/)
- Implement signal handlers (STEER, PAUSE, STOP, INFO)
- Implement feedback detection (scan iterations/N+1/feedbacks/)
- Implement REPLANNING state transition

### Phase 6: Integration & Polish (Wave 6)
> End-to-end flow, CLI commands, error handling

- Wire all components together
- Implement `status` and `signal` CLI commands
- Implement `feedback` CLI command (create feedback directory structure)
- Add logging throughout
- Manual end-to-end testing

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-----------|--------|------------|
| Copilot SDK breaking changes | Medium | High | Pin versions, abstract SDK surface |
| LLM not following agent prompt faithfully | Medium | Medium | Strong system prompts, tool-result validation |
| Tool execution timeout | Low | Medium | Configurable timeouts, retry logic |
| Rate limiting with 2 concurrent agents | Low | Medium | Sequential fallback mode |
| Large artifact files exceeding context | Medium | Medium | Summarization tools, chunked reads |

---

## Related Documents

| Document | Description |
|----------|-------------|
| [Architecture](architecture.md) | Component design, state machine, tool catalog, data flows |
| [Database Schema](database-schema.md) | EF Core entity definitions, DbContext, tool-to-repository mapping |
| [Task Breakdown](task-breakdown.md) | Detailed implementation tasks with dependencies |
| [Prototype Scaffold](prototype-scaffold.md) | Project structure, NuGet packages, key code patterns |
| [agents/ralph-v2/](../agents/ralph-v2/) | Original Ralph V2 agent definitions (source of truth for prompts) |
