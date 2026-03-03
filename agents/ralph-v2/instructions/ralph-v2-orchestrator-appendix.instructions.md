---
description: Appendix for Ralph-v2 Orchestrator instructions — extended state machine and feedback protocol reference
applyTo: ".ralph-sessions/**"
---

# Ralph-v2 Orchestrator — Extended Reference Appendix

> Extended state machine sections (States 8, 8.5, 9), live signal protocol, post-iteration feedback protocol, and schema validation rules — extracted from `ralph-v2-orchestrator.instructions.md` to keep the core file within the CLI 30K character limit.

### Schema Validation Rules

**iterations/<N>/progress.md must include:**
- `# Progress` header
- `## Legend` section with statuses `[ ]`, `[/]`, `[P]`, `[x]`, `[F]`, `[C]`
- `## Planning Progress (Iteration N)` section
- `## Implementation Progress (Iteration N)` section

**metadata.yaml must include:**
- `version`, `session_id`, `created_at`, `updated_at`, `iteration`
- `orchestrator.state`, `orchestrator.previous_state` (optional, set when transitioning to REPLANNING)
- `tasks.total`, `tasks.completed`, `tasks.failed`, `tasks.pending`
- `session_review.cycle` (int, default `0`) — incremented each time SESSION_CRITIQUE_REPLAN is entered; reset to `0` at new iteration start
- `session_review.issue_severity_threshold` (string, default `"any"`) — loaded once from `<SESSION_ID>.instructions.md`; controls which issue severities trigger the self-critique loop (`"any"` | `"major"` | `"critical"`)
- `session_review.max_critique_cycles` (int or null, default `null`) — loaded once from `<SESSION_ID>.instructions.md`; `null` = unlimited; set to a positive integer to cap loop cycles

**Valid Planning Task Names:**

*Planning tasks (Iteration 1):*
- `plan-init`
- `plan-brainstorm`
- `plan-research`
- `plan-breakdown`

*Replanning tasks (Iteration N+1):*
- `plan-rebrainstorm`
- `plan-reresearch`
- `plan-update`
- `plan-rebreakdown`

*Critique tasks (within iteration N, per cycle C):*
- `plan-critique-triage`
- `plan-critique-brainstorm` (optional — only present if CRITIQUE_TRIAGE sets `brainstorm_needed: true`)
- `plan-critique-research` (optional — only present if CRITIQUE_TRIAGE sets `research_needed: true`)
- `plan-critique-breakdown`

*Knowledge tasks (any iteration):*
- `plan-knowledge-extraction`
- `plan-knowledge-staging`
- `plan-knowledge-promotion`

**Knowledge Progress (Iteration N):**
- `plan-knowledge-extraction`: `[ ]` | `[x]` | `[C]`
- `plan-knowledge-staging`: `[ ]` | `[x]` | `[C]`
- `plan-knowledge-promotion`: `[ ]` | `[x]` | `[C]`

**Critique Planning Progress (Iteration N, Cycle C):** *(optional section; appended to `iterations/<N>/progress.md` by Planner on first entry into SESSION_CRITIQUE_REPLAN)*
- `plan-critique-triage`: `[ ]` | `[x]`
- `plan-critique-brainstorm`: `[ ]` | `[x]` (optional)
- `plan-critique-research`: `[ ]` | `[x]` (optional)
- `plan-critique-breakdown`: `[ ]` | `[x]`

### Timeout Recovery Policy

Apply to any subagent call:
1. Re-spawn the same subagent with the same single-mode input.
2. If timeout or error again, sleep 30 seconds, then re-spawn.
3. If timeout or error again, sleep 60 seconds, then re-spawn.
4. If timeout or error again, sleep 60 seconds, then re-spawn.
5. If still failing:
    - If `TASK_ID` exists: invoke Ralph-v2-Planner (MODE: SPLIT_TASK) with that task. The Orchestrator then treats the newly broken-down tasks as replacements and invokes Executor for each. If these also time out, the policy reapplies to the new tasks.
    - If no `TASK_ID`: exit with error and ask user to reduce scope.

**Concrete Sleep Commands**
- **Windows (PowerShell):** `Start-Sleep -Seconds 30` or `Start-Sleep -Seconds 60`
- **Linux/WSL (bash):** `sleep 30` or `sleep 60`

### Local Timestamp Commands

Use these commands for local timestamps across the workflow (SESSION_ID, metadata timestamps):

**Note:** These commands return local time in your system's timezone (UTC+7), not UTC.

- **SESSION_ID format `<YYMMDD>-<hhmmss>`**
  - **Windows (PowerShell):** `Get-Date -Format "yyMMdd-HHmmss"`
  - **Linux/WSL (bash):** `TZ=Asia/Ho_Chi_Minh date +"%y%m%d-%H%M%S"`

- **ISO8601 local timestamp (with offset)**
  - **Windows (PowerShell):** `Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"`
  - **Linux/WSL (bash):** `TZ=Asia/Ho_Chi_Minh date +"%Y-%m-%dT%H:%M:%S%z"`

### 8. State: SESSION_REVIEW

```
# Check Live Signals
RUN Poll-Signals
    IF ABORT: EXIT
    IF PAUSE: WAIT
    IF INFO: Inject message into review context for consideration
    IF STEER:
        LOG "Steering signal received: <message>"
        PASS signal message to Reviewer context in next invocation

# Read current critique cycle counter (persisted across loops)
C = metadata.yaml.session_review.cycle (default 0)

INVOKE Ralph-v2-Reviewer
    MODE: SESSION_REVIEW
    SESSION_PATH: .ralph-sessions/<SESSION_ID>/
    ITERATION: <current iteration>
    SESSION_REVIEW_CYCLE: C
    ORCHESTRATOR_CONTEXT: PENDING_CONTEXT (if available)

ON completion:
    CAPTURE message_to_next → BUFFER as PENDING_CONTEXT

ON timeout or error:
    APPLY Timeout Recovery Policy

# --- Self-Critique Loop Decision ---
# Apply issue_severity_threshold to determine active issue count
ISSUE_SEVERITY_THRESHOLD = session_review.issue_severity_threshold (loaded in Session Resolution; default "any")

IF ISSUE_SEVERITY_THRESHOLD == "any":
    ACTIVE_ISSUE_COUNT = Reviewer output "issues_found.total_count"
ELSE IF ISSUE_SEVERITY_THRESHOLD == "major":
    ACTIVE_ISSUE_COUNT = issues_found.critical_count + issues_found.major_count
ELSE IF ISSUE_SEVERITY_THRESHOLD == "critical":
    ACTIVE_ISSUE_COUNT = issues_found.critical_count

IF ACTIVE_ISSUE_COUNT == 0:
    # No active issues — finalize iteration timing and advance to KNOWLEDGE_EXTRACTION
    UPDATE iterations/<ITERATION>/metadata.yaml: completed_at: <timestamp>
    INVOKE Ralph-v2-Planner
        MODE: UPDATE_METADATA
        SESSION_PATH: .ralph-sessions/<SESSION_ID>/
        STATUS: "completed"
    ON timeout or error:
        APPLY Timeout Recovery Policy
    UPDATE metadata.yaml:
        - state: KNOWLEDGE_EXTRACTION
        - session_review.cycle: 0  # reset for any future iteration
    STATE = KNOWLEDGE_EXTRACTION

ELSE:
    # Active issues exist — check loop cap before re-entering critique
    MAX_CRITIQUE_CYCLES = session_review.max_critique_cycles (loaded in Session Resolution; null = unlimited)

    IF MAX_CRITIQUE_CYCLES is not null AND C >= MAX_CRITIQUE_CYCLES:
        LOG WARNING "SESSION_REVIEW self-critique cap hit (cycle=<C>, max=<MAX_CRITIQUE_CYCLES>). Advancing to KNOWLEDGE_EXTRACTION with <ACTIVE_ISSUE_COUNT> active issue(s) unresolved."
        UPDATE iterations/<ITERATION>/metadata.yaml: completed_at: <timestamp>
        INVOKE Ralph-v2-Planner
            MODE: UPDATE_METADATA
            SESSION_PATH: .ralph-sessions/<SESSION_ID>/
            STATUS: "awaiting_feedback"
        ON timeout or error:
            APPLY Timeout Recovery Policy
        UPDATE metadata.yaml:
            - state: KNOWLEDGE_EXTRACTION
            - session_review.cycle: 0
        STATE = KNOWLEDGE_EXTRACTION

    ELSE:
        # Increment cycle and enter critique replanning
        NEW_CYCLE = C + 1
        UPDATE metadata.yaml:
            - state: SESSION_CRITIQUE_REPLAN
            - session_review.cycle: NEW_CYCLE
        STATE = SESSION_CRITIQUE_REPLAN
```

### 8.5. State: SESSION_CRITIQUE_REPLAN

```
# Route critique planning tasks (mirrors PLANNING state pattern)
# Critique planning tasks live in progress.md under:
#   "## Critique Planning Progress (Iteration N, Cycle C)"

# Check Live Signals
RUN Poll-Signals
    IF ABORT: EXIT
    IF PAUSE: WAIT
    IF INFO: Inject message into review context for consideration

READ iterations/<ITERATION>/progress.md
C = metadata.yaml.session_review.cycle  # current cycle (already incremented in State 8)

# Routing: find the first incomplete critique planning task for cycle C

IF plan-critique-triage (Cycle C) not present in progress.md OR not [x]:
    INVOKE Ralph-v2-Planner
        SESSION_PATH: .ralph-sessions/<SESSION_ID>/
        MODE: CRITIQUE_TRIAGE
        ITERATION: <current iteration>
        REVIEW_PATH: iterations/<ITERATION>/review.md
        SESSION_REVIEW_CYCLE: C
        ORCHESTRATOR_CONTEXT: PENDING_CONTEXT (if available)

    ON completion:
        CAPTURE message_to_next → BUFFER as PENDING_CONTEXT
        # Planner appended "## Critique Planning Progress (Iteration N, Cycle C)"
        # to progress.md with plan-critique-triage [x] and optional subtasks

    ON timeout or error:
        APPLY Timeout Recovery Policy

ELSE IF plan-critique-brainstorm (Cycle C) exists in progress.md AND not [x]:
    INVOKE Ralph-v2-Questioner
        SESSION_PATH: .ralph-sessions/<SESSION_ID>/
        MODE: brainstorm
        SOURCE: critique
        ITERATION: <current iteration>
        REVIEW_PATH: iterations/<ITERATION>/review.md
        CYCLE: C
        ORCHESTRATOR_CONTEXT: PENDING_CONTEXT (if available)

    ON completion:
        CAPTURE message_to_next → BUFFER as PENDING_CONTEXT

    ON timeout or error:
        APPLY Timeout Recovery Policy

ELSE IF plan-critique-research (Cycle C) exists in progress.md AND not [x]:
    INVOKE Ralph-v2-Questioner
        SESSION_PATH: .ralph-sessions/<SESSION_ID>/
        MODE: research
        ITERATION: <current iteration>
        CYCLE: C
        QUESTION_CATEGORY: critique-<C>
        ORCHESTRATOR_CONTEXT: PENDING_CONTEXT (if available)

    ON completion:
        CAPTURE message_to_next → BUFFER as PENDING_CONTEXT

    ON timeout or error:
        APPLY Timeout Recovery Policy

ELSE IF plan-critique-breakdown (Cycle C) not [x]:
    INVOKE Ralph-v2-Planner
        SESSION_PATH: .ralph-sessions/<SESSION_ID>/
        MODE: CRITIQUE_BREAKDOWN
        ITERATION: <current iteration>
        REVIEW_PATH: iterations/<ITERATION>/review.md
        SESSION_REVIEW_CYCLE: C
        ORCHESTRATOR_CONTEXT: PENDING_CONTEXT (if available)

    ON completion:
        CAPTURE message_to_next → BUFFER as PENDING_CONTEXT

    ON timeout or error:
        APPLY Timeout Recovery Policy

ELSE:
    # All critique planning tasks [x] — execute gap-filling tasks
    # Gap-filling tasks were added to Implementation Progress (Iteration N) by CRITIQUE_BREAKDOWN
    UPDATE metadata.yaml with state: BATCHING
    STATE = BATCHING
    # Flow: BATCHING → EXECUTING_BATCH → REVIEWING_BATCH → BATCHING (loop)
    # → SESSION_REVIEW re-invoked with incremented cycle; loop continues until
    #   ACTIVE_ISSUE_COUNT == 0 or max_critique_cycles cap is hit
```

### 9. State: KNOWLEDGE_EXTRACTION

```
# Conditional activation
IF 'Ralph-v2-Librarian' NOT in agents list:
    UPDATE metadata.yaml with state: COMPLETE
    STATE = COMPLETE
    SKIP to State 10 (COMPLETE)

# --- Step A: EXTRACT (iteration artifacts → iteration knowledge/) ---
INVOKE Ralph-v2-Librarian
    SESSION_PATH: .ralph-sessions/<SESSION_ID>/
    MODE: EXTRACT
    ITERATION: <current iteration>
    ORCHESTRATOR_CONTEXT: PENDING_CONTEXT (if available)

ON completion:
    CAPTURE message_to_next → BUFFER as PENDING_CONTEXT

ON timeout or error:
    APPLY Timeout Recovery Policy

# Check extraction result
IF Librarian returns 0 items extracted:
    UPDATE metadata.yaml with state: COMPLETE
    STATE = COMPLETE
    SKIP to State 10 (COMPLETE)

# --- Step B: STAGE (iteration knowledge/ → session knowledge/) ---
INVOKE Ralph-v2-Librarian
    SESSION_PATH: .ralph-sessions/<SESSION_ID>/
    MODE: STAGE
    ITERATION: <current iteration>
    ORCHESTRATOR_CONTEXT: PENDING_CONTEXT (if available)

ON completion:
    CAPTURE message_to_next → BUFFER as PENDING_CONTEXT

ON timeout or error:
    APPLY Timeout Recovery Policy

# --- Step C: PROMOTE (session knowledge/ → workspace .docs/) ---
INVOKE Ralph-v2-Librarian
    SESSION_PATH: .ralph-sessions/<SESSION_ID>/
    MODE: PROMOTE
    ITERATION: <current iteration>
    ORCHESTRATOR_CONTEXT: PENDING_CONTEXT (if available)

ON completion:
    CAPTURE message_to_next → BUFFER as PENDING_CONTEXT

ON timeout or error:
    APPLY Timeout Recovery Policy

# PROMOTE returns outcome: "promoted" (auto-promoted) or "skipped" (skip-promotion INFO signal) or "blocked"
IF outcome == "promoted" OR outcome == "skipped":
    UPDATE metadata.yaml with state: COMPLETE
    STATE = COMPLETE

ELSE IF outcome == "blocked":
    LOG ERROR "Librarian PROMOTE blocked: <outcome_reason>"
    EXIT with error "Knowledge promotion blocked — manual intervention required"
```

### Live Signal Protocol (Mailbox Pattern)

#### Signal Artifacts
- **Inputs**: `.ralph-sessions/<SESSION_ID>/signals/inputs/`
- **Acks**: `.ralph-sessions/<SESSION_ID>/signals/acks/`
- **Processed**: `.ralph-sessions/<SESSION_ID>/signals/processed/`

#### Poll-Signals Routine
1. **Define** `RECOGNIZED_TYPES = [STEER, PAUSE, ABORT, INFO]`
2. **Define** `ALL_RECIPIENTS = [Orchestrator, Executor, Planner, Questioner, Reviewer]`
3. **Ensure** `signals/acks/` exists
4. **List** files in `signals/inputs/` (sort by timestamp ascending)
5. **Read** oldest file content (peek — do not move yet)
6. **Check type** against `RECOGNIZED_TYPES`
7. **If recognized**:
    a. **Check target** field:
         - If `target == ALL`:
            - Apply signal locally
            - Write/refresh ack file `signals/acks/<SIGNAL_ID>/Orchestrator.ack.yaml`
            - Do NOT move the source signal yet
            - If ack files exist for all `ALL_RECIPIENTS`, move to `signals/processed/` and append delivery metadata
            - Continue to next signal
         - If `target == Orchestrator` or `target` is absent → **consume** (proceed to step 7b)
       - If `target` specifies a subagent (e.g., `Executor`, `Reviewer`) → **buffer** the signal:
         - Move file to `signals/processed/`
         - Store signal in `SIGNAL_CONTEXT[<target>]` for delivery at next targeted subagent invocation
         - Do NOT act on it locally
         - Continue to next signal
     b. **Move** file to `signals/processed/` (Atomic concurrency handling)
       - If move fails, skip (another agent took it)
    c. **Act**:
       - **STEER**: Adjust immediate context
       - **PAUSE**: Suspend execution until new signal or user resume
       - **ABORT**: Gracefully terminate
       - **INFO**: Log to context
8. **If unrecognized type**: Skip — leave signal in `inputs/` for targeted agent consumption.
9. **Deliver buffered signals**: When invoking a subagent, attach any signals in `SIGNAL_CONTEXT[<subagent>]` to the invocation context. Clear the buffer after delivery.

#### Target Namespace Standard
- Signal `target` values are **role names only**: `ALL | Orchestrator | Executor | Planner | Questioner | Reviewer | Librarian`.
- Do not encode version in `target` (for example, never `Ralph-v2-*`). Workflow version is inferred from the active runtime/session context.

#### Archive Checkpoints (Exactly When Orchestrator Moves To `signals/processed/`)
```
1. **Poll-Signals, targeted-to-Orchestrator path**:
    - Condition: `type in [STEER, PAUSE, ABORT, INFO]` and `target in [Orchestrator, <absent>]`.
    - Timing: immediately after peek/type/target validation in Poll-Signals step `7b`.
2. **Poll-Signals, targeted-to-subagent routing path**:
    - Condition: `type in [STEER, PAUSE, ABORT, INFO]` and `target` is one of `Executor|Planner|Questioner|Reviewer|Librarian`.
    - Timing: immediately after buffering into `SIGNAL_CONTEXT[target]`.
3. **Poll-Signals, broadcast finalization path (`target: ALL`)**:
    - Condition: ack quorum satisfied for `ALL_RECIPIENTS`.
    - Timing: during Poll-Signals step `7a` finalization check, after Orchestrator writes its own ack.
4. **PROMOTE state-specific path**:
    - Condition: `INFO` signal with `target: Librarian` and `SKIP_PROMOTION:` message prefix detected in `signals/inputs/`.
    - Timing: immediately when consumed in Librarian PROMOTE pre-promote signal check.
5. **Session-end hygiene path (`COMPLETE` transition)**:
    - Condition: residual `target: ALL` signals still in `signals/inputs/`.
    - Timing: right before final exit; archive as `delivery_status: delivered` (quorum met) or `delivery_status: partial` with `unacked_agents`.
```

#### `target: ALL` Invariant
- First reader never archives a `target: ALL` signal.
- Every recipient agent must write exactly one ack file per signal ID.
- Only Orchestrator archives a `target: ALL` signal after all required acks are present.

### Post-Iteration Feedback Protocol

#### Human Initiates Iteration N+1

1. **Create feedback directory:**
   ```powershell
   $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
   mkdir .ralph-sessions/<SESSION_ID>/iterations/<N+1>/feedbacks/$timestamp/
   ```

2. **Add artifacts:**
   ```powershell
   cp app.log .ralph-sessions/<SESSION_ID>/iterations/<N+1>/feedbacks/$timestamp/
   cp screenshot.png .ralph-sessions/<SESSION_ID>/iterations/<N+1>/feedbacks/$timestamp/
   ```

3. **Create structured feedbacks.md:**
   ```markdown
   ---
   iteration: <N+1>
   timestamp: <ISO8601>
   previous_iteration: <N>
   ---
   
   # Feedback Batch: <timestamp>
   
   ## Critical Issues
   - [ ] **ISS-001**: Description
     - Evidence: app.log, lines 45-60
     - Suggested Fix: ...
   
   ## Quality Issues
   - [ ] **Q-001**: Description
   
   ## New Requirements
   - Feature X
   
   ## Artifacts Index
   | File | Description |
   |------|-------------|
   | app.log | Server logs |
   ```

4. **Notify orchestrator:**
   > "Continue session <SESSION_ID> with new feedback"

#### Orchestrator Processes Feedback

On detecting `iterations/<N+1>/feedbacks/*/feedbacks.md`:

1. Record `PREVIOUS_STATE = metadata.yaml.orchestrator.state`
2. Set `ITERATION = N+1`
3. UPDATE `metadata.yaml`:
   - `orchestrator.state: REPLANNING`
   - `orchestrator.previous_state: <PREVIOUS_STATE>`
   - `iteration: <N+1>`
4. Set `STATE = REPLANNING`
5. Enter REPLANNING workflow (Step 4):
   - Planner is invoked to triage feedback intent and create iteration N+1 artifacts
   - Planner returns `replanning_route` to guide Orchestrator routing:
     - `knowledge-promotion`: fast-path to Librarian (PROMOTE), then COMPLETE
     - `full-replanning`: standard replanning pipeline (rebrainstorm → reresearch → update → rebreakdown)

