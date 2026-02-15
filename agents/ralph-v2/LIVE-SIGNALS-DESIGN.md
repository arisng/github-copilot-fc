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
type: STEER      # STEER | PAUSE | ABORT | INFO | APPROVE | SKIP
target: ALL      # ALL | Ralph-Executor | Ralph-Orchestrator
message: "Don't use the 'foo' library, it's deprecated. Use 'bar' instead."
iteration: 1     # Optional. Forward-compatibility for iteration-scoped signals (e.g., APPROVE/SKIP).
                  # Orchestrator ignores if absent; validates against current iteration if present.
```

> **Forward-compatibility note**: Signal filenames currently use second-level timestamps (`signal.<YYMMDD-HHmmss>.yaml`), which is sufficient for human-generated signals. If automated signal generation is introduced in the future (e.g., hooks emitting signals), use millisecond timestamps or random suffixes (e.g., `signal.<YYMMDD-HHmmss>-<ms>.yaml` or `signal.<YYMMDD-HHmmss>-<random4>.yaml`) to avoid collisions.

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

3. **Target-Aware Routing** (Orchestrator):
   After peeking at a signal file, the Orchestrator applies target-aware routing before consuming:
   1. **Peek**: Read signal file to get `type`, `target`, `message`.
   2. **Check target**: If `target == ALL` or `target == Ralph-Orchestrator` → consume normally (move to `processed/`, act on it).
   3. **Route to subagent**: If `target != ALL` and `target != Ralph-Orchestrator` (e.g., `target: Ralph-Executor`) → buffer the signal for delivery at the next targeted subagent invocation. Move the file to `signals/processed/` (Orchestrator still owns the mailbox), but route the message context to the targeted subagent instead of acting on it.
   4. **Subagent direct polling**: When subagents poll `signals/inputs/` directly (for universal signals — see §4), they apply the same target check: only consume signals where `target == ALL` or `target` matches the current subagent identity.

   <!-- Cross-ref: The orchestrator's Poll-Signals routine implements this peek-check-route flow. See ralph-v2.agent.md §State Machine. -->

### 3. Signal Types

#### Overview

| Type        | Category         | Semantics                | Polled By                          |
| ----------- | ---------------- | ------------------------ | ---------------------------------- |
| **STEER**   | Universal        | Trajectory Correction    | Orchestrator + Subagents (direct)  |
| **INFO**    | Universal        | Context Injection        | Orchestrator + Subagents (direct)  |
| **PAUSE**   | Universal        | Temporary Halt           | Orchestrator + Subagents (direct)  |
| **ABORT**   | Universal        | Permanent Halt           | Orchestrator + Subagents (direct)  |
| **APPROVE** | State-specific   | Knowledge Promotion      | Orchestrator only (KNOWLEDGE_APPROVAL) |
| **SKIP**    | State-specific   | Knowledge Bypass         | Orchestrator only (KNOWLEDGE_APPROVAL) |

#### 3.1 STEER — Trajectory Correction

**Semantics**: Re-route the agent's workflow path based on the signal's `message`. The agent adjusts its current approach, loops back to earlier steps, skips steps, or escalates to the Orchestrator.

**Agent Behavior**: Inject `message` into current context. Evaluate impact on in-progress work and apply the appropriate response from the decision tree below.

**Mid-Execution Decision Tree** (for subagents, especially Executor at Step 3.5):

```
STEER signal received during implementation
│
├─ (a) Work Invalidated
│     Signal contradicts already-implemented work
│     (e.g., "use library X" when library Y was already integrated)
│     → Restart implementation step (Step 3) with updated context
│     → Note in report: "Restarted due to STEER: <summary>"
│
├─ (b) Additive / Non-conflicting
│     Signal adds constraints or context without invalidating current work
│     (e.g., "also handle edge case Z" or "target Firefox only")
│     → Adjust in-place and continue from current position
│     → Append STEER context to active constraints
│
└─ (c) Scope Change
      Signal fundamentally changes the task's objective
      (e.g., "don't build feature A, build feature B instead")
      → Return {status: "blocked", blockers: ["STEER scope change: <summary>"]}
      → Escalate to Orchestrator for task redefinition
      → Do NOT silently discard or redefine task scope
```

**Decision Criteria**: The agent determines which branch to take by comparing the STEER message against:
1. Files already modified — does the signal invalidate those changes?
2. Success criteria — does the signal change what "done" means?
3. Task objective — does the signal redefine the task itself?

#### 3.2 INFO — Context Injection

**Semantics**: Enrich the agent's context with additional facts, constraints, or background information. The agent's workflow path does **not** change — it continues on its current trajectory with enhanced knowledge.

**Agent Behavior**: Add `message` to known facts/constraints. Non-blocking — the agent acknowledges the information and continues. INFO signals never trigger restarts, pauses, or escalation.

**Examples**:
- "The deployment target is Azure, not AWS."
- "The team prefers tabs over spaces in config files."
- "The `foo` module was deprecated last week."

**Distinction from STEER**: INFO tells the agent something new; STEER tells the agent to change direction. If the information implies the agent should change what it's doing, use STEER instead.

#### 3.3 PAUSE — Temporary Halt

**Semantics**: Temporarily suspend execution with the intent to resume later. The agent preserves its current state and waits for the human to clear the pause or provide further instructions.

**Agent Behavior**:
1. Complete the current atomic operation (e.g., finish writing a file, complete a test run) — do NOT leave artifacts in a half-written state.
2. Save progress: update `iterations/<N>/progress.md` with current status and note "Paused by signal."
3. Return `{status: "paused"}` to the Orchestrator.
4. On resume, the Orchestrator re-invokes the subagent with optional updated context from the PAUSE signal's `message` field (e.g., "Resume after reviewing the API spec changes").

**Distinction from ABORT**: PAUSE is temporary — the session will be resumed. ABORT is permanent — the session terminates.

#### 3.4 ABORT — Permanent Halt (was STOP)

**Semantics**: Permanently terminate the current operation. The session ends with cleanup. No resume is expected — if the human wants to continue later, they start a new session or iteration.

**Agent Behavior**: Execute the **ABORT Cleanup Checklist** before terminating:

| Step | Action | Owner |
|------|--------|-------|
| 1 | Mark all in-progress tasks `[/]` as `[F]` with reason `"Aborted by signal"` in `iterations/<N>/progress.md` | Subagent (if mid-task) or Orchestrator |
| 2 | Update session `metadata.yaml`: set `orchestrator.state: COMPLETE` and add `status: aborted` | Orchestrator |
| 3 | Update `iterations/<N>/metadata.yaml`: record `completed_at` timestamp | Orchestrator |
| 4 | Do **NOT** revert file changes — preserve all modifications for debugging and future reference | All agents |

**After cleanup**: Return `{status: "blocked", blockers: ["Aborted by signal"]}`.

**Rationale for no-revert (Step 4)**: Reverting changes destroys evidence needed for debugging and replanning. The human can inspect the partial work, understand what was done, and decide what to keep or discard in a future session.

#### 3.5 APPROVE — Knowledge Promotion

**Semantics**: Trigger promotion of staged knowledge from `iterations/<N>/knowledge/` to `.docs/`. This signal is **state-specific** — it is only consumed in the Orchestrator's `KNOWLEDGE_APPROVAL` state.

**Agent Behavior**: Orchestrator receives APPROVE → invokes Librarian in PROMOTE mode → Librarian moves staged files to `.docs/` with appropriate metadata.

**`message` field**: Optional reviewer comments (e.g., "Looks good, promote all" or "Promote only the API reference, not the tutorial").

**Polling**: Orchestrator only. Subagents do not poll for APPROVE signals.

#### 3.6 SKIP — Knowledge Bypass

**Semantics**: Bypass knowledge promotion; the session completes without promoting staged knowledge. This signal is **state-specific** — it is only consumed in the Orchestrator's `KNOWLEDGE_APPROVAL` state.

**Agent Behavior**: Orchestrator receives SKIP → transitions to `COMPLETE` state without invoking Librarian promotion. Staged knowledge is **preserved** in `iterations/<N>/knowledge/` (not deleted) but not promoted to `.docs/`.

**`message` field**: Reason for skipping (e.g., "Need more review time" or "Knowledge is too specific to this task").

**Polling**: Orchestrator only. Subagents do not poll for SKIP signals.

**Carry-forward behavior**: If neither APPROVE nor SKIP is received within the KNOWLEDGE_APPROVAL timeout (or the iteration ends without a signal), staged knowledge is automatically carried forward to the next iteration with a `carried_from` marker for the Librarian to reconcile.

### 4. Agent Integration — Hybrid Polling Model

Subagents have a **dual role** in signal handling, resolving the previous design inconsistency where subagents were classified as "context consumers" but actually polled `signals/inputs/` directly in their workflow code:

| Classification         | Signals                      | Description                                                                                           |
| ---------------------- | ---------------------------- | ----------------------------------------------------------------------------------------------------- |
| **Direct poller**      | STEER, INFO, PAUSE, ABORT    | Subagents poll `signals/inputs/` at step boundaries during long-running tasks. These are **universal signals** — time-sensitive and relevant regardless of orchestrator state. |
| **Context consumer**   | APPROVE, SKIP                | Subagents receive these via Orchestrator invocation context. These are **state-specific signals** — only meaningful in `KNOWLEDGE_APPROVAL` state. |
| **Primary poller**     | All types                    | Orchestrator — owns `signals/inputs/`, runs Poll-Signals routine at state boundaries, dispatches state-specific signals to subagents. |

#### A. Orchestrator (Ralph-v2)

**Role**: Primary signal router, flow controller, and state-specific signal consumer.

**Checkpoints**:
1. **State Boundaries**: Poll signals between every state transition.
2. **Before Invoking Subagent**: Check signals. If `ABORT` → execute cleanup checklist (§3.4) and exit. If `PAUSE` → suspend and wait. If `STEER/INFO` → pass message to subagent invocation context.
3. **Loop Boundaries**: Inside `EXECUTING_BATCH` loop (between tasks). Inside `REVIEWING_BATCH` loop (between reviews).
4. **KNOWLEDGE_APPROVAL**: Poll for `APPROVE` and `SKIP` signals (these are not forwarded — consumed directly).

**Target-Aware Routing**: The Orchestrator checks the `target` field before consuming (see §2.3). Signals targeting a specific subagent are buffered and delivered at the next invocation of that subagent.

#### B. Subagents (Executor, Planner, Questioner, Reviewer, Librarian)

**Role**: Direct pollers for universal signals; context consumers for state-specific signals.

**Direct Polling Checkpoints** (for universal signals: STEER, PAUSE, ABORT, INFO):
1. **Initialization (Step 0)**: Poll `signals/inputs/` before starting work. If `ABORT` → return `blocked`. If `PAUSE` → save state and return `paused`. If `STEER/INFO` → ingest into context.
2. **Step Boundaries**: Between major workflow steps (e.g., Executor between Read Context → Mark WIP → Implement → Verify). If a universal signal is found, handle it before proceeding to the next step.
3. **Mid-Execution (Step 3.5 — Executor only)**: Poll during long-running implementation. Apply STEER decision tree (§3.1) if a STEER signal is found.

**Context-Consumed Signals** (APPROVE, SKIP):
- Subagents do NOT poll for these. They are irrelevant outside `KNOWLEDGE_APPROVAL` state.
- The Orchestrator handles these directly and invokes the Librarian with the appropriate mode.

**Why hybrid?** When the Orchestrator invokes a long-running subagent (e.g., Executor on a complex task), the Orchestrator is BLOCKED waiting for the return. During this time, no orchestrator-level polling occurs. Direct polling by subagents ensures time-sensitive signals (STEER, PAUSE, ABORT) are handled within the subagent's execution, not delayed until the subagent returns.

> **Invariant — Temporal Demarcation**: The Orchestrator and subagents never poll `signals/inputs/` simultaneously. The Orchestrator polls at **state boundaries** (when no subagent is running). Subagents poll at **step boundaries** (when the Orchestrator is blocked). This temporal separation prevents duplicate signal consumption without requiring locks or coordination protocols.

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

- **Ralph-v2 (Orchestrator)**: Add "Poll Signals" step in State Machine key loops (list, move, read). Implement target-aware routing (§2.3). Add ABORT cleanup checklist execution (§3.4).
- **Subagents**: Implement direct polling for universal signals (STEER, PAUSE, ABORT, INFO) at step boundaries. Retain context-consumer pattern for APPROVE/SKIP.

### Phase 3: "Hot Steering" (Advanced)

- Implement the STEER mid-execution decision tree (§3.1) in the Executor's Step 3.5.
- Allow agents to restart, adjust, or escalate based on STEER signal impact analysis.
