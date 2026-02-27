# Ralph v2 — Multi-Agent Orchestration System

A feedback-driven, multi-agent system with isolated task files, structured iteration loops, live signal injection, and session-scope knowledge management. v1 agents are archived in `agents/archived/ralph*.agent.md` — do not reference them for new development.

**Current version: v2.9.0**

## Table of Contents

- [Architecture](#architecture)
- [Session Structure](#session-structure)
- [State Machine](#state-machine)
- [Design Principles](#design-principles)
- [Usage](#usage)
- [Related Documentation](#related-documentation)
- [Version History](#version-history)

---

## Architecture

### Agent Directory

```
agents/ralph-v2/
├── ralph-v2.agent.md              # Orchestrator (state machine, routing)
├── ralph-v2-planner.agent.md      # Planning (plan.md, tasks, waves)
├── ralph-v2-questioner.agent.md   # Q&A discovery (brainstorm/research/feedback-analysis)
├── ralph-v2-executor.agent.md     # Task execution (implementation, design-time validation)
├── ralph-v2-reviewer.agent.md     # Quality assurance (review, COMMIT, runtime validation)
├── ralph-v2-librarian.agent.md    # Knowledge management (STAGE/PROMOTE/CURATE)
├── README.md                      # This file (single entry point)
└── docs/
    ├── design/
    │   ├── live-signals-design.md # Signal protocol design (types, routing, ack quorum)
    │   ├── live-signals-map.md    # Signal checkpoint implementation map
    │   └── critique.md            # Workflow critique and guardrail status
    ├── reference/
    │   ├── hooks-integrations.md  # Hooks integration plan (P0-P3 tiers)
    │   └── normalization.md       # SSOT normalization patterns
    ├── specs/
    │   └── stop-hook-finalization.spec.md  # Stop hook metadata finalization spec
    └── templates/
        └── feedbacks.template.md  # Feedback file template
```

### Agent Reference

| Agent | Role | Modes | Key Responsibilities |
|-------|------|-------|---------------------|
| **Orchestrator** | Routing | — | State machine transitions, subagent invocation, `metadata.yaml` ownership, signal routing |
| **Planner** | Planning | INITIALIZE, TASK_BREAKDOWN, UPDATE, REBREAKDOWN, SPLIT_TASK, UPDATE_METADATA, REPAIR_STATE | Plan creation, task decomposition, wave dependency reasoning, replanning |
| **Questioner** | Discovery | brainstorm, research, feedback-analysis | Q&A generation, research, feedback analysis |
| **Executor** | Implementation | — | Task execution, design-time validation (build/lint/tests) |
| **Reviewer** | Quality | TASK_REVIEW, COMMIT, SESSION_REVIEW, TIMEOUT_FAIL | Code review, atomic commits (hunk-level staging), session review |
| **Librarian** | Knowledge | STAGE, PROMOTE, CURATE | Knowledge extraction, Diátaxis classification, approval gate, wiki promotion |

### Ownership Model

| Artifact | Owner (write) | Notes |
|----------|--------------|-------|
| `metadata.yaml` | Planner (init), Orchestrator (transitions) | Session-level state machine SSOT |
| `iterations/<N>/metadata.yaml` | Planner (init), Reviewer (update) | Iteration timing SSOT |
| `iterations/<N>/plan.md` | Planner | Mutable plan per iteration |
| `iterations/<N>/tasks/*.md` | Planner | One file per task |
| `iterations/<N>/progress.md` | Planner, Questioner, Executor, Reviewer, Librarian | SSOT for all task/planning/knowledge status |
| `iterations/<N>/reports/*` | Executor, Reviewer | Task and review reports |
| `iterations/<N>/questions/*` | Questioner | Per-category Q&A files |
| `knowledge/` | Librarian | Session-scope Diátaxis knowledge staging |
| `signals/` | Human (write), Agents (ack), Orchestrator (route) | Session-level mailbox |

---

## Session Structure

`.ralph-sessions/` is always relative to the **workspace root**. Session ID format: `<YYMMDD>-<hhmmss>`.

Each iteration is **self-contained** — all mutable artifacts live inside `iterations/<N>/`. Session-level state (`metadata.yaml`, `signals/`, `knowledge/`) stays at the session root.

```
.ralph-sessions/<SESSION_ID>/
├── metadata.yaml                  # Session state machine SSOT (Orchestrator-owned)
├── signals/                       # Session-level signal mailbox
│   ├── inputs/                    # Incoming signals from human
│   ├── acks/                      # Acknowledgments for broadcast signals
│   └── processed/                 # Consumed signals (moved after processing)
│
├── knowledge/                     # Session-scope Diátaxis knowledge
│   ├── tutorials/
│   ├── how-to/
│   ├── reference/
│   ├── explanation/
│   └── index.md                   # Knowledge inventory (approved + pending)
│
└── iterations/
    └── <N>/                       # Self-contained iteration
        ├── metadata.yaml          # Iteration timing SSOT
        ├── plan.md                # Mutable plan (with Replanning History)
        ├── progress.md            # SSOT for task/planning status
        ├── tasks/                 # One file per task (task-<id>.md)
        ├── reports/               # Task reports (task-<id>-report[-r<N>].md)
        ├── questions/             # Q&A by category
        ├── tests/                 # Ephemeral test artifacts (tests/task-<id>/)
        ├── feedbacks/             # Structured feedback (feedbacks/<timestamp>/)
        └── review.md              # Iteration review
```

---

## State Machine

```
INITIALIZING ─── Planner (INITIALIZE) creates session structure
       │
       ▼
   PLANNING ──── Questioner (brainstorm/research) → Planner (TASK_BREAKDOWN)
       │
       ▼
   BATCHING ──── Build waves from task dependencies
       │
       ▼
EXECUTING_BATCH ── Executor runs tasks → marks [P]
       │
       ▼
REVIEWING_BATCH ── Reviewer validates → [x] + COMMIT or [F]
       │              │
       │              └── loops back to BATCHING until all waves done
       ▼
SESSION_REVIEW ── Reviewer (SESSION_REVIEW) → review.md
       │
       ▼
KNOWLEDGE_EXTRACTION ── Librarian (STAGE) → knowledge/
       │                    │
       │                    └── 0 items staged → skip to COMPLETE
       ▼
CURATE ── Librarian (CURATE) → auto-promotes by default
       │                    │
       │                    ├── Default: auto-promote to .docs/ → COMPLETE
       │                    ├── SKIP signal → bypass promotion → COMPLETE
       │                    └── Post-iteration feedback → REPLANNING
       ▼
   COMPLETE ──── All tasks [x]/[C], or awaiting feedback
       │
       ▼ (human provides feedbacks/)
  REPLANNING ──── Planner triages → Questioner → Planner → back to BATCHING
```

**Replanning routes:**
- `full-replanning` — Questioner (feedback-analysis, research) → Planner (UPDATE, REBREAKDOWN) → BATCHING
- `knowledge-promotion` — Fast-path from CURATE: Librarian (PROMOTE) → COMPLETE

---

## Design Principles

### Isolated Task Files

One file per task in `tasks/<id>.md` with YAML frontmatter (`id`, `iteration`, `type`, `created_at`), dependencies, and success criteria. Eliminates write contention and enables parallel execution.

### Single Source of Truth (SSOT) Progress

`progress.md` is the **only** location for task status. Status markers: `[ ]` not started, `[/]` in progress, `[P]` pending review, `[x]` completed, `[F]` failed, `[C]` cancelled/skipped.

### Structured Feedback Loops

Two protocols for human feedback:

1. **Live Signal Protocol** (session active) — Drop YAML signal files into `signals/inputs/` for real-time steering
2. **Post-Iteration Feedback Protocol** (session at rest) — Create `iterations/<N+1>/feedbacks/<timestamp>/feedbacks.md` with artifacts

### Live Signals

Six signal types in two categories:

| Signal | Category | Semantics | Polled By |
|--------|----------|-----------|-----------|
| `STEER` | Universal | Re-route workflow | Orchestrator + Subagents |
| `INFO` | Universal | Context injection | Orchestrator + Subagents |
| `PAUSE` | Universal | Temporary halt | Orchestrator + Subagents |
| `ABORT` | Universal | Permanent halt with cleanup | Orchestrator + Subagents |
| `APPROVE` | State-specific | Knowledge promotion trigger | Librarian (CURATE) |
| `SKIP` | State-specific | Knowledge bypass | Librarian (CURATE) |

Target-aware routing: Orchestrator checks `target` field and routes to specific subagents. Broadcast signals (`target: ALL`) require ack quorum from all recipients before archival.

### Atomic Commits (COMMIT Mode)

Reviewer executes commits via dedicated COMMIT mode with hunk-level analysis:
- `git diff` per file → classify hunks (TASK-RELEVANT / UNRELATED / AMBIGUOUS)
- Partial staging via `git apply --cached` — never `git add .` or `git add -A`
- `git-atomic-commit` skill for conventional commit generation
- Commit failure does NOT affect review verdict (`[x]` preserved)

### Session-Scope Knowledge

Knowledge persists at `knowledge/` (session root) across all iterations:
- Staged files include `approved: false` frontmatter; promoted files get `approved: true` + timestamp
- **Default auto-approval**: Knowledge is auto-promoted to `.docs/` at each iteration unless overridden by a SKIP signal
- Approved knowledge is not re-extracted on subsequent iterations
- Librarian reconciles new knowledge against existing approved items
- Diátaxis categorization: `tutorials/`, `how-to/`, `reference/`, `explanation/`

### Skills Enforcement

All subagents discover and load skills at runtime via 4-step reasoning:
1. Check agent instructions for skill affinities
2. Check task context for explicitly mentioned skills
3. Scan `<SKILLS_DIR>` and match descriptions
4. Load only directly relevant skills (typically 1-3)

| Agent | Primary Skill Affinities |
|-------|--------------------------|
| Reviewer | `git-atomic-commit` |
| Librarian | `diataxis` |
| Others | Task-specific (varies) |

### Operational Guardrails

- **Schema validation** for `progress.md` and `metadata.yaml`
- **Orchestrator owns only `metadata.yaml`** — all other writes delegated to subagents
- **Single-mode invocations** — each subagent call runs exactly one mode
- **Timeout recovery** — exponential backoff (30s → 60s → 60s → SPLIT_TASK)
- **Reviewer-owned runtime validation** — mandatory for every task, workload-aware
- **Single task per reviewer invocation**

---

## Usage

### Starting a Session

```
User: "@Ralph-v2 Create a Blazor component library"

Orchestrator:
1. INITIALIZING → Planner (INITIALIZE) → creates session structure
2. PLANNING → Questioner (brainstorm/research) → Planner (TASK_BREAKDOWN)
3. BATCHING → EXECUTING_BATCH → REVIEWING_BATCH → ...
```

### Providing Feedback

```powershell
# 1. Create feedback directory for next iteration
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
mkdir .ralph-sessions/<SESSION_ID>/iterations/<N+1>/feedbacks/$timestamp/

# 2. Add evidence artifacts
cp error.log .ralph-sessions/<SESSION_ID>/iterations/<N+1>/feedbacks/$timestamp/

# 3. Create feedbacks.md (see templates/feedbacks.template.md)
code .ralph-sessions/<SESSION_ID>/iterations/<N+1>/feedbacks/$timestamp/feedbacks.md

# 4. Resume: "Continue session <SESSION_ID> with new feedback"
```

### Sending Live Signals

```powershell
$ts = Get-Date -Format "yyMMdd-HHmmssK" -replace ":", ""
Set-Content ".ralph-sessions/<SESSION_ID>/signals/inputs/signal.$ts.yaml" @"
type: APPROVE       # STEER | INFO | PAUSE | ABORT | APPROVE | SKIP
target: ALL          # ALL | Orchestrator | Executor | Planner | Questioner | Reviewer | Librarian
message: "Knowledge looks good"
created_at: $(Get-Date -Format "yyyy-MM-ddTHH:mm:ssK")
"@
```

### Timestamp Commands

| Format | Windows (PowerShell) | Linux/WSL (bash) |
|--------|---------------------|------------------|
| Session ID `<YYMMDD-hhmmss>` | `Get-Date -Format "yyMMdd-HHmmss"` | `TZ=Asia/Ho_Chi_Minh date +"%y%m%d-%H%M%S"` |
| ISO 8601 with offset | `Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"` | `TZ=Asia/Ho_Chi_Minh date +"%Y-%m-%dT%H:%M:%S%z"` |

---

## Related Documentation

| Document | Description |
|----------|-------------|
| [docs/design/live-signals-design.md](docs/design/live-signals-design.md) | Signal protocol design (types, routing, ack quorum) |
| [docs/design/live-signals-map.md](docs/design/live-signals-map.md) | Signal checkpoint implementation map |
| [docs/design/critique.md](docs/design/critique.md) | Workflow critique and guardrail status |
| [docs/reference/hooks-integrations.md](docs/reference/hooks-integrations.md) | Hooks integration plan (P0-P3 tiers) |
| [docs/reference/normalization.md](docs/reference/normalization.md) | SSOT normalization patterns |
| [docs/specs/stop-hook-finalization.spec.md](docs/specs/stop-hook-finalization.spec.md) | Stop hook metadata finalization spec |
| [docs/templates/feedbacks.template.md](docs/templates/feedbacks.template.md) | Feedback file template |

---

## Version History

### v2.9.0 (2026-02-27)

**Rename & Consistency Pass**
- Renamed `KNOWLEDGE_APPROVAL` → `CURATE` across all agent files and documentation (avoids collision with APPROVE signal type)
- Renamed `REBREAKDOWN_TASK` → `SPLIT_TASK` across all agent files and documentation (structural disambiguation from REBREAKDOWN mode)
- Added Planner disambiguation docs for REBREAKDOWN vs SPLIT_TASK
- Clarified SOURCE_ITERATION semantics in Librarian (traceability marker, not iteration-scoped storage)
- Version bump 2.8.0 → 2.9.0 across all agent files
- README version reconciled from stale v2.5.0 to v2.9.0 (v2.6.0–v2.8.0 history not captured)

### v2.5.0 (2026-02-27)

**Documentation Restructure**
- Reorganized flat documentation files into `docs/` hierarchy: `docs/design/`, `docs/reference/`, `docs/specs/`, `docs/templates/`
- Moved `LIVE-SIGNALS-DESIGN.md`, `LIVE-SIGNALS-MAP.md`, `CRITIQUE.md` → `docs/design/`
- Moved `appendixes/hooks-integrations.md` → `docs/reference/hooks-integrations.md`
- Moved `appendixes/normalization-deep-dive.md` → `docs/reference/normalization.md` (renamed)
- Moved `specs/`, `templates/` → `docs/specs/`, `docs/templates/`
- Removed empty `appendixes/`, `specs/`, `templates/` directories
- README is now the single entry point for all documentation

**Default Knowledge Auto-Approval**
- Librarian now auto-promotes staged knowledge to `.docs/` by default (no APPROVE signal required)
- CURATE state transitions directly to auto-promote unless overridden by SKIP signal
- Reduces friction for knowledge persistence across iterations

**Subagent Template Standardization**
- All subagent files now follow a consistent XML-tagged template structure
- Canonical tag order: `<persona>`, `<artifacts>`, `<rules>`, `<workflow>`, `<signals>`, `<contract>`
- Orchestrator uses `<stateMachine>` in place of `<workflow>`
- Markdown content within XML tags; YAML frontmatter unchanged

### v2.4.0 (2026-02-27)

**CURATE Delegation to Librarian**
- Librarian now owns the full CURATE gate (signal polling, PROMOTE/SKIP execution, `progress.md` marking)
- New Librarian mode: `CURATE` — encapsulates approval signal reading, promotion, skip, and post-iteration feedback detection
- Orchestrator no longer directly marks `plan-knowledge-approval` — removed Hard Rules exception
- `plan-knowledge-approval` now supports `[/]` (in-progress) status set by Librarian
- Librarian returns structured `outcome` field: `approved`, `skipped`, `awaiting`, or `replanning`

**README Restructure**
- Reorganized as: Architecture → Session Structure → State Machine → Design Principles → Usage → Related Docs → Version History
- Consolidated 12 numbered "Key Improvements" sections into focused Design Principles
- Removed stale v1 vs v2 comparison table
- Moved verbose changelog details to IMPROVEMENTS.md

### v2.3.0 (2026-02-16)

> Breaking: NOT backward-compatible with v2.2.0 sessions.

- Session-scope `knowledge/` replaces iteration-scope `iterations/<N>/knowledge/` — eliminated carry-forward logic
- COMMIT extracted from Reviewer's TASK_REVIEW Step 7 into dedicated mode with hunk-level staging
- 4-step reasoning-based skill discovery replaces numeric caps and pre-listed skills
- Structured `plan.md` template (7 mandatory sections) with self-validation
- Enhanced dependency reasoning (4 sub-steps: shared resource, read-after-write, interface/contract, ordering)

### v2.2.0 (2026-02-15)

> Breaking: NOT backward-compatible with v2.1.0 sessions.

- Iteration scope normalization — all mutable artifacts under `iterations/<N>/`
- Signal protocol enhancements (6 types, hybrid polling, target-aware routing)
- Skills enforcement (mandatory Step 0, cross-platform resolution, degraded mode)
- Atomic commits via Reviewer (selective staging, `git-atomic-commit` skill)
- Knowledge carry-forward with reconciliation and max-carry threshold

### v2.1.0 (2026-02-14)

- Added Librarian subagent with `STAGE`/`PROMOTE` knowledge pipeline
- KNOWLEDGE_EXTRACTION and CURATE states
- Signal types: `APPROVE`, `SKIP`

### v2.0.x (2026-02-07 – 2026-02-10)

- Initial v2: isolated task files, structured feedback loops, REPLANNING state, SSOT progress tracking
