# Ralph v2 Agents

This directory contains version 2 of the Ralph agents system with significant architectural improvements over v1.
Ralph v1 (or simply "Ralph") agents are already archived in `agents/archived/ralph*.agent.md`.
Do not reference Ralph v1 agents for developing newer Ralph versions.

## Documentation

- **[IMPROVEMENTS.md](IMPROVEMENTS.md)** - Recent improvements (metadata naming, timing tracking, structure simplification)
- **[CRITIQUE.md](CRITIQUE.md)** - Latest review notes and guardrail status

## Quick Comparison: v1 vs v2

| Feature                | v1                                     | v2                                                       |
| ---------------------- | -------------------------------------- | -------------------------------------------------------- |
| **Task Storage**       | Monolithic `tasks.md`                  | Isolated `tasks/<id>.md` files                           |
| **Progress Tracking**  | `progress.md` + inline `✅` in tasks.md | `progress.md` **only** (SSOT)                            |
| **Feedback Loops**     | Manual, unstructured                   | Structured `iterations/<N>/feedbacks/<timestamp>/`       |
| **Replanning**         | Not supported                          | Full `REPLANNING` state with re-brainstorm               |
| **Plan History**       | Single `plan.md`                       | `iterations/<N>/plan.md` with Replanning History section |
| **Task Reports**       | `tasks.<id>-report.md`                 | `iterations/<N>/reports/<id>-report[-r<N>].md`           |
| **Q&A Files**          | `plan.questions.<category>.md`         | `iterations/<N>/questions/<category>.md`                 |
| **Session Metadata**   | `state/current.yaml` in folder         | `metadata.yaml` at session root                          |
| **Iteration Metadata** | `iterations/N/state.yaml`              | `iterations/N/metadata.yaml` with timing                 |
| **Session Review**     | `progress.review[N].md` (v1)           | `iterations/<N>/review.md` (v2)                          |

## Directory Structure

```
agents/ralph-v2/
├── ralph-v2.agent.md              # Orchestrator
├── ralph-v2-planner.agent.md      # Planning agent
├── ralph-v2-questioner.agent.md   # Q&A discovery agent
├── ralph-v2-executor.agent.md     # Task execution agent
├── ralph-v2-reviewer.agent.md     # Quality assurance agent
├── ralph-v2-librarian.agent.md    # Knowledge management subagent
├── LIVE-SIGNALS-DESIGN.md         # Signal protocol design
├── LIVE-SIGNALS-MAP.md            # Signal checkpoint map
├── CRITIQUE.md                    # Review notes and guardrail status
├── IMPROVEMENTS.md                # Historical improvements log
├── appendixes/
│   ├── hooks-integrations.md      # Hooks integration plan (P0-P3 tiers)
│   └── normalization-deep-dive.md # SSOT normalization patterns
├── templates/
│   └── feedbacks.template.md      # Feedback file template
└── README.md                      # This file
```

## Session Structure (v2.2.0)

**Note:** `.ralph-sessions` directory is strictly relative to the **root of the current workspace**.

Session ID Format: `<YYMMDD>-<hhmmss>` (e.g., `260209-143000`)

Each iteration is **self-contained** — all mutable artifacts (plan, tasks, progress, reports, questions) live inside `iterations/<N>/`. Only session-level state (`metadata.yaml`, `signals/`) remains at the session root.

```
.ralph-sessions/<SESSION_ID>/
├── metadata.yaml                  # Session-level state machine SSOT (Orchestrator-owned)
├── signals/                       # Session-level signal mailbox (not iteration-scoped)
│   ├── inputs/                    # Incoming signals from human
│   └── processed/                 # Consumed signals (moved here after processing)
│
├── tests/                         # Ephemeral test artifacts (session-level)
│   └── task-<id>/
│       ├── test-results.log
│       └── screenshot.png
│
└── iterations/                    # Per-iteration container (self-contained)
    ├── 1/
    │   ├── metadata.yaml          # Iteration timing SSOT (Planner/Reviewer)
    │   ├── plan.md                # Current mutable plan for this iteration
    │   ├── progress.md            # SSOT for task status in this iteration
    │   │
    │   ├── tasks/                 # Isolated task files
    │   │   ├── task-1.md
    │   │   ├── task-2.md
    │   │   └── task-N.md
    │   │
    │   ├── reports/               # Task reports
    │   │   ├── task-1-report.md
    │   │   ├── task-2-report-r2.md    # Rework attempt
    │   │   └── task-N-report.md
    │   │
    │   ├── questions/             # Q&A by category
    │   │   ├── technical.md
    │   │   ├── requirements.md
    │   │   ├── constraints.md
    │   │   ├── assumptions.md
    │   │   ├── risks.md
    │   │   └── feedback-driven.md     # Feedback analysis
    │   │
    │   ├── knowledge/             # Diátaxis-categorized knowledge for human review
    │   │   ├── tutorials/         # Learning-oriented walkthroughs
    │   │   ├── how-to/            # Task-oriented guides
    │   │   ├── reference/         # Information-oriented descriptions
    │   │   ├── explanation/       # Understanding-oriented discussion
    │   │   └── index.md           # Knowledge inventory
    │   │
    │   └── review.md              # Session review (if conducted)
    │
    └── 2/                         # NEW ITERATION (after feedback)
        ├── metadata.yaml          # Iteration 2 timing SSOT
        ├── plan.md                # Updated plan with Replanning History section
        ├── progress.md            # Task status for iteration 2
        │
        ├── tasks/                 # Task files for iteration 2
        ├── reports/               # Reports for iteration 2
        ├── questions/             # Questions for iteration 2
        │
        ├── knowledge/             # Diátaxis-categorized knowledge with carry-forward
        │   ├── tutorials/         # Learning-oriented (may include carried items)
        │   ├── how-to/            # Task-oriented
        │   ├── reference/         # Information-oriented
        │   ├── explanation/       # Understanding-oriented
        │   └── index.md           # Knowledge inventory
        │
        ├── feedbacks/             # Structured feedback from human
        │   ├── 20260207-105500/
        │   │   ├── feedbacks.md   # Required
        │   │   ├── app.log        # Optional artifacts
        │   │   └── screenshot.png
        │   └── 20260207-110000/
        │       └── feedbacks.md
        │
        └── review.md              # Iteration 2 review
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
  → Update iterations/<N>/plan.md (append Replanning History section)
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

### 5. Replanning History (replaces Plan Snapshots)

Instead of immutable `plan.iteration-N.md` snapshot files, each replanning cycle appends a **Replanning History** section directly to the iteration's `plan.md`:

```markdown
## Replanning History

### Iteration 2 Replanning (2026-02-07T11:00:00Z)

#### Feedback Summary
- ISS-001: Form submission fails (Critical)

#### Changes
- **Removed**: task-3 (superseded by ISS-001 fix)
- **Added**: task-5 (null check implementation)
- **Modified**: task-2 (updated success criteria)

#### Rationale
Feedback revealed root cause was missing null checks, not schema validation.
```

This preserves the change rationale inline without creating separate snapshot files.

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

- **Artifacts**: `signals/inputs/` (session-level) and `signals/processed/`
- **Signal Types**:

  | Signal    | Category       | Semantics                                           | Polled By                |
  | --------- | -------------- | --------------------------------------------------- | ------------------------ |
  | `STEER`   | Universal      | Re-route workflow (agent adjusts approach)          | Orchestrator + Subagents |
  | `INFO`    | Universal      | Context injection (enrich context, no path change)  | Orchestrator + Subagents |
  | `PAUSE`   | Universal      | Temporary halt (resume later with optional updates) | Orchestrator + Subagents |
  | `ABORT`   | Universal      | Permanent halt (graceful termination with cleanup)  | Orchestrator + Subagents |
  | `APPROVE` | State-specific | Knowledge promotion trigger                         | Orchestrator only        |
  | `SKIP`    | State-specific | Knowledge bypass                                    | Orchestrator only        |

- **Hybrid Polling Model**: Subagents are direct pollers for universal signals (`STEER`, `PAUSE`, `ABORT`, `INFO`) and context consumers for state-specific signals (`APPROVE`, `SKIP`). See [LIVE-SIGNALS-DESIGN.md](LIVE-SIGNALS-DESIGN.md) §4.
- **Target-Aware Routing**: Orchestrator checks `target` field in signals and routes to specific subagents. See [LIVE-SIGNALS-DESIGN.md](LIVE-SIGNALS-DESIGN.md) §2.3.
- **Documentation**:
  - [Design](LIVE-SIGNALS-DESIGN.md)
  - [Implementation Map](LIVE-SIGNALS-MAP.md)
  - [Hooks Integration Plan](appendixes/hooks-integrations.md) (P0-P3 priority tiers)

### 9. Operational Guardrails

- **Schema validation** for `iterations/<N>/progress.md` and `metadata.yaml`
- **Orchestrator-owned state ownership** of `metadata.yaml` (atomic transitions)
- **Single-mode invocations** for all subagents
- **Timeout recovery policy** with sleep backoff and task splitting
- **Reviewer-owned runtime validation** (mandatory for every task, workload-aware)
- **Documentation workloads** explicitly exclude `playwright-cli` in runtime validation
- **Executor design-time validation only** (build/lint/tests)
- **Single task per reviewer invocation**

### 10. Skills Enforcement (New in v2.2.0)

Every subagent proactively discovers and activates relevant skills at runtime via a mandatory **Step 0: Skills Directory Resolution**.

**Hybrid Skill Activation Model**:
1. **Session instructions pre-list**: The Planner pre-lists discovered skills in `<SESSION_ID>.instructions.md` during initialization
2. **Runtime discovery**: Each subagent independently resolves and validates the skills directory at invocation time

**Step 0 Pattern** (all subagents):
1. Resolve `<SKILLS_DIR>` cross-platform:
   - **Windows**: `$env:USERPROFILE\.copilot\skills`
   - **Linux/WSL**: `~/.copilot/skills`
2. Validate with `Test-Path` / `test -d`
3. Set `SKILLS_AVAILABLE` flag; if not found, continue in **degraded mode** (warning, not failure)
4. Load max 3-5 matched skills per invocation (context budget)

**Skill affinities by agent**:
| Agent      | Primary Skills                                 |
| ---------- | ---------------------------------------------- |
| Executor   | Task-specific (varies)                         |
| Reviewer   | `git-atomic-commit` (critical for commit step) |
| Questioner | Task research skills                           |
| Librarian  | `diataxis` (knowledge categorization)          |
| Planner    | Planning-related skills                        |

### 11. Atomic Commits (New in v2.2.0)

The **Reviewer** (not the Executor) executes atomic commits per task after each review passes.

**Workflow**:
1. Reviewer completes review, marks task as `[x]` (qualified)
2. **Step 7: Atomic Commit** runs:
   - Extract `files_modified` from executor's report
   - Selective file staging (`git add` per file — **never** `git add .` or `git add -A`)
   - Verify staging with `git diff --cached --name-only`
   - If `git-atomic-commit` skill is available: invoke in autonomous mode (may produce multiple commits per task)
   - If skill unavailable: fallback to basic conventional commit (`git commit -m "type(scope): subject"`)
3. Commit failure does **NOT** affect review verdict — `[x]` is preserved regardless

**Key design decisions**:
- Executor is NOT responsible for commits (separation of concerns)
- Multiple commits per task are allowed (skill may split by file type)
- Commit status is reported in reviewer output (`commit_status`, `commit_summary`)

### 12. Knowledge Carry-Forward (New in v2.2.0)

Staged knowledge that isn't approved or skipped in the current iteration carries forward to the next iteration.

**Rules**:
- Unapproved knowledge in `iterations/<N>/knowledge/<category>/` carries to `iterations/<N+1>/knowledge/<category>/` (where category is `tutorials`, `how-to`, `reference`, or `explanation`)
- Each carried file gets frontmatter markers: `carried_from_iteration`, `original_staged_at`, `carry_reason`
- **Max carry threshold**: Configurable via `knowledge.max_carry_iterations` (default: 2)
- Files exceeding the threshold are **auto-discarded** with a log entry
- The Librarian reconciles carried knowledge against new iteration context before re-staging
- Contradictions between carried knowledge and new findings result in discard of the carried version

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

User message: "Continue session 260207-120000 with feedbacks"

Ralph-v2:
1. Detect feedbacks in iterations/2/feedbacks/
2. STATE: REPLANNING
3. Invoke plan-rebrainstorm → analyze feedbacks
4. Invoke plan-reresearch → research solutions
5. Invoke plan-update → update iterations/2/plan.md (append Replanning History)
6. Invoke plan-rebreakdown → update iterations/2/tasks/, reset iterations/2/progress.md
7. STATE: BATCHING
8. Continue execution
```

## Agent Reference

| Agent                          | Purpose       | Key Features (v2.2.0)                                               |
| ------------------------------ | ------------- | ------------------------------------------------------------------- |
| `ralph-v2.agent.md`            | Orchestrator  | State machine, target-aware signal routing, skills context passing  |
| `ralph-v2-planner.agent.md`    | Planning      | Isolated task files, Replanning History, REBREAKDOWN mode           |
| `ralph-v2-questioner.agent.md` | Q&A           | Brainstorm/research/feedback-analysis modes, iteration-scoped Q&A   |
| `ralph-v2-executor.agent.md`   | Execution     | STEER decision tree, feedback context, design-time validation only  |
| `ralph-v2-reviewer.agent.md`   | Review        | Atomic commits per task, runtime validation, workload-aware         |
| `ralph-v2-librarian.agent.md`  | Wiki curation | Knowledge staging/promotion, carry-forward, Diátaxis categorization |

## Librarian Usage

- Invocation path: `Ralph-v2` orchestrator invokes `Ralph-v2-Librarian` as a subagent only.
- Direct usage: Not supported (`user-invokable: false`).
- Dual modes:
  - **STAGE**: Extract and stage knowledge to `iterations/<N>/knowledge/` for human review.
  - **PROMOTE**: Promote approved staged content from `iterations/<N>/knowledge/` to `.docs/`.
- Documentation model: Diátaxis structure (`tutorials/`, `how-to/`, `reference/`, `explanation/`).

## File Templates

See `templates/` directory for:
- `feedbacks.template.md` - Structured feedback format

## Version Compatibility

- **v1 agents**: Continue to work with existing v1 sessions
- **v2.0.x–2.1.x sessions**: NOT compatible with v2.2.0 agents (breaking structural change)
- **v2.2.0 agents**: Create and manage v2.2.0 sessions only
- **No cross-compatibility**: v1 cannot read v2 sessions; v2.1.x sessions cannot be used with v2.2.0 agents

## Changelog

### v2.2.0 (2026-02-15)

> **Breaking change**: New session structure is NOT backward-compatible with v2.1.0 sessions. Existing sessions must be completed with v2.1.0 agents or recreated.

**Iteration Scope Normalization**
- All mutable artifacts moved into `iterations/<N>/`: `plan.md`, `tasks/`, `progress.md`, `reports/`, `questions/`
- Session root retains only `metadata.yaml` (state machine SSOT) and `signals/` (session-level mailbox)
- `plan.iteration-N.md` snapshot pattern removed — replaced by inline Replanning History section in `plan.md`
- `delta.md` and `replanning/` directory removed — rationale captured in Replanning History
- `questions/` moved from session root to `iterations/<N>/questions/`

**Signal Protocol Enhancements**
- `STOP` renamed to `ABORT` across all documents
- All 6 signal types defined with clear semantics: `STEER`, `INFO`, `PAUSE`, `ABORT`, `APPROVE`, `SKIP`
- Hybrid polling model: subagents = direct pollers for universal signals, context consumers for state-specific signals
- Target-aware routing: Orchestrator checks `target` field, buffers and routes to specific subagents
- STEER mid-execution decision tree with 3 branches (restart/adjust/escalate)
- ABORT cleanup checklist with 4 explicit steps
- Hooks integration plan with P0-P3 priority tiers (design only)

**Skills Enforcement**
- Mandatory Step 0 (Skills Discovery & Activation) added to all subagents
- Cross-platform skills directory resolution (`$env:USERPROFILE\.copilot\skills` / `~/.copilot/skills`)
- `Test-Path` / `test -d` validation with degraded mode fallback (not hard failure)
- Context budget: max 3-5 skills per invocation
- Hybrid skill activation: session instructions pre-list + runtime discovery

**Atomic Commits**
- Reviewer executes atomic commits per task after review passes (Step 7)
- Selective file staging — only `files_modified` from executor report
- `git-atomic-commit` skill in autonomous mode with fallback to basic conventional commit
- Commit failure does NOT affect review verdict (`[x]` preserved)
- Multiple commits per task allowed (skill splits by file type)

**Knowledge Carry-Forward**
- Unapproved staged knowledge carries forward to next iteration with `carried_from_iteration` marker
- Configurable max carry threshold (`knowledge.max_carry_iterations`, default: 2)
- Auto-discard with log entry when threshold exceeded
- Librarian reconciles carried knowledge against new iteration context
- Knowledge staging uses Diátaxis categories (`tutorials/`, `how-to/`, `reference/`, `explanation/`) with `index.md`

**Agent Updates** (all agents bumped to new versions)
- Orchestrator: target-aware signal routing, skills context passing, `SIGNAL_CONTEXT` in subagent invocations
- Planner: iteration-scoped artifacts, Replanning History template, removed plan snapshots
- Executor: STEER decision tree, signal filtering (universal only), design-time validation
- Reviewer: atomic commit step (Step 7), `commit_status`/`commit_summary` in output contract
- Questioner: iteration-scoped question paths, skills Step 0
- Librarian: knowledge carry-forward with reconciliation, `diataxis` skill affinity

### v2.1.0 (2026-02-14)

**Librarian & Knowledge Pipeline**
- Added `Ralph-v2-Librarian` subagent with dual-mode knowledge pipeline (`STAGE` / `PROMOTE`)
- New orchestrator states: `KNOWLEDGE_EXTRACTION` (State 9) and `KNOWLEDGE_APPROVAL` (State 10)
- Knowledge staging in `iterations/<N>/knowledge/` with human review gate
- `.docs/` wiki updated via Librarian promotion only (no direct writes)
- Diátaxis-based categorization for all wiki content

**Signal Protocol**
- New signal types: `APPROVE` (knowledge promotion) and `SKIP` (knowledge bypass)
- Poll-Signals routine restructured to peek-before-move with `RECOGNIZED_TYPES` allowlist
- State 10 uses `RUN Poll-Signals` + direct read for state-specific signal consumption
- SKIP branch includes explicit `plan-knowledge-approval [C]` write in `progress.md`

**Consistency & Quality**
- State renumbering: `KNOWLEDGE_EXTRACTION` (9), `KNOWLEDGE_APPROVAL` (10), `COMPLETE` (11)
- Progress.md ownership delegation to subagents (Hard Rules)
- Hard Rules exception for orchestrator SKIP signal `[C]` write
- Timeout recovery policy genericized (not executor-specific)
- Knowledge progress initialization at iteration start
- Version unified to v2.x scheme (frontmatter + changelog)
- Documentation alignment across README, LIVE-SIGNALS-DESIGN, and orchestrator

### v2.0.1 (2026-02-10)
- Orchestrator assumes direct ownership of `metadata.yaml` state updates
- Removed `## Current State` redundancy from `progress.md`
- Simplification of state transition logic

### v2.0.0 (2026-02-07)
- Initial v2 release
- Isolated task files architecture
- Structured feedback loops
- REPLANNING state
- Plan snapshots
- SSOT progress tracking
