# Design: Live Feedback Implementation (Ralph v2)

## Problem Statement

Current "Feedback Loops" in Ralph v2 are **iteration-based** (batch). Users can only influence the session during `REPLANNING` (between iterations) or when a task fails. 
Users need a way to **intervene asynchronously** ("live") during potentially long-running states like `EXECUTING_BATCH` or `PLANNING` to steer direction, inject new constraints, or pause execution without waiting for failure.

## Proposed Solution: The "Live Signals" Protocol (Mailbox Pattern)

To avoid concurrency conflicts (e.g., User writing while Agent consumes, or multiple Agents consuming simultaneously), we use a **Directory-Based Mailbox Pattern** instead of a single file.

### 1. Artifacts: `signals/` Directory

Located at the session root: `.ralph-sessions/<SESSION_ID>/signals/`.

**Structure:**
```
signals/
├── inputs/                      # User drops signal files here
│   ├── signal.<TIMESTAMP>.yaml  # e.g., signal.260208-143000.yaml
│   └── ...
└── processed/                   # Agents move handled files here
    ├── <TIMESTAMP>.yaml         # Archived signal
    └── ...
```

**Signal File Schema (Input):**
```yaml
# signal.260208-143000.yaml
type: STEER   # STEER | PAUSE | STOP | INFO | APPROVE | SKIP
target: ALL   # ALL | Ralph-Executor | Ralph-Orchestrator
message: "Don't use the 'foo' library, it's deprecated. Use 'bar' instead."
```

**Processed File Schema (Output adds metadata):**
Agents append handling info when moving to `processed/`:
```yaml
# Original content...
# ...
handling_metadata:
  handled_by: Ralph-v2-Executor
  handled_at: 2026-02-08T14:30:05Z
  action_taken: "Updated context to prefer 'bar' library"
```

### 2. Concurrency Strategy

1. **Wait-Free Insertion**: Users create unique files with timestamps. No conflict with other signals.
2. **Atomic Consumption**:
   - Agent lists files in `signals/inputs/`.
   - Agent picks the oldest file (FIFO by timestamp).
   - Agent **reads** the file content to determine the signal type (peek).
   - If the signal type is recognized for the current context, agent **moves** the file to `signals/processed/` (atomic OS operation). If move fails (another agent took it), skip and try next.
   - If the signal type is not recognized in the current context, agent leaves the file in `inputs/` for state-specific consumption.
   - Processing happens after the move (exclusive ownership).

   <!-- Cross-ref: The orchestrator's Poll-Signals routine implements this peek-check-move flow. See ralph-v2.agent.md §State Machine. -->

### 3. Signal Types

| Type        | Semantics             | Agent Behavior                                                                                                                                                                                                         |
| ----------- | --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **STEER**   | Trajectory Correction | Inject `message` into current context/prompt. Adjust immediate plan.                                                                                                                                                   |
| **INFO**    | Context Injection     | Add `message` to known facts/constraints. Non-blocking.                                                                                                                                                                |
| **PAUSE**   | Flow Control          | Suspend execution. Wait for User to clear/resume.                                                                                                                                                                      |
| **STOP**    | Abort                 | Gracefully terminate current operation. Mark task/session as stopped.                                                                                                                                                  |
| **APPROVE** | Knowledge Promotion   | Triggers knowledge promotion from staging (`iterations/<N>/knowledge/`) to `.docs/`. Consumed in KNOWLEDGE_APPROVAL orchestrator state. `message`: optional reviewer comments.                                         |
| **SKIP**    | Knowledge Bypass      | Bypasses knowledge promotion; session completes without promoting staged knowledge. Consumed in KNOWLEDGE_APPROVAL orchestrator state. `message`: reason for skipping. Staged knowledge is preserved but not promoted. |

### 4. Agent Integration

#### A. Orchestrator (Ralph-v2)

**Role**: Global signal router and flow controller.
**Checkpoints**:
1. **Before Invoking Subagent**: Check signals. If `STOP/PAUSE`, active immediately. If `STEER/INFO`, pass to subagent context.
2. **Loop Boundaries**: Inside `EXECUTING_BATCH` loop (between tasks).

#### B. Subagents

**Role**: Context consumers. Subagents receive signal context from the orchestrator; they do not poll `signals/inputs/` directly.

| Classification       | Description                                                                                                             |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| **Direct poller**    | Orchestrator — owns `signals/inputs/`, runs Poll-Signals routine, dispatches to subagents                               |
| **Context consumer** | All subagents (Executor, Planner, Questioner, Reviewer, Librarian) — receive signal context via orchestrator invocation |

**Checkpoints** (for Context consumer subagents):
1. **Initialization**: Read orchestrator-provided signal context. If relevant, ingest and acknowledge.
2. **Step Boundaries**: If agent has multi-step logic (e.g., Planner passes, Executor TDD cycle), check signal context between steps.

### 5. Workflow Example

1. **Scenario**: Ralph-v2 orchestrator is in `EXECUTING_BATCH`, invoking Ralph-v2-Executor for task-3 (running tests).
2. **User Input**: User notices the agent is writing tests for the wrong browser.
3. **Signal Injection**: User creates a signal file:
   `signals/inputs/signal.20260208-143000.yaml`
   ```yaml
   type: STEER
   message: "Target Firefox only, not Chrome."
   ```
4. **Orchestrator Checkpoint**: Between task invocations, the orchestrator runs Poll-Signals.
   - Orchestrator reads the signal (peek), recognizes `STEER` as a standard type.
   - Orchestrator atomically moves the file to `signals/processed/`.
   - Orchestrator logs: "Steering signal received: Target Firefox only, not Chrome."
5. **Context Passing**: Orchestrator passes the STEER message to the next Executor invocation context.
6. **Executor Adjustment**: Executor receives the steering context, adjusts test targets to Firefox only.

## Implementation Plan

### Phase 1: Artifact Support

- Define `signals/` directory structure.
- Create `Inject-Signal` skill (PowerShell script) to create timestamped files safely.

### Phase 2: Agent Updates

- **Ralph-v2**: Add "Poll Signals" step in State Machine key loops (list, move, read).
- **Subagents**: Receive orchestrator-provided signal context at invocation; no direct polling.


### Phase 3: "Hot Steering" (Advanced)

- Allow agents to "restart" current step if a `STEER` signal invalidates previous work immediately.
