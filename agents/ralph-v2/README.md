# Ralph v2 Agents

This directory contains version 2 of the Ralph agents system with significant architectural improvements over v1.

## Documentation

- **[IMPROVEMENTS.md](IMPROVEMENTS.md)** - Recent improvements (metadata naming, timing tracking, structure simplification)
- **[CRITIQUE.md](CRITIQUE.md)** - Latest review notes and guardrail status

## Quick Comparison: v1 vs v2

| Feature                | v1                                     | v2                                                    |
| ---------------------- | -------------------------------------- | ----------------------------------------------------- |
| **Task Storage**       | Monolithic `tasks.md`                  | Isolated `tasks/<id>.md` files                        |
| **Progress Tracking**  | `progress.md` + inline `✅` in tasks.md | `progress.md` **only** (SSOT)                         |
| **Feedback Loops**     | Manual, unstructured                   | Structured `iterations/<N>/feedbacks/<timestamp>/`    |
| **Replanning**         | Not supported                          | Full `REPLANNING` state with re-brainstorm            |
| **Plan History**       | Single `plan.md`                       | `plan.md` + immutable `plan.iteration-N.md` snapshots |
| **Task Reports**       | `tasks.<id>-report.md`                 | `reports/<id>-report[-r<N>].md`                       |
| **Q&A Files**          | `plan.questions.<category>.md`         | `questions/<category>.md`                             |
| **Session Metadata**   | `state/current.yaml` in folder         | `metadata.yaml` at session root                       |
| **Iteration Metadata** | `iterations/N/state.yaml`              | `iterations/N/metadata.yaml` with timing              |
| **Session Review**     | `progress.review[N].md` (v1)           | `iterations/<N>/review.md` (v2)                       |

## Directory Structure

```
agents/v2/
├── ralph-v2.agent.md              # Orchestrator
├── ralph-v2-planner.agent.md      # Planning agent
├── ralph-v2-questioner.agent.md   # Q&A discovery agent
├── ralph-v2-executor.agent.md     # Task execution agent
├── Ralph-v2-Reviewer.agent.md     # Quality assurance agent
├── templates/
│   └── feedbacks.template.md      # Feedback file template
└── README.md                      # This file
```

## Session Structure (v2)

**Note:** `.ralph-sessions` directory is strictly relative to the **root of the current workspace**.

Session ID Format: `<YYMMDD>-<hhmmss>` (e.g., `260209-143000`)

```
.ralph-sessions/<SESSION_ID>/
├── plan.md                        # Current mutable plan
├── plan.iteration-1.md            # Immutable snapshot
├── plan.iteration-2.md            # Immutable snapshot
├── progress.md                    # SSOT for task status
├── metadata.yaml                  # Session metadata (Managed by Planner/Reviewer)
│
├── tasks/                         # Isolated task files
│   ├── task-1.md
│   ├── task-2.md
│   └── task-N.md
│
├── reports/                       # Task reports
│   ├── task-1-report.md
│   ├── task-2-report-r2.md        # Rework attempt
│   └── task-N-report.md
│
├── questions/                     # Q&A by category
│   ├── technical.md
│   ├── requirements.md
│   ├── constraints.md
│   ├── assumptions.md
│   ├── risks.md
│   └── feedback-driven.md         # NEW: Feedback analysis
│
├── tests/                         # Test artifacts
│   └── task-<id>/
│       ├── test-results.log
│       └── screenshot.png
│
└── iterations/                    # Per-iteration container
    ├── 1/
    │   ├── metadata.yaml          # Iteration state with timing (Planner/Reviewer)
    │   ├── review.md              # Session review (if conducted)
    │   └── artifacts/             # Consolidated artifacts for wiki promotion
    │
    └── 2/                         # NEW ITERATION
        ├── metadata.yaml          # Iteration 2 state with timing
        ├── review.md              # Iteration 2 review
        ├── artifacts/             # Consolidated artifacts
        ├── feedbacks/             # Structured feedback
        │   ├── 20260207-105500/
        │   │   ├── feedbacks.md   # Required
        │   │   ├── app.log        # Optional artifacts
        │   │   └── screenshot.png
        │   └── 20260207-110000/
        │       └── feedbacks.md
        └── replanning/
            ├── delta.md           # Plan changes
            └── rationale.md       # Why changes made
```

## Key Improvements

### 1. Isolated Task Files

**v1 Problem**: All tasks in one `tasks.md` file - contention during parallel execution, hard to query.

**v2 Solution**: One file per task in `tasks/<id>.md`:

```markdown
---
id: task-1
iteration: 1
type: Sequential
created_at: 2026-02-07T10:00:00Z
---

# Task: task-1

## Title
Create feature X

## Files
- src/feature-x.cs

## Objective
Implement feature X

## Success Criteria
- [ ] Criterion 1
- [ ] Criterion 2

## Dependencies
depends_on: []
inherited_by: [task-2]
```

**Benefits**:
- No write contention during parallel execution
- File system is the index - fast queries
- Each task is independently versioned

### 2. SSOT for Progress

**v1 Problem**: Status markers in both `tasks.md` and `progress.md`.

**v2 Solution**: Status **only** in `progress.md`:

```markdown
# Progress

## Legend
- `[ ]` Not started
- `[/]` In progress
- `[P]` Pending review
- `[x]` Completed
- `[F]` Failed

## Tasks (Iteration 2)
- [x] task-1 (Attempt 1, Iteration 1, qualified: 2026-02-07T10:00Z)
- [F] task-2 (Attempt 1, Iteration 1, failed: 2026-02-07T10:30Z)
- [ ] task-2 (Attempt 2, Iteration 2, reset: 2026-02-07T11:00Z)
- [ ] task-3 (Attempt 1, Iteration 2)

## Iterations
| Iteration | Status     | Tasks | Feedbacks       |
| --------- | ---------- | ----- | --------------- |
| 1         | Complete   | 1/2   | N/A             |
| 2         | Replanning | 0/2   | 20260207-110000 |

## Current State
state: REPLANNING
iteration: 2
```

### 3. Structured Feedback Loops

**v1 Problem**: No structured way to provide feedback for failed tasks.

**v2 Solution**: Dedicated `iterations/<N>/feedbacks/<timestamp>/` directory:

1. **Create feedback directory**:
   ```powershell
   mkdir .ralph-sessions/<SESSION_ID>/iterations/2/feedbacks/20260207-110000/
   ```

2. **Copy artifacts**:
   ```powershell
   cp app.log .ralph-sessions/<SESSION_ID>/iterations/2/feedbacks/20260207-110000/
   cp screenshot.png .ralph-sessions/<SESSION_ID>/iterations/2/feedbacks/20260207-110000/
   ```

3. **Create structured feedbacks.md** (use template in `templates/feedbacks.template.md`):
   ```markdown
   ---
   iteration: 2
   timestamp: 2026-02-07T11:00:00Z
   ---

   # Feedback Batch: 20260207-110000

   ## Critical Issues
   - [ ] **ISS-001**: Form submission fails
     - Evidence: app.log, lines 45-60
     - Suggested Fix: Add null checks

   ## Artifacts Index
    | File    | Description |
    | ------- | ----------- |
    | app.log | Server logs |
   ```

4. **Notify orchestrator**:
   > "Continue session <SESSION_ID> with new feedback"

### 4. REPLANNING State

**v1 Problem**: Failed tasks just get reworked without re-planning.

**v2 Solution**: Full replanning workflow:

```
COMPLETE → (feedbacks/) → REPLANNING
  ↓
plan-rebrainstorm → Ralph-v2-Questioner
  → Analyze feedbacks, generate questions
  ↓
plan-reresearch → Ralph-v2-Questioner
  → Research solutions to feedback issues
  ↓
plan-update → Ralph-v2-Planner
  → Update plan.md, create plan.iteration-N.md
  ↓
plan-rebreakdown → Ralph-v2-Planner
  → Update tasks, reset failed tasks [F] → [ ]
  ↓
BATCHING → ...
```

**Benefits**:
- Validate assumptions that failed
- Research solutions before implementation
- Update plan based on learnings
- Address root causes, not symptoms

### 5. Plan Snapshots

Each iteration creates an immutable snapshot:

```
plan.md              # Current mutable plan
plan.iteration-1.md  # Snapshot after iteration 1
plan.iteration-2.md  # Snapshot after iteration 2
metadata.yaml        # Session metadata
```

This preserves history and enables comparison between iterations.

### 6. Iteration Timing

Each iteration's `metadata.yaml` tracks start and end times:

```yaml
# iterations/1/metadata.yaml
iteration: 1
started_at: 2026-02-07T10:00:00Z
planning_complete: true
planning_completed_at: 2026-02-07T10:30:00Z
completed_at: 2026-02-07T12:15:00Z
tasks_defined: 5
```

**Duration calculation**: `completed_at - started_at`
- Planning duration: `planning_completed_at - started_at`
- Execution duration: `completed_at - planning_completed_at`

### 7. Session Review per Iteration

Each iteration can have a review document:

```markdown
# iterations/N/review.md

Review for iteration N, documenting:
- Goal achievement
- Task success rates
- Iteration duration
- Gaps identified
- Recommendations
```

### 8. Live Signal Injection (Hot Steering)

**v1 Problem**: Users can only intervene during replanning or after failure.

**v2 Solution**: Asynchronous "Live Signals" (Mailbox Pattern) allowed during execution.

- **Artifacts**: `signals/inputs/` and `signals/processed/`
- **Actions**: `STEER` (correct), `PAUSE` (hold), `STOP` (abort), `INFO` (context)
- **Documentation**:
  - [Design](LIVE-SIGNALS-DESIGN.md)
  - [Implementation Map](LIVE-SIGNALS-MAP.md)

### 9. Operational Guardrails (New)

- **Schema validation** for `progress.md` and `metadata.yaml`
- **Single-mode invocations** for all subagents
- **Timeout recovery policy** with sleep backoff and task splitting
- **Reviewer-owned runtime validation** (mandatory for every task)
- **Executor compile-time validation only** (build/lint/tests)
- **Single task per reviewer invocation**

## Migration from v1

### For New Sessions

Simply use the v2 agents:
1. Reference `agents/v2/ralph-v2.agent.md` in your prompt
2. The orchestrator will create v2 structure automatically

### For Existing v1 Sessions

Option 1: **Continue with v1** (recommended for active sessions)
- v1 agents remain functional
- No migration needed

Option 2: **Migrate to v2** (for important sessions)
Manual migration steps:
1. Parse `tasks.md` into individual `tasks/<id>.md` files
2. Move reports to `reports/` directory
3. Promote `state/current.yaml` to `metadata.yaml` at session root
4. Rename `iterations/*/state.yaml` to `iterations/*/metadata.yaml`
5. Update `progress.md` to v2 format
6. Add timing fields to iteration metadata

## Usage Examples

### Starting a New Session

```markdown
User: "@Ralph-v2 Create a Blazor component library"

Ralph-v2:
1. STATE: INITIALIZING
2. Invoke Ralph-v2-Planner (MODE: INITIALIZE)
3. Create v2 session structure
4. Proceed to PLANNING
```

### Timeout Recovery (Operational)

If a subagent times out, the orchestrator uses sleep backoff before retrying:

- **Windows (PowerShell):** `Start-Sleep -Seconds 30` then `Start-Sleep -Seconds 60`
- **Linux/WSL (bash):** `sleep 30` then `sleep 60`

After repeated failures, the orchestrator invokes `REBREAKDOWN_TASK` to split the task.

### Local Timestamp Commands

Use these commands for local timestamps across the workflow:

- **SESSION_ID format `<YYMMDD>-<hhmmss>`**
  - **Windows (PowerShell):** `Get-Date -Format "yyMMdd-HHmmss"`
  - **Linux/WSL (bash):** `date +"%y%m%d-%H%M%S"`

- **ISO8601 local timestamp (with offset)**
  - **Windows (PowerShell):** `Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"`
  - **Linux/WSL (bash):** `date +"%Y-%m-%dT%H:%M:%S%z"`

### Providing Feedback for Failed Task

```powershell
# After task-2 fails in iteration 1

# 1. Create feedback directory
mkdir .ralph-sessions/260207-120000/iterations/2/feedbacks/20260207-130000/

# 2. Add artifacts
cp C:\temp\error.log .ralph-sessions/260207-120000/iterations/2/feedbacks/20260207-130000/

# 3. Create feedbacks.md
code .ralph-sessions/260207-120000/iterations/2/feedbacks/20260207-130000/feedbacks.md

# 4. Notify orchestrator
```

User message: "Continue session 260207-120000 with feedback"

Ralph-v2:
1. Detect feedbacks in iterations/2/feedbacks/
2. STATE: REPLANNING
3. Invoke plan-rebrainstorm → analyze feedbacks
4. Invoke plan-reresearch → research solutions
5. Invoke plan-update → update plan.md, create plan.iteration-1.md
6. Invoke plan-rebreakdown → update tasks/task-2.md, reset progress.md
7. STATE: BATCHING
8. Continue execution
```

## Agent Reference

| Agent                          | Purpose      | Key Differences from v1               |
| ------------------------------ | ------------ | ------------------------------------- |
| `ralph-v2.agent.md`            | Orchestrator | REPLANNING state, feedback detection  |
| `ralph-v2-planner.agent.md`    | Planning     | Isolated task files, REBREAKDOWN mode |
| `ralph-v2-questioner.agent.md` | Q&A          | feedback-analysis mode                |
| `ralph-v2-executor.agent.md`   | Execution    | Feedback context awareness            |
| `ralph-v2-reviewer.agent.md`   | Review       | Feedback resolution validation        |

## File Templates

See `templates/` directory for:
- `feedbacks.template.md` - Structured feedback format

## Version Compatibility

- **v1 agents**: Continue to work with existing v1 sessions
- **v2 agents**: Create and manage v2 sessions only
- **No cross-compatibility**: v1 cannot read v2 sessions, v2 cannot read v1 sessions

## Changelog

### v2.0.0 (2026-02-07)
- Initial v2 release
- Isolated task files architecture
- Structured feedback loops
- REPLANNING state
- Plan snapshots
- SSOT progress tracking
