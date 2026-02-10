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
│   ├── signal.<TIMESTAMP>.yaml  # e.g., signal.20260208-143000.yaml
│   └── ...
└── processed/                   # Agents move handled files here
    ├── <TIMESTAMP>.yaml         # Archived signal
    └── ...
```

**Signal File Schema (Input):**
```yaml
# signal.20260208-143000.yaml
type: STEER   # STEER | PAUSE | STOP | INFO
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
   - Agent picks a file (FIFO by timestamp).
   - Agent **moves** file to `signals/processed/` (Atomic OS operation).
   - If move fails (another agent took it), skip and try next.
   - Processing happens on the moved file (exclusive ownership).

### 3. Signal Types

| Type      | Semantics             | Agent Behavior                                                        |
| --------- | --------------------- | --------------------------------------------------------------------- |
| **STEER** | Trajectory Correction | Inject `message` into current context/prompt. Adjust immediate plan.  |
| **INFO**  | Context Injection     | Add `message` to known facts/constraints. Non-blocking.               |
| **PAUSE** | Flow Control          | Suspend execution. Wait for User to clear/resume.                     |
| **STOP**  | Abort                 | Gracefully terminate current operation. Mark task/session as stopped. |

### 3. Agent Integration

#### A. Orchestrator (Ralph-v2)

**Role**: Global signal router and flow controller.
**Checkpoints**:
1. **Before Invoking Subagent**: Check signals. If `STOP/PAUSE`, active immediately. If `STEER/INFO`, pass to subagent context.
2. **Loop Boundaries**: Inside `EXECUTING_BATCH` loop (between tasks).

#### B. Subagents (Executor/Planner/Questioner)

**Role**: Context consumers.
**Checkpoints**:
1. **Initialization**: Read `pending` signals. If `target` matches, ingest and acknowledge.
2. **Step Boundaries**: If agent has multi-step logic (e.g., Planner passes, Executor TDD cycle), check signals between steps.

### 5. Workflow Example

1. **Scenario**: Ralph-Executor is running tests (Step 3).
2. **User Input**: User notices the agent is writing tests for the wrong browser.
3. **Signal Injection**: User runs command or creates file:
   `signals/inputs/signal.20260208-143000.yaml`
   ```yaml
   type: STEER
   message: "Target Firefox only, not Chrome."
   ```
4. **Agent Checkpoint**: Executor finishes "Step 3: Implementation", checks `signals/inputs/`.
5. **Consumption**:
   - Executor finds the file.
   - **Atomically Moves** it to `signals/processed/signal.20260208-143000.executed.yaml`.
   - Adds "Target Firefox only" to critical context.
   - **Correction**: Re-runs implementation step or filters verification to Firefox.

## Implementation Plan

### Phase 1: Artifact Support

- Define `signals/` directory structure.
- Create `Inject-Signal` skill (PowerShell script) to create timestamped files safely.

### Phase 2: Agent Updates

- **Ralph-v2**: Add "Poll Signals" step in State Machine key loops (list, move, read).
- **Subagents**: Add "Poll Signals" logic at step boundaries.


### Phase 3: "Hot Steering" (Advanced)

- Allow agents to "restart" current step if a `STEER` signal invalidates previous work immediately.
