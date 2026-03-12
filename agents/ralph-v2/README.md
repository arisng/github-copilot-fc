# Ralph v2 — Multi-Agent Orchestration System

A feedback-driven, multi-agent system with isolated task files, structured iteration loops, live signal injection, and session-scope knowledge management. v1 agents are archived in `agents/.archived/ralph*.agent.md` — do not reference them for new development.

**Current version: v2.13.0**

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
agents/
└── ralph-v2/
    ├── README.md
    ├── instructions/
    │   ├── ralph-v2-orchestrator.instructions.md          # Orchestrator core (control-plane logic stays inline)
    │   ├── ralph-v2-planner.instructions.md
    │   ├── ralph-v2-questioner.instructions.md
    │   ├── ralph-v2-executor.instructions.md
    │   ├── ralph-v2-reviewer.instructions.md              # Compressed to ~26K body (fits CLI 30K limit)
    │   └── ralph-v2-librarian.instructions.md             # Compressed to ~27K body (fits CLI 30K limit)
    ├── vscode/
    │   ├── ralph-v2-orchestrator-VSCode.agent.md
    │   ├── ralph-v2-executor-VSCode.agent.md
    │   ├── ralph-v2-planner-VSCode.agent.md
    │   ├── ralph-v2-questioner-VSCode.agent.md
    │   ├── ralph-v2-reviewer-VSCode.agent.md
    │   └── ralph-v2-librarian-VSCode.agent.md
    └── cli/
        ├── .plugin-managed                                # Marker: agents here are published via plugin only
        ├── ralph-v2-orchestrator-CLI.agent.md
        ├── ralph-v2-executor-CLI.agent.md
        ├── ralph-v2-planner-CLI.agent.md
        ├── ralph-v2-questioner-CLI.agent.md
        ├── ralph-v2-reviewer-CLI.agent.md
        └── ralph-v2-librarian-CLI.agent.md
```

> **Note**: `specs/`, `docs/`, and shared files remain at the `ralph-v2/` root. The normative Ralph workflow contract lives under `openspec/specs/ralph-v2-orchestration/`; the files under `agents/ralph-v2/` summarize and normalize that contract for public Ralph-facing surfaces.

```
agents/ralph-v2/
├── specs/                         # Feature specifications (YAML frontmatter)
│   ├── live-signals.spec.md       # Live signal protocol spec (v2.10.0, implemented)
│   ├── normalization.spec.md      # SSOT normalization spec (v2.2.0, implemented)
│   └── ralph-v2-stop-hook-metadata-finalization.spec.md  # Stop hook finalization spec (implemented)
└── docs/
    ├── design/
    │   └── critique.md            # Workflow critique and guardrail status
    ├── reference/
    │   └── hooks-integrations.md  # Hooks integration plan (P0-P3 tiers)
    └── templates/
        └── feedbacks.template.md  # Feedback file template
```

### Instruction Files

All subagents load their behaviour from shared `instructions/` files. The GitHub Copilot CLI enforces a **30,000-character maximum on the Markdown body** (YAML frontmatter is excluded). Ralph-v2 now follows a harness-engineering split: control-plane logic stays inline in the agent instructions, while bulky protocol and template references move into Ralph-specific skills that the agents load on demand.

| File                                    | Purpose                                                                                                   | Body (approx) |
| --------------------------------------- | --------------------------------------------------------------------------------------------------------- | ------------- |
| `ralph-v2-orchestrator.instructions.md` | Orchestrator core — state machine, subagent routing, critique loop, knowledge extraction routing          | ~28K          |
| `ralph-v2-planner.instructions.md`      | Planner modes: INITIALIZE, TASK_BREAKDOWN, UPDATE, REBREAKDOWN, SPLIT_TASK, UPDATE_METADATA, REPAIR_STATE | ~28K          |
| `ralph-v2-questioner.instructions.md`   | Questioner modes: brainstorm, research, feedback-analysis                                                 | ~16K          |
| `ralph-v2-executor.instructions.md`     | Executor — task implementation, signal polling, report structure                                          | ~12K          |
| `ralph-v2-reviewer.instructions.md`     | Reviewer modes: TASK_REVIEW, ITERATION_REVIEW, SESSION_REVIEW, COMMIT, TIMEOUT_FAIL                       | ~26K          |
| `ralph-v2-librarian.instructions.md`    | Librarian modes: EXTRACT, STAGE, PROMOTE, COMMIT                                                          | ~27K          |

> **No CLI-trimmed variants**: Previously `ralph-v2-reviewer.cli-embed.instructions.md` and `ralph-v2-librarian.cli-embed.instructions.md` existed as trimmed CLI variants. These are now eliminated — all agents embed from the consolidated instruction files, which have been compressed to fit within the 30K CLI body limit.

### Ralph-Coupled Skills

These skills are bundled in the Ralph-v2 plugins and loaded on demand by the agents:

| Skill                                 | Primary Consumers                         | Purpose                                                 |
| ------------------------------------- | ----------------------------------------- | ------------------------------------------------------- |
| `ralph-session-ops-reference`         | Orchestrator, Planner, Reviewer, Executor | Schema validation, timeout recovery, timestamp commands |
| `ralph-signal-mailbox-protocol`       | All Ralph-v2 agents                       | Live signal mailbox protocol, ack quorum, routing       |
| `ralph-feedback-batch-protocol`       | Orchestrator, Questioner                  | Post-iteration feedback batch handling                  |
| `ralph-planning-artifact-templates`   | Planner                                   | Canonical plan/progress/metadata/task templates         |
| `ralph-knowledge-merge-and-promotion` | Librarian                                 | Knowledge extraction, staging, merge, promotion rules   |

These Ralph-coupled skills intentionally remain in the root `skills/` factory instead of `agents/ralph-v2/skills`. The root location preserves the workspace-wide skill convention and publish tooling, while the Ralph-v2 plugin manifests define the actual ownership boundary by bundling only the skills that belong to the Ralph workflow.

### Plugin Distribution

Ralph-v2 CLI agents are distributed **exclusively via the ralph-v2 CLI plugin**. Do not use `publish-agents.ps1` for CLI agents in this folder (the `.plugin-managed` marker enforces this).

Plugin location: `plugins/cli/ralph-v2/plugin.json`
Runtime-scoped bundle root: `plugins/cli/.build/`
CLI publish unit: `plugins/cli/.build/ralph-v2/`
CLI install location (workspace publish flow): `~/.copilot/installed-plugins/_direct/ralph-v2`

The workspace publisher now copies the prepared CLI bundle directly into `_direct/ralph-v2` with exact replacement semantics and no `.install/` staging. That payload copy is verified, but Copilot CLI discovery of raw `_direct` copies is still treated as a best-effort path because local probes have not yet proven parity with `copilot plugin install`.

To publish:
```powershell
# Publish via plugin (required for CLI agents)
pwsh -NoProfile -File scripts/publish/publish-plugins.ps1

# Or using the artifact publisher:
pwsh -NoProfile -File scripts/publish/publish-artifact.ps1 -Type plugin -Name ralph-v2
```

For VS Code, prefer the plugin publisher so the Ralph-coupled skills are bundled together:
```powershell
pwsh -NoProfile -File scripts/publish/publish-plugins.ps1 -Runtime vscode -Plugins ralph-v2
```

VS Code publish builds `plugins/vscode/.build/ralph-v2/` and registers that runtime-scoped bundle path in `chat.plugins.paths`.

Direct `publish-agents.ps1 -Platform vscode` is now a legacy path and should only be used if the required skills have already been published separately.

### Version Governance

Ralph-v2 now uses one workflow-version contract across source and published artifacts:

- The canonical Ralph workflow version is the shared `version` frontmatter carried by the source Ralph agent wrapper files.
- The source CLI and VS Code `plugin.json` manifests mirror that workflow version for readability.
- Build and publish automation stamp bundled plugin manifests from the canonical workflow version before publication.
- Channel naming remains orthogonal to versioning: beta and stable may change bundle identity, but they do not suffix or derive the workflow version.

### Agent Reference

| Agent            | Role           | Modes                                                                                      | Key Responsibilities                                                                                       |
| ---------------- | -------------- | ------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------- |
| **Orchestrator** | Routing        | —                                                                                          | State machine transitions, concurrency SSOT, ordered handoffs, `.ralph-sessions/<SESSION_ID>/metadata.yaml` ownership, signal routing |
| **Planner**      | Planning       | INITIALIZE, TASK_BREAKDOWN, TASK_CREATE, UPDATE, REBREAKDOWN, SPLIT_TASK, UPDATE_METADATA, REPAIR_STATE, CRITIQUE_TRIAGE, CRITIQUE_BREAKDOWN | Plan creation, validated task inventory, single-task task-file materialization, wave dependency reasoning, critique-loop replanning |
| **Questioner**   | Discovery      | brainstorm, research, feedback-analysis                                                    | Q&A generation, research, feedback analysis                                                                |
| **Executor**     | Implementation | —                                                                                          | Task execution, design-time validation (build/lint/tests)                                                  |
| **Reviewer**     | Quality        | TASK_REVIEW, ITERATION_REVIEW, SESSION_REVIEW, COMMIT, TIMEOUT_FAIL                        | Task review, blocking post-knowledge iteration review, final session retrospective, atomic commits, `## Live Signals` normalization in `progress.md` |
| **Librarian**    | Knowledge      | EXTRACT, STAGE, PROMOTE                                                                    | Knowledge extraction (iteration-scoped), durable staging, wiki promotion (workspace-scoped) |

### Ownership Model

| Artifact                       | Owner (write)                                      | Notes                                                         |
| ------------------------------ | -------------------------------------------------- | ------------------------------------------------------------- |
| `.ralph-sessions/<SESSION_ID>/metadata.yaml` | Planner (init), Orchestrator (transitions)         | Session-level state machine SSOT                              |
| `iterations/<N>/metadata.yaml` | Planner (init), Reviewer (update)                  | Iteration timing SSOT                                         |
| `iterations/<N>/plan.md`       | Planner                                            | Mutable plan per iteration                                    |
| `iterations/<N>/tasks/*.md`    | Planner                                            | One file per task                                             |
| `iterations/<N>/progress.md`   | Planner, Questioner, Executor, Reviewer, Librarian | SSOT for all task/planning/knowledge status; Reviewer normalizes the `## Live Signals` section |
| `iterations/<N>/reports/*`     | Executor, Reviewer                                 | Task and review reports                                       |
| `iterations/<N>/questions/*`   | Questioner                                         | Per-category Q&A files                                        |
| `iterations/<N>/knowledge/`    | Librarian (EXTRACT)                                | Iteration-scoped extracted knowledge                          |
| `knowledge/`                   | Librarian (STAGE, PROMOTE)                         | Session-scope merged knowledge staging and promotion tracking |
| `signals/`                     | Human (write), Agents (ack), Orchestrator (route)  | Session-level mailbox                                         |

---

## Session Structure

`.ralph-sessions/` is always relative to the **workspace root**. Session ID format: `<YYMMDD>-<hhmmss>`.

Each iteration is **self-contained** — all mutable artifacts live inside `iterations/<N>/`. Session-level state (`.ralph-sessions/<SESSION_ID>/metadata.yaml`, `signals/`, `knowledge/`) stays at the session root.

```
.ralph-sessions/<SESSION_ID>/
├── metadata.yaml                  # Session state machine SSOT (Orchestrator-owned)
├── signals/                       # Session-level signal mailbox
│   ├── inputs/                    # Incoming signals from human
│   ├── acks/                      # Acknowledgments for broadcast signals
│   └── processed/                 # Consumed signals (moved after processing)
│
├── knowledge/                     # Session-scope Diátaxis knowledge (merged from iterations)
│   ├── tutorials/
│   ├── how-to-guides/
│   ├── reference/
│   ├── explanation/
│   └── index.md                   # Knowledge inventory (staged + promoted)
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
        ├── knowledge/             # Iteration-scoped extracted knowledge (Librarian EXTRACT)
        │   ├── tutorials/
        │   ├── how-to-guides/
        │   ├── reference/
        │   ├── explanation/
        │   └── index.md           # Iteration knowledge manifest
        └── review.md              # Post-knowledge iteration review
```

---

## State Machine

```
INITIALIZING ─── Planner (INITIALIZE) creates session structure
    │
    ▼
   PLANNING ──── Questioner (brainstorm/research) → Planner (TASK_BREAKDOWN) → Planner (TASK_CREATE per queued task)
    │
    ▼
   BATCHING ──── Orchestrator selects the next incomplete wave after task dependencies are satisfied
    │
    ▼
EXECUTING_BATCH ── Executor runs same-wave tasks whose dependency guards are satisfied
    │
    ▼
REVIEWING_BATCH ── Reviewer runs TASK_REVIEW across distinct pending tasks → COMMIT remains ordered per qualified task
    │
    └── loops back to BATCHING until all waves are closed
    ▼
KNOWLEDGE_EXTRACTION ── Librarian auto-sequences EXTRACT → STAGE → PROMOTE
    │                    ├── EXTRACT: iteration artifacts → `iterations/<N>/knowledge/`
    │                    ├── STAGE: iteration knowledge → session `knowledge/`
    │                    ├── PROMOTE: session knowledge → `.docs/`
    │                    └── Skip or zero-item paths still close the knowledge pipeline before review
    ▼
ITERATION_REVIEW ── Reviewer (ITERATION_REVIEW) writes `iterations/<N>/review.md`
    │
    ├── no active issues or critique cap reached → COMPLETE
    └── active issues remain → ITERATION_CRITIQUE_REPLAN
                     │
                     ▼
                Planner triages critique gaps → optional Questioner support → Planner breaks down follow-up work → BATCHING

COMPLETE ─── iteration is closed and waiting for feedback or an explicit final retrospective
    │
    ├── feedback arrives → REPLANNING
    └── final retrospective requested → SESSION_REVIEW
                          │
                          ▼
                    Reviewer (SESSION_REVIEW) writes `.ralph-sessions/<SESSION_ID>/session-review.md`
                          │
                          ▼
                          COMPLETE
```

**Concurrency boundaries:**
- Orchestration is the source of truth for parallel-safe versus sequential work.
- Planner remains sequential except for `TASK_CREATE`, which may fan out only after `TASK_BREAKDOWN` or critique planning has already produced the queued task inventory.
- Questioner remains sequential.
- Executor parallelism is limited to same-wave tasks whose dependency guards are already satisfied.
- Reviewer may parallelize `TASK_REVIEW` across distinct tasks in the same wave, but `COMMIT`, `ITERATION_REVIEW`, and `SESSION_REVIEW` remain sequential.
- Librarian remains sequential across `EXTRACT -> STAGE -> PROMOTE -> ITERATION_REVIEW`.

**Review semantics:**
- `ITERATION_REVIEW` is the blocking, post-knowledge gate for the current iteration.
- `SESSION_REVIEW` is the optional session-scoped retrospective after iteration work is already closed.
- `ITERATION_CRITIQUE_REPLAN` is the critique-loop state that generates follow-up work from iteration-review findings.

**Replanning routes:**
- `full-replanning` — Questioner (`feedback-analysis`, research) → Planner (`UPDATE`, `REBREAKDOWN`) → BATCHING
- `knowledge-promotion` — Fast-path from REPLANNING: Librarian (`PROMOTE`) → COMPLETE

---

## Design Principles

### Isolated Task Files

One file per task in `iterations/<N>/tasks/task-<id>.md` with YAML frontmatter (`id`, `iteration`, `type`, `created_at`), dependencies, and success criteria. `tasks/<id>.md` is legacy shorthand only when discussing pre-normalization sessions. Eliminates write contention and enables parallel execution.

### Single Source of Truth (SSOT) Progress

`iterations/<N>/progress.md` is the **only** location for task status. Status markers: `[ ]` not started, `[/]` in progress, `[P]` pending review, `[x]` completed, `[F]` failed, `[C]` cancelled/skipped.

The `## Live Signals` section inside `iterations/<N>/progress.md` is normalized by Reviewer. Other roles can surface signal outcomes through reports, outputs, or routed context, but should not directly rewrite that section.

### Structured Feedback Loops

Two protocols for human feedback:

1. **Live Signal Protocol** (session active) — Drop YAML signal files into `signals/inputs/` for real-time steering
2. **Post-Iteration Feedback Protocol** (session at rest) — Create `iterations/<N+1>/feedbacks/<timestamp>/feedbacks.md` with artifacts

### Live Signals

Four signal types (all universal):

| Signal  | Category  | Semantics                                                                  | Polled By                |
| ------- | --------- | -------------------------------------------------------------------------- | ------------------------ |
| `STEER` | Universal | Re-route workflow                                                          | Orchestrator + Subagents |
| `INFO`  | Universal | Context injection (also used for targeted conventions like skip-promotion) | Orchestrator + Subagents |
| `PAUSE` | Universal | Temporary halt                                                             | Orchestrator + Subagents |
| `ABORT` | Universal | Permanent halt with cleanup                                                | Orchestrator + Subagents |

Target-aware routing: Orchestrator checks `target` field and routes to specific subagents. Broadcast signals (`target: ALL`) require ack quorum from all recipients before archival.

Reviewer owns the normalized iteration record for signal activity in `iterations/<N>/progress.md` under `## Live Signals`. Planner, Questioner, Executor, Librarian, and Orchestrator may react to signals, but they report those outcomes through their own artifacts or outputs instead of mutating that section directly.

### Atomic Commits (COMMIT Mode)

Reviewer executes commits via dedicated COMMIT mode with hunk-level analysis:
- `git diff` per file → classify hunks (TASK-RELEVANT / UNRELATED / AMBIGUOUS)
- Partial staging via `git apply --cached` — never `git add .` or `git add -A`
- `git-atomic-commit` skill for conventional commit generation
- Durable commit messages describe stable repository changes, not `.ralph-sessions/`, iteration folders, or temporary report/test paths
- Commit failure does NOT affect review verdict (`[x]` preserved)

### Knowledge Pipeline (EXTRACT → STAGE → PROMOTE)

Knowledge flows through three tiers with explicit merge semantics:

1. **EXTRACT** (iteration-scoped): Scan `iterations/<N>/` artifacts, write reusable knowledge to `iterations/<N>/knowledge/` with Diátaxis classification
2. **STAGE** (session-scoped): Merge iteration knowledge into session `knowledge/` with auto-conflict-resolution (newer-wins timestamp strategy)
3. **PROMOTE** (workspace-scoped): Merge session knowledge into `.docs/` with auto-conflict-resolution. Auto-promotes by default; `INFO + target: Librarian + SKIP_PROMOTION:` prefix opts out

Key behaviors:
- **Auto-extract and auto-stage** are enabled by default in the orchestrator's KNOWLEDGE_EXTRACTION state
- Promoted knowledge is not re-extracted on subsequent iterations
- Staged and promoted knowledge must rewrite or omit `.ralph-sessions/...`, `iterations/<N>/...`, and other ephemeral provenance paths in reader-facing content
- **Cherry-pick staging**: Human can selectively stage specific files from `iterations/<N>/knowledge/` via `CHERRY_PICK` parameter
- **Cross-iteration staging**: Human can stage knowledge from previous iterations via `SOURCE_ITERATIONS` parameter (useful when auto-stage was disabled)
- **Merge conflicts**: Auto-resolved by default — newer timestamp wins. Content overlap detected via H2/H3 heading comparison (>50% overlap threshold)
- Diátaxis categorization: `tutorials/`, `how-to-guides/`, `reference/`, `explanation/`

### Skills Enforcement

All subagents discover and load skills at runtime via 4-step reasoning:
1. Check agent instructions for skill affinities
2. Check task context for explicitly mentioned skills
3. Scan `<SKILLS_DIR>` and match descriptions
4. Load only directly relevant skills (typically 1-3 but can be more depending on task context)

| Agent        | Primary Skill Affinities                                                                            |
| ------------ | --------------------------------------------------------------------------------------------------- |
| Orchestrator | `ralph-session-ops-reference`, `ralph-signal-mailbox-protocol`, `ralph-feedback-batch-protocol`     |
| Planner      | `ralph-planning-artifact-templates`, `ralph-session-ops-reference`, `ralph-signal-mailbox-protocol` |
| Questioner   | `ralph-signal-mailbox-protocol`, `ralph-feedback-batch-protocol`, `ralph-session-ops-reference`     |
| Executor     | `ralph-signal-mailbox-protocol`, `ralph-session-ops-reference`                                      |
| Reviewer     | `ralph-signal-mailbox-protocol`, `ralph-session-ops-reference`, `git-atomic-commit`                 |
| Librarian    | `ralph-knowledge-merge-and-promotion`, `diataxis`, `diataxis-categorizer`, `git-atomic-commit`      |

### Operational Guardrails

- **Schema validation** for `iterations/<N>/progress.md`, `iterations/<N>/metadata.yaml`, and `.ralph-sessions/<SESSION_ID>/metadata.yaml`
- **Orchestrator owns only `.ralph-sessions/<SESSION_ID>/metadata.yaml`** — all other writes delegated to subagents
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

# 3. Create feedbacks.md (see docs/templates/feedbacks.template.md)
code .ralph-sessions/<SESSION_ID>/iterations/<N+1>/feedbacks/$timestamp/feedbacks.md

# 4. Resume: "Continue session <SESSION_ID> with new feedback"
```

### Sending Live Signals

```powershell
$ts = Get-Date -Format "yyMMdd-HHmmssK" -replace ":", ""
Set-Content ".ralph-sessions/<SESSION_ID>/signals/inputs/signal.$ts.yaml" @"
type: INFO          # STEER | INFO | PAUSE | ABORT
target: Librarian   # ALL | Orchestrator | Executor | Planner | Questioner | Reviewer | Librarian
message: "SKIP_PROMOTION: Skip knowledge promotion this iteration"
created_at: $(Get-Date -Format "yyyy-MM-ddTHH:mm:ssK")
"@
```

### Timestamp Commands

| Format                       | Windows (PowerShell)                      | Linux/WSL (bash)                                  |
| ---------------------------- | ----------------------------------------- | ------------------------------------------------- |
| Session ID `<YYMMDD-hhmmss>` | `Get-Date -Format "yyMMdd-HHmmss"`        | `TZ=Asia/Ho_Chi_Minh date +"%y%m%d-%H%M%S"`       |
| ISO 8601 with offset         | `Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"` | `TZ=Asia/Ho_Chi_Minh date +"%Y-%m-%dT%H:%M:%S%z"` |

---

## Related Documentation

| Document                                                                                                         | Description                                                                                           |
| ---------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| [specs/live-signals.spec.md](specs/live-signals.spec.md)                                                         | Live signal protocol spec — design, types, routing, ack quorum, checkpoint map (v2.10.0, implemented) |
| [specs/normalization.spec.md](specs/normalization.spec.md)                                                       | SSOT normalization patterns spec (v2.2.0, implemented)                                                |
| [specs/ralph-v2-stop-hook-metadata-finalization.spec.md](specs/ralph-v2-stop-hook-metadata-finalization.spec.md) | Stop hook metadata finalization spec (implemented)                                                    |
| [docs/design/critique.md](docs/design/critique.md)                                                               | Workflow critique and guardrail status                                                                |
| [docs/reference/hooks-integrations.md](docs/reference/hooks-integrations.md)                                     | Hooks integration plan (P0-P3 tiers)                                                                  |
| [docs/templates/feedbacks.template.md](docs/templates/feedbacks.template.md)                                     | Feedback file template                                                                                |

---

## Version History

### v2.12.0 (2026-03-01)

**SKIP Signal Removal**
- **Removed SKIP signal type**: Signal types reduced from 5 to 4 (STEER, INFO, PAUSE, ABORT). The skip-promotion intent is now expressed via `INFO + target: Librarian + SKIP_PROMOTION:` message prefix convention
- **Updated Librarian PROMOTE pre-check**: Polls for `INFO` with `target: Librarian` and `SKIP_PROMOTION:` prefix instead of `type: SKIP`
- **Updated Executor signal routing**: Removed SKIP-specific routing line from Poll-Signals routine
- **Updated state machine**: Removed SKIP transitions from KNOWLEDGE_EXTRACTION state
- **Updated specs and docs**: `live-signals.spec.md` §3.5 SKIP removed, §3.2 INFO gains "Targeted INFO Conventions" subsection; `hooks-integrations.md` signal validation updated; `critique.md` knowledge persistence references updated

**Self-Contained Knowledge Enforcement**
- **Librarian PROMOTE content transformation (Step 6.5)**: Transforms ephemeral session references into descriptive labels during promotion — `source_artifacts` paths become descriptive strings, `staged`/`staged_at` fields removed, body text scanned for session-relative patterns
- **EXTRACT authoring guideline**: Added upstream guidance to avoid session-specific references during extraction

**Intelligent Sub-Category Classification**
- **New `diataxis-categorizer` skill**: Domain-based sub-category heuristic for `.docs/` organization (keyword extraction → reuse check → ≥3-file threshold → fallback)
- **Librarian PROMOTE Step 6.75**: Sub-category resolution using the categorizer skill during promotion
- **Wiki reorganization**: `.docs/` restructured with domain-based sub-categories (`ralph/`, `copilot/`, `blazor-agui/`); `research/` files reclassified; `generate_index.py` updated for recursive scanning
- **Extended self-critique checklist**: 9→11 dimensions — (j) Knowledge Self-Containment, (k) Sub-Category Structure Consistency; dimension (b) updated for 4-type signal protocol

### v2.11.0 (2026-02-28)

**Spec Restructuring & Legacy Cleanup**
- **New `specs/` directory**: Top-level peer to `docs/` for feature specifications with YAML frontmatter
- **Created `specs/live-signals.spec.md`**: Merged `docs/design/live-signals-design.md` + `docs/design/live-signals-map.md` into unified spec (status: implemented, v2.10.0). Originals deleted
- **Created `specs/normalization.spec.md`**: Transformed `docs/reference/normalization.md` into spec format (status: implemented, v2.2.0). Original deleted
- **Migrated `specs/ralph-v2-stop-hook-metadata-finalization.spec.md`**: Added YAML frontmatter convention to existing spec
- **Removed legacy duplicate directories**: `appendixes/`, `docs/specs/`, root-level `templates/` (remnants from v2.5.0 reorganization)
- **Updated cross-references**: All paths in README and `docs/reference/hooks-integrations.md` updated to new spec locations
- **v2.10.0 knowledge extraction**: Extracted knowledge from v2.10.0 changes with Diátaxis categorization (`source_iteration: external`)

### v2.10.0 (2026-02-28)

> Breaking: NOT backward-compatible with v2.9.0 sessions (session structure change + state machine change).

**Knowledge Pipeline Refactor (EXTRACT → STAGE → PROMOTE)**
- **New EXTRACT mode**: Scans iteration artifacts and writes reusable knowledge to iteration-scoped `iterations/<N>/knowledge/` with Diátaxis classification
- **Refactored STAGE mode**: Now merges iteration-scoped knowledge into session-scoped `knowledge/` with auto-conflict-resolution (newer-wins timestamp strategy). Supports `CHERRY_PICK` and `SOURCE_ITERATIONS` parameters for selective and cross-iteration staging
- **Refactored PROMOTE mode**: Now merges session-scoped knowledge into workspace `.docs/` with auto-conflict-resolution. Uses `INFO + target: Librarian + SKIP_PROMOTION:` prefix convention as pre-promote opt-out
- **Removed CURATE mode**: Redundant with separate EXTRACT/STAGE/PROMOTE pipeline. Signal polling absorbed by PROMOTE; auto-promote is the default; post-iteration feedback detection moved to orchestrator
- **Removed APPROVE signal type**: Auto-promote is default; `INFO + target: Librarian + SKIP_PROMOTION:` convention replaces dedicated SKIP signal type. Signal types reduced from 6 to 4
- **Auto-extract and auto-stage enabled by default**: Orchestrator's KNOWLEDGE_EXTRACTION state auto-sequences EXTRACT → STAGE → PROMOTE
- **Iteration-scoped knowledge folder**: Added `iterations/<N>/knowledge/` to session structure with full Diátaxis subdirectories
- **Merge algorithm**: Shared by STAGE and PROMOTE — per-file merge with 5 cases (new, newer-wins, skip-older, content-overlap, contradiction). Content overlap detected via H2/H3 heading comparison with >50% threshold
- **New progress tracking**: `plan-knowledge-extraction`, `plan-knowledge-staging` (new), `plan-knowledge-promotion` (replaces `plan-knowledge-approval`)
- **New frontmatter template**: Three-state tracking (`extracted_at`, `staged`/`staged_at`, `promoted`/`promoted_at`) replaces binary `approved`/`approved_at`
- State machine: Removed CURATE state; KNOWLEDGE_EXTRACTION now auto-sequences all three Librarian modes
- Version bump 2.9.0 → 2.10.0 across all agent files

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
- CURATE state transitions directly to auto-promote unless overridden by skip-promotion INFO signal
- Reduces friction for knowledge persistence across iterations

**Subagent Template Standardization**
- All subagent files now follow a consistent XML-tagged template structure
- Canonical tag order: `<persona>`, `<artifacts>`, `<rules>`, `<workflow>`, `<signals>`, `<contract>`
- Orchestrator uses `<stateMachine>` in place of `<workflow>`
- Markdown content within XML tags; YAML frontmatter unchanged

### v2.4.0 (2026-02-27)

**CURATE Delegation to Librarian**
- Librarian now owns the full CURATE gate (signal polling, PROMOTE/skip-promotion execution, `iterations/<N>/progress.md` marking)
- New Librarian mode: `CURATE` — encapsulates approval signal reading, promotion, skip-promotion, and post-iteration feedback detection
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
- Structured `iterations/<N>/plan.md` template (7 mandatory sections) with self-validation
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
- Signal types: `APPROVE`, `SKIP` (both later removed — see v2.10.0/v2.11.0)

### v2.0.x (2026-02-07 – 2026-02-10)

- Initial v2: isolated task files, structured feedback loops, REPLANNING state, SSOT progress tracking
