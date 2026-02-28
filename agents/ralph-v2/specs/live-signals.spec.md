---
title: "Live Signals Protocol"
status: implemented
version: "2.10.0"
created_at: 2026-02-28T21:15:21+07:00
updated_at: 2026-02-28T21:15:21+07:00
---

# Live Signals Protocol

This specification defines the Live Signals protocol for Ralph v2 — a directory-based mailbox pattern enabling asynchronous human intervention during agent execution. It combines the design rationale (problem statement, signal types, concurrency strategy, agent integration) with the implementation map (checkpoint tables per agent, common polling routine).

---

## Design

### 1. Problem Statement

Current "Feedback Loops" in Ralph v2 are **iteration-based** (batch). Users can only influence the session during `REPLANNING` (between iterations) or when a task fails.
Users need a way to **intervene asynchronously** ("live") during potentially long-running states like `EXECUTING_BATCH` or `PLANNING` to steer direction, inject new constraints, or pause execution without waiting for failure.

### 2. Proposed Solution: The "Live Signals" Protocol (Mailbox Pattern)

To avoid concurrency conflicts (e.g., User writing while Agent consumes, or multiple Agents consuming simultaneously), we use a **Directory-Based Mailbox Pattern** instead of a single file.

#### 2.1 Artifacts: `signals/` Directory

Located at the session root: `.ralph-sessions/<SESSION_ID>/signals/`.

**Structure:**
```
signals/
├── inputs/                      # User drops signal files here
│   ├── signal.<TIMESTAMP>.yaml  # e.g., signal.260208-143000.yaml
│   └── ...
├── acks/                        # Per-signal delivery acknowledgements
│   └── <SIGNAL_ID>/
│       ├── Orchestrator.ack.yaml
│       ├── Executor.ack.yaml
│       └── ...
└── processed/                   # Agents move handled files here
    ├── <TIMESTAMP>.yaml         # Archived signal
    └── ...
```

**Signal File Schema (Input):**

```yaml
# signal.260208-143000.yaml
type: STEER      # STEER | PAUSE | ABORT | INFO | SKIP
target: ALL      # ALL | Executor | Orchestrator
message: "Don't use the 'foo' library, it's deprecated. Use 'bar' instead."
iteration: 1     # Optional. Forward-compatibility for iteration-scoped signals (e.g., SKIP).
                  # Orchestrator ignores if absent; validates against current iteration if present.
```

> **SKIP ownership**: This state-specific signal is consumed by the Librarian during PROMOTE mode within the KNOWLEDGE_EXTRACTION state (not the Orchestrator). The Librarian polls `signals/inputs/` directly and archives on consume before transitioning.

> **Forward-compatibility note**: Signal filenames currently use second-level timestamps (`signal.<YYMMDD-HHmmss>.yaml`), which is sufficient for human-generated signals. If automated signal generation is introduced in the future (e.g., hooks emitting signals), use millisecond timestamps or random suffixes (e.g., `signal.<YYMMDD-HHmmss>-<ms>.yaml` or `signal.<YYMMDD-HHmmss>-<random4>.yaml`) to avoid collisions.

**Processed File Schema (Output adds metadata):**
The consuming agent (targeted signal) or the Orchestrator (after `target: ALL` ack quorum) appends handling info when moving to `processed/`:

```yaml
# Original content...
# ...
handling_metadata:
   handled_by: Executor
   handled_at: 2026-02-08T14:30:05Z
   action_taken: "Updated context to prefer 'bar' library"
```

**Target Namespace Standard (Version-Agnostic):**
- `target` accepts only role names: `ALL | Orchestrator | Executor | Planner | Questioner | Reviewer | Librarian`.
- Do not include workflow version in `target` values. The active Ralph version is inferred from runtime context.

#### 2.2 Concurrency Strategy

1. **Wait-Free Insertion**: Users create unique files with timestamps. No conflict with other signals.
2. **Broadcast-Safe Consumption**:
   - Agent lists files in `signals/inputs/`.
   - Agent picks the oldest file (FIFO by timestamp).
   - Agent **reads** the file content to determine the signal type (peek).
   - If `target == ALL`, the agent **must not move** the signal file. Instead it writes an idempotent per-agent ack file at `signals/acks/<SIGNAL_ID>/<AGENT>.ack.yaml` after ingesting the signal.
   - If `target` is a single consumer (for example `Orchestrator` or `Executor`), the recognized consumer moves the file to `signals/processed/` after successful ingestion.
   - If the signal type is not recognized in the current context, leave it in `inputs/`.

3. **Target-Aware Routing** (Orchestrator):
   After peeking at a signal file, the Orchestrator applies target-aware routing before consuming:
   1. **Peek**: Read signal file to get `type`, `target`, `message`.
   2. **Check target**:
      - If `target == ALL`: apply locally, write `Orchestrator` ack, and leave signal in `inputs/`.
      - If `target == Orchestrator`: consume normally (move to `processed/`, act on it).
   3. **Route to subagent**: If `target` names a subagent (for example `target: Executor`) buffer the signal for delivery at the next targeted subagent invocation, then move to `processed/`.
   4. **Finalize ALL delivery**: Only the Orchestrator may archive a `target: ALL` signal. It moves the signal to `processed/` only after all required recipients have acked.
   5. **Subagent direct polling**: When subagents poll `signals/inputs/` directly (for universal signals — see [§4 Agent Integration](#4-agent-integration--hybrid-polling-model)), they process only signals where `target == ALL` or `target` matches the current subagent identity.

4. **Required Ack Set for `target: ALL`**:
   - `Orchestrator`
   - `Executor`
   - `Planner`
   - `Questioner`
   - `Reviewer`

   > **Note**: Librarian is excluded from the required ack set because it is invoked episodically (only during KNOWLEDGE_EXTRACTION state). Including it would block `target: ALL` quorum resolution during states where Librarian is not running.

5. **Session-End Finalization Rule**:
   - On transition to `COMPLETE`, the Orchestrator evaluates any remaining `target: ALL` signals.
   - If all required acks exist, archive normally.
   - If some acks are missing, archive with metadata `delivery_status: partial` plus an `unacked_agents` list. This prevents mailbox leaks while preserving delivery audit.

6. **Exact Orchestrator Archive Moments**:
   - Targeted to `Orchestrator` (or unscoped): archive immediately in Poll-Signals consume path.
   - Targeted to a specific subagent: archive immediately after buffering for that subagent.
   - `target: ALL`: archive only when ack quorum is reached (or at session end with `delivery_status: partial`).
   - `SKIP` in `KNOWLEDGE_EXTRACTION` (PROMOTE step): Librarian archives immediately on consume before transition.

   <!-- Cross-ref: The orchestrator's Poll-Signals routine implements this peek-check-route flow. See ralph-v2.agent.md §State Machine. -->

### 3. Signal Types

#### Overview

| Type        | Category         | Semantics                | Polled By                          |
| ----------- | ---------------- | ------------------------ | ---------------------------------- |
| **STEER**   | Universal        | Trajectory Correction    | Orchestrator + Subagents (direct)  |
| **INFO**    | Universal        | Context Injection        | Orchestrator + Subagents (direct)  |
| **PAUSE**   | Universal        | Temporary Halt           | Orchestrator + Subagents (direct)  |
| **ABORT**   | Universal        | Permanent Halt           | Orchestrator + Subagents (direct)  |
| **SKIP**    | State-specific   | Knowledge Promotion Bypass | Librarian (PROMOTE mode within KNOWLEDGE_EXTRACTION) |

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

#### 3.5 SKIP — Knowledge Promotion Bypass

**Semantics**: Bypass knowledge promotion; the session completes without promoting staged knowledge to `.docs/`. This signal is **state-specific** — it is only consumed during the PROMOTE step of `KNOWLEDGE_EXTRACTION` state.

**Agent Behavior**: Librarian (in PROMOTE mode) polls for SKIP signal before executing promotion → marks `plan-knowledge-promotion [C]` in `progress.md` → returns `outcome: "skipped"` to Orchestrator. Staged knowledge is **preserved** in session-scope `knowledge/` (not deleted) but not promoted to `.docs/`.

**`message` field**: Reason for skipping (e.g., "Need more review time" or "Knowledge is too specific to this task").

**Polling**: Librarian only (in PROMOTE mode). The Orchestrator auto-sequences EXTRACT → STAGE → PROMOTE within KNOWLEDGE_EXTRACTION; SKIP allows the human to opt out of the final PROMOTE step.

**Default behavior (v2.10.0)**: Knowledge promotion is **auto-promoted** by default. The SKIP signal is the opt-out mechanism — if no SKIP signal is present, PROMOTE proceeds automatically. Promoted knowledge (in `.docs/` with `promoted: true`) is the final state; session-scope `knowledge/` remains as-is for audit.

#### 3.6 COMMIT Mode — Signal Behavior

The Reviewer's **COMMIT mode** (atomic commit of reviewed task changes) is invoked by the Orchestrator as a sub-step within `REVIEWING_BATCH`. COMMIT mode does **NOT** introduce any new signal types. It uses the existing signal infrastructure as follows:

- **No new signal types**: COMMIT mode relies entirely on existing STEER, INFO, PAUSE, ABORT, and SKIP signals.
- **Signal polling during COMMIT**: COMMIT is a short-lived operation (git staging + commit). The Reviewer does not poll `signals/inputs/` during COMMIT Steps 1–6. Instead, the Orchestrator polls signals at the boundary between the TASK_REVIEW invocation and the COMMIT invocation.
- **ABORT during COMMIT**: If an ABORT signal arrives while the Orchestrator is blocked waiting for COMMIT to return, the COMMIT operation completes or fails independently. On return, the Orchestrator detects the ABORT signal at its next checkpoint and executes the ABORT cleanup checklist (§3.4). Importantly, **commit failure does NOT revert the `[x]` review verdict** — the review and commit outcomes are independent.
- **STEER during COMMIT**: STEER signals are not consumed during COMMIT. They are picked up by the Orchestrator at the next state boundary after COMMIT returns. Re-evaluation of commit scope mid-commit is not supported — COMMIT operates on the files identified in the task report.
- **Retry logic**: The Orchestrator retries COMMIT once on failure. If both attempts fail, changes remain in the working directory. The `[x]` verdict is preserved regardless of commit outcome.

### 4. Agent Integration — Hybrid Polling Model

Subagents have a **dual role** in signal handling, resolving the previous design inconsistency where subagents were classified as "context consumers" but actually polled `signals/inputs/` directly in their workflow code:

| Classification         | Signals                      | Description                                                                                           |
| ---------------------- | ---------------------------- | ----------------------------------------------------------------------------------------------------- |
| **Direct poller**      | STEER, INFO, PAUSE, ABORT    | Subagents poll `signals/inputs/` at step boundaries during long-running tasks. These are **universal signals** — time-sensitive and relevant regardless of orchestrator state. |
| **Librarian direct poller (PROMOTE)** | SKIP | Librarian polls this directly in PROMOTE mode within KNOWLEDGE_EXTRACTION. This is a **state-specific signal** — only meaningful during the PROMOTE step. |
| **Primary poller**     | All types                    | Orchestrator — routes signals, finalizes `target: ALL` archival after ack quorum, and dispatches state-specific signals. |

#### A. Orchestrator (Ralph-v2)

**Role**: Primary signal router, flow controller, and state-specific signal consumer.

**Checkpoints**:
1. **State Boundaries**: Poll signals between every state transition.
2. **Before Invoking Subagent**: Check signals. If `ABORT` → execute cleanup checklist (§3.4) and exit. If `PAUSE` → suspend and wait. If `STEER/INFO` → pass message to subagent invocation context.
3. **Loop Boundaries**: Inside `EXECUTING_BATCH` loop (between tasks). Inside `REVIEWING_BATCH` loop (between reviews and between review→COMMIT invocations — COMMIT is a sub-step within REVIEWING_BATCH, not a separate state).
4. **KNOWLEDGE_EXTRACTION** (PROMOTE step): Delegates to Librarian (PROMOTE mode) which polls for `SKIP` signal directly before auto-promoting.

**Target-Aware Routing**: The Orchestrator checks the `target` field before consuming (see [§2.2 Concurrency Strategy](#22-concurrency-strategy)). Signals targeting a specific subagent are buffered and delivered at the next invocation of that subagent. For `target: ALL`, the Orchestrator writes only its own ack and leaves the signal available for other subagents.

#### B. Subagents (Executor, Planner, Questioner, Reviewer, Librarian)

**Role**: Direct pollers for universal signals; context consumers for state-specific signals.

**Direct Polling Checkpoints** (for universal signals: STEER, PAUSE, ABORT, INFO):
1. **Initialization (Step 0)**: Poll `signals/inputs/` before starting work. If `ABORT` → return `blocked`. If `PAUSE` → save state and return `paused`. If `STEER/INFO` → ingest into context.
2. **Step Boundaries**: Between major workflow steps (e.g., Executor between Read Context → Mark WIP → Implement → Verify). If a universal signal is found, handle it before proceeding to the next step.
3. **Mid-Execution (Step 3.5 — Executor only)**: Poll during long-running implementation. Apply STEER decision tree (§3.1) if a STEER signal is found.
4. **Ack Behavior**: After ingesting a `target: ALL` universal signal, write `signals/acks/<SIGNAL_ID>/<CURRENT_AGENT>.ack.yaml` and do not move the source signal.

**State-Specific Signals** (SKIP):
- Only the Librarian polls for SKIP, and only in PROMOTE mode within `KNOWLEDGE_EXTRACTION` state.
- Other subagents do NOT poll for SKIP. It is irrelevant outside the PROMOTE step.
- Orchestrator auto-sequences EXTRACT → STAGE → PROMOTE within KNOWLEDGE_EXTRACTION; Librarian polls for SKIP before executing promotion.

**Why hybrid?** When the Orchestrator invokes a long-running subagent (e.g., Executor on a complex task), the Orchestrator is BLOCKED waiting for the return. During this time, no orchestrator-level polling occurs. Direct polling by subagents ensures time-sensitive signals (STEER, PAUSE, ABORT) are handled within the subagent's execution, not delayed until the subagent returns.

> **Invariant — Temporal Demarcation**: The Orchestrator and subagents never poll `signals/inputs/` simultaneously. The Orchestrator polls at **state boundaries** (when no subagent is running). Subagents poll at **step boundaries** (when the Orchestrator is blocked). This temporal separation still reduces contention; duplicate reads are intentional only for `target: ALL` and tracked via per-agent ack files.

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
   - Orchestrator reads the signal (peek), recognizes `STEER` as universal with `target: ALL`.
   - Orchestrator applies it locally, writes `signals/acks/signal.20260208-143000/Orchestrator.ack.yaml`, and leaves the signal in `inputs/`.
5. **Executor Checkpoint**: Executor reaches Step 0 polling.
   - Executor ingests the same signal, writes `signals/acks/signal.20260208-143000/Executor.ack.yaml`, and keeps the signal in `inputs/`.
6. **Finalization**: After all required agent acks exist, Orchestrator archives the signal to `signals/processed/` with delivery metadata.

### 6. Implementation Plan

#### Phase 1: Artifact Support

- Define `signals/` directory structure.
- Create `Inject-Signal` skill (PowerShell script) to create timestamped files safely.

#### Phase 2: Agent Updates

- **Ralph-v2 (Orchestrator)**: Add "Poll Signals" step in State Machine key loops (list, peek, route, finalize). Implement target-aware routing with ack-quorum finalization for `target: ALL` (§2.2). Add ABORT cleanup checklist execution (§3.4).
- **Subagents**: Implement direct polling for universal signals (STEER, PAUSE, ABORT, INFO) at step boundaries and write per-agent ack files for `target: ALL`. Librarian polls for SKIP in PROMOTE mode.

#### Phase 3: "Hot Steering" (Advanced)

- Implement the STEER mid-execution decision tree (§3.1) in the Executor's Step 3.5.
- Allow agents to restart, adjust, or escalate based on STEER signal impact analysis.

---

## Implementation Map

> This section maps all **Live Signal Checkpoints** in the Ralph v2 agent system. Use this as a reference when fine-tuning signal responsiveness or adding new polling locations.

### Agent Classification (Hybrid Polling Model)

Subagents have a **dual role** in signal handling, formalized as the Hybrid Polling Model (see [§4 Agent Integration](#4-agent-integration--hybrid-polling-model)). This resolves the previous inconsistency where subagents were classified as "context consumers" but actually polled `signals/inputs/` directly.

| Agent              | Universal Signals (STEER, INFO, PAUSE, ABORT) | State-Specific Signals (SKIP)    | Role                                                                         |
| ------------------ | ---------------------------------------------- | ----------------------------------------- | ---------------------------------------------------------------------------- |
| **Orchestrator**   | Direct poller (state boundaries)               | Delegates to Librarian (PROMOTE step) | **Primary poller** — owns `signals/inputs/`, routes targeted signals         |
| **Executor**       | Direct poller (step boundaries)                | Context consumer                          | Direct poller for universal; context consumer for state-specific             |
| **Planner**        | Direct poller (mode start)                     | Context consumer                          | Direct poller for universal; context consumer for state-specific             |
| **Questioner**     | Direct poller (cycle/loop boundaries)          | Context consumer                          | Direct poller for universal; context consumer for state-specific             |
| **Reviewer**       | Direct poller (step boundaries)                | Context consumer                          | Direct poller for universal; context consumer for state-specific             |
| **Librarian**      | Direct poller (stage/gate boundaries)          | Direct poller (PROMOTE mode)   | Direct poller for universal; direct poller for SKIP in PROMOTE |

**Why hybrid?** When the Orchestrator invokes a long-running subagent, the Orchestrator is BLOCKED waiting for the return. Direct polling by subagents ensures universal signals (STEER, PAUSE, ABORT, INFO) are handled within the subagent's execution, not delayed until return.

### 1. Ralph-v2 (Orchestrator)

| State                | Location            | Code Block                     | Behavior                                                                                                                     |
| -------------------- | ------------------- | ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| `INITIALIZING`       | Artifact Creation   | `2. State: INITIALIZING`       | Creates `signals/inputs/`, `signals/acks/`, and `signals/processed/` directories.                                            |
| `PLANNING`           | Top of State        | `3. State: PLANNING`           | **ABORT**: Exit.<br>**PAUSE**: Wait.<br>**STEER**: Update plan notes before routing.<br>**INFO**: Log and continue.           |
| `EXECUTING_BATCH`    | Pre-Loop            | `6. State: EXECUTING_BATCH`    | **ABORT**: Exit.<br>**PAUSE**: Wait.<br>**STEER**: Logs message and passes to Executor context.<br>**INFO**: Append to context. |
| `REVIEWING_BATCH`    | Pre-Loop            | `7. State: REVIEWING_BATCH`    | **ABORT**: Exit.<br>**PAUSE**: Wait.<br>**INFO**: Inject into review context.<br>**STEER**: Log message, pass to Reviewer context. |
| `REVIEWING_BATCH`    | Between Review & COMMIT | `7. State: REVIEWING_BATCH` | COMMIT is a sub-step within REVIEWING_BATCH (not a new state). After `[x]` verdict, Orchestrator invokes COMMIT mode for the same task. Signal polling occurs between review invocation and COMMIT invocation — ABORT/PAUSE checked before each invocation. |
| `KNOWLEDGE_EXTRACTION` | EXTRACT→STAGE→PROMOTE | `9. State: KNOWLEDGE_EXTRACTION` | Auto-sequences 3 Librarian invocations: EXTRACT (iteration→iteration knowledge), STAGE (iteration→session merge), PROMOTE (session→`.docs/` merge). **SKIP**: Librarian polls before PROMOTE — skips promotion, preserves session-scope `knowledge/`.<br>**ABORT**: Exit with cleanup (§3.4). |

> **Target-Aware Routing**: At every checkpoint above, the Orchestrator applies peek-check-route logic (see [§2.2 Concurrency Strategy](#22-concurrency-strategy)). Signals targeting a specific subagent are buffered for delivery at the next invocation.

### 2. Ralph-v2-Executor

| Workflow Section  | Step         | Code Block                            | Behavior                                                                                                                                              |
| ----------------- | ------------ | ------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `1. Read Context` | **Step 0**   | `Step 0: Check Live Signals`          | **ABORT**: Return blocked status.<br>**PAUSE**: Wait.<br>**STEER**: Update current execution context.<br>**INFO**: Append to context.                  |
| `2. Mark WIP`     | **Step 2**   | `2. Mark WIP`                         | **ABORT**: Return blocked.<br>**PAUSE**: Wait.<br>**STEER**: Log and continue.<br>**INFO**: Log and continue.                                          |
| `3. Implement`    | **Step 3.5** | `3.5. Verify Signals (Mid-Execution)` | **STEER**: Apply decision tree (§3.1): (a) restart, (b) adjust, (c) escalate.<br>**INFO**: Append to context and continue.     |

### 3. Ralph-v2-Planner

| Mode             | Step           | Code Block                    | Behavior                                                                                                                                                  |
| ---------------- | -------------- | ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| All modes        | **Mode Start** | Before mode-specific workflow | **ABORT**: Return blocked.<br>**PAUSE**: Wait.<br>**STEER**: Adjust mode context before proceeding.<br>**INFO**: Append to context.                        |
| `TASK_BREAKDOWN` | **Step 0**     | `Step 0: Check Live Signals`  | **ABORT**: Return blocked.<br>**PAUSE**: Wait.<br>**STEER**: Adjust plan context and constraints before generating task files.<br>**INFO**: Log and continue. |

### 4. Ralph-v2-Questioner

| Mode                | Loop            | Code Block                                  | Behavior                                                                                                                |
| ------------------- | --------------- | ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `brainstorm`        | Pre-Generation  | `Step 1.5: Check Live Signals`              | **STEER**: Update analysis context.<br>**PAUSE**: Wait.<br>**ABORT**: Return early.<br>**INFO**: Append to analysis.     |
| `research`          | Question Loop   | `Step 2: Research each unanswered question` | **Act on**: STEER/INFO/PAUSE/ABORT inside loop.                                                                          |
| `feedback-analysis` | Issue Loop      | `Process: 2. For each critical issue`       | **Act on**: STEER/INFO/PAUSE/ABORT inside loop.                                                                          |

### 5. Ralph-v2-Reviewer

| Workflow Section | Step             | Code Block                   | Behavior                                                                                                                                   |
| ---------------- | ---------------- | ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `TASK_REVIEW`    | **Step 0**       | `Step 0: Check Live Signals` | **ABORT**: Return blocked.<br>**PAUSE**: Wait.<br>**STEER**: Adjust review context.<br>**INFO**: Append to context.                         |
| `TASK_REVIEW`    | **Step 1.5**     | `1.5. Check Live Signals`    | **STEER**: Adjust validation context.<br>**PAUSE**: Wait.<br>**ABORT**: Return early.<br>**INFO**: Append to validation context.             |
| `TASK_REVIEW`    | **Post-Verdict** | After review decision        | **ABORT**: Proceed to Report to Orchestrator.<br>**STEER**: Re-evaluate if verdict should change.                                            |
| `COMMIT`         | **Step 0**       | `Step 0: Skills Resolution`  | COMMIT mode has its own Step 0 skills discovery. No explicit signal checkpoint at Step 0 — COMMIT is a short-lived operation. Signal polling is handled by the Orchestrator between review and COMMIT invocations (see [§1 Orchestrator](#1-ralph-v2-orchestrator)). |
| `COMMIT`         | **ABORT during COMMIT** | Steps 1–6             | If ABORT is received by the Orchestrator while COMMIT is running, the Orchestrator is blocked. COMMIT completes or fails independently. On return, Orchestrator checks signals and executes ABORT cleanup. Commit failure does NOT revert the `[x]` review verdict. |

### 6. Ralph-v2-Librarian

| Mode      | Step                   | Code Block                         | Behavior                                                                                                                                   |
| --------- | ---------------------- | ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `EXTRACT` | **Gate 0 (Preflight)** | Before extraction preflight        | **ABORT**: Return blocked.<br>**PAUSE**: Wait.<br>**STEER**: Adjust extraction scope/criteria.<br>**INFO**: Append to context.              |
| `STAGE`   | **Gate 1 (Preflight)** | Before staging preflight           | **ABORT**: Return blocked.<br>**PAUSE**: Wait.<br>**STEER**: Adjust staging scope/criteria.<br>**INFO**: Append to context.                 |
| `EXTRACT` | **Post-Collection**    | After evidence collection (Step 4) | **ABORT**: Return blocked.<br>**PAUSE**: Wait.<br>**STEER**: Re-filter collected knowledge based on new context.<br>**INFO**: Append to context and continue.   |
| `PROMOTE` | **Gate 2 (Preflight)** | Before promotion preflight         | **ABORT**: Return blocked.<br>**PAUSE**: Wait.<br>**STEER**: Adjust promotion scope.<br>**INFO**: Append to context.                        |
| `PROMOTE` | **Pre-Promote Signal Check** | Step 2: Poll for SKIP | **SKIP**: Mark `[C]` and return `skipped` outcome.<br>**ABORT**: Return blocked.<br>**PAUSE**: Wait.<br>**STEER**: Adjust promotion scope. |
| `PROMOTE` | **Post-Collection** | After reading staged content (Step 5) | **STEER**: Re-filter staged content based on new context.<br>**INFO**: Append to context and continue. |

### 7. Gap Analysis

| Agent  | Potential Location | Reason to Add                                                    |
| ------ | ------------------ | ---------------------------------------------------------------- |
| (None) |                    | All identified gaps addressed in this revision (Planner mode start, Librarian gates, Reviewer Step 0/Post-Verdict). |

### 8. Checkpoint Performance

Checkpoint overhead is **negligible**. Each checkpoint involves a single directory listing (`Get-ChildItem signals/inputs/` on Windows, `ls signals/inputs/` on Linux). When no signals are pending (the common case), this completes in <10ms.

During a typical task execution, 3–5 checkpoints fire (e.g., Executor Steps 0, 2, 3.5), totaling **~30–50ms per task** — insignificant compared to the seconds/minutes of actual task work. Adding new checkpoints (e.g., to Planner and Librarian) is safe with no measurable performance impact.

*(Source: Q-RISK-004 — Performance overhead from frequent polling is LOW.)*

### Common Polling Routine

All checkpoints follow this logic pattern (Mailbox Pattern). Signal type determines routing per the Hybrid Polling Model — subagents handle universal signals (STEER/INFO/PAUSE/ABORT) directly, while the state-specific signal (SKIP) is handled by the Librarian during PROMOTE mode within KNOWLEDGE_EXTRACTION.

```markdown
Poll signals/inputs/
  - List files (sort timestamp asc)
  - For each file (FIFO):
    - Peek: Read signal type and target
    - If target != ALL and target != self → skip (leave for correct consumer)
    - If target == ALL:
      - Do NOT move source signal
      - Write idempotent ack file: signals/acks/<SIGNAL_ID>/<self>.ack.yaml
      - Continue processing content
    - Else:
      - Atomic Move → signals/processed/
    - Read Content
    - Act based on type: STEER / INFO / PAUSE / ABORT
    - (Librarian only: also handle SKIP in PROMOTE mode)
    - (Orchestrator only: archive target ALL after all required ack files exist)
```
