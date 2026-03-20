# Fleet In VS Code As A Generic Orchestrator Reference

**File:** `prompts/fleet.prompt.md`  
**Type:** VS Code `.prompt.md` customization (prompt file)
**Version:** 0.3.0
**Role:** Generic multi-iteration orchestrator for repository-safe parallel work in VS Code

## Overview

This document is the authoritative specification for the custom fleet prompt. It describes the artifact's structure, wave lifecycle, artifact schema, subagent routing, and specialization interface — serving as the stable baseline from which domain-specific fleet variants are derived.

This custom fleet.prompt.md (only for VS Code) is an attempt to simulate the native (built-in) `/fleet` slash command of Copilot CLI. The design intentionally diverges from the CLI implementation to fit the VS Code environment and to provide a more explicit artifact-based orchestration contract. Key differences include:

- **Artifact-driven orchestration:** VS Code fleet relies on a shared file system for all state management and communication between subagents, rather than in-chat context or a session SQLite database. This makes the session history inspectable and resumable.
- **Explicit wave lifecycle:** VS Code fleet defines a clear 10-step lifecycle for each iteration, with specific artifact outputs at each stage. This contrasts with the more free-form CLI fleet, which is more of a high-level pattern than a strict lifecycle.
- **Pure router orchestrator:** VS Code fleet enforces a strict router-only contract for the orchestrator. The orchestrator creates artifacts, tracks state, and routes — it does not execute or assess actual work. This is a stronger constraint than CLI fleet, where the orchestrating agent can also perform work directly.
- **Metadata-only delegation protocol:** Task briefs contain only artifact paths and routing metadata — no inline work content. Subagents respond with output artifact path, routing state, and blockers only — no work summaries. All work content lives in artifact files.
- **Hard bootstrap gate:** Every fleet session must create its bootstrap artifacts before any planning or delegation. This prevents the common failure mode of the orchestrator collapsing into a single-pass executor.
- **JD-first routing:** Subagent roles are defined as Job Descriptions first. An agent is admitted to the active routing table only after it satisfies a specific JD. The routing team grows deliberately over time as new standalone specialist agents are authored.
- **No built-in agent types:** VS Code fleet does not assume the presence of any built-in agent types and instead relies on custom agents present in the workspace.
- **Identity constraints in the reference doc only:** Identity constraints (what fleet is not, what it must not do) are documented here, not repeated in the prompt file. The prompt is reserved for behavioral instructions.

See also:
- [Fleet Orchestration: CLI vs VS Code Comparative Analysis](../../../../explanation/copilot/shared/fleet-cli-vs-vscode-comparison.md) — why this design differs from CLI `/fleet`
- [Fleet Mode as Prompt Injection](../../../../explanation/copilot/cli/fleet-mode-as-prompt-injection.md) — how CLI `/fleet` works internally
- [Fleet and Task Subagent Dispatch Reference](../../cli/fleet-and-task-subagent-dispatch.md) — full CLI `task()` schema

---

## Frontmatter Specification

```yaml
---
name: fleet
description: "Multi-iteration VS Code subagent orchestrator with wave-based dispatch, artifact-driven state, and knowledge capture."
argument-hint: "Describe the work to orchestrate in iterations and waves"
agent: agent
metadata:
  version: 0.3.0
  author: arisng
---
```

| Field           | Value                                                      | Purpose                                              |
| --------------- | ---------------------------------------------------------- | ---------------------------------------------------- |
| `name`          | `fleet`                                                    | Prompt identifier; used to invoke it from the picker |
| `description`   | …                                                          | Shown in the VS Code prompt picker                   |
| `argument-hint` | "Describe the work to orchestrate in iterations and waves" | Prompt shown to user when selecting this workflow    |
| `agent`         | `agent`                                                    | Runs in the default Copilot VS Code agent mode       |

---

## Identity Constraints

> These constraints are documented here only. The prompt file (`fleet.prompt.md`) does not reproduce them — the prompt is reserved for behavioral instructions, not for disambiguation notes.

The VS Code fleet prompt is **not** Copilot CLI `/fleet`. Key constraints that distinguish it:

- Do **not** use CLI-only built-in agent types: `task`, `explore`, `code-review`, `research`, `general-purpose`.
- Do **not** assume a session SQLite todo database exists. Coordination uses the shared artifact file system instead.
- Use only VS Code-compatible **standalone** custom agents present in this workspace.
- Default scope: current session and current changes only; ignore unrelated workspace changes unless explicitly requested.
- Do **not** route to nested orchestrators or to agents that belong to another workflow system (such as Ralph-v2 agents). The fleet prompt is itself the orchestration layer — adding a nested orchestration agent creates conflicting layers and corrupts the router contract.

These constraints are the primary divergence points from CLI fleet and must be preserved in any derived variant.

---

## Pure Router Design

The orchestrator is a **pure router**. This is the most important behavioral constraint for VS Code fleet.

| The orchestrator does                                           | The orchestrator does NOT do                                        |
| --------------------------------------------------------------- | ------------------------------------------------------------------- |
| Create and update orchestration metadata files                  | Execute tasks itself                                                |
| Write task briefs containing only artifact paths and routing metadata | Include work-specific content in task briefs                   |
| Dispatch subagents by pointing them at the task brief path      | Assess, evaluate, or critique actual work content                   |
| Read subagent routing state from the response metadata          | Read work content from subagent responses                           |
| Advance or loop based on routing state                          | Make routing decisions based on in-context reasoning about the work |
| Confirm output artifacts exist on disk before advancing         | Accept a subagent result and continue without disk confirmation     |

**Why this matters:** When the orchestrator starts assessing or executing work itself, it collapses the multi-agent structure into a single-agent single-pass execution. The fleet pattern only delivers value when the orchestrator stays in its routing lane, task briefs carry only metadata, and subagents do all the actual work.

---

## Delegation Protocol

All communication between the orchestrator and subagents is metadata-only. No work-specific content crosses the boundary in either direction.

### What goes into a task brief

The orchestrator writes `iterations/<N>/tasks/<TASK_ID>.md` containing:

| Field | Content |
|---|---|
| Session metadata path | Path to `metadata.yaml` (subagent reads the goal and scope from here) |
| Iteration metadata path | Path to `iterations/<N>/metadata.yaml` (subagent reads iteration scope from here) |
| Prior artifact paths | Paths the subagent should read for context (e.g., `plan.md`, earlier `reports/`) |
| Expected output artifact path | Where the subagent must write its result |
| Routing exit criteria | The state value the subagent must write back to signal completion |

The orchestrator does **not** include: the goal as inline text, task descriptions as prose, summaries of prior subagent results, or any work content. The subagent reads the artifacts directly and gathers its own context.

### What a subagent reports back

The subagent responds to the orchestrator with metadata only:

| Field | Content |
|---|---|
| Output artifact path | Confirms where the result was written |
| Routing state | One of: `done`, `stable`, `pass`, `needs_revision`, `needs_fix`, `blocked` |
| Blockers | Artifact path or a single-line code — only if routing state is `blocked` |

The subagent does **not** include: work content, results summaries, findings, or any content that duplicates what is already in the output artifact file.

---

## Critical Pitfall: Single-Pass Execution

The most common failure mode for VS Code fleet is the orchestrator executing everything itself in a single pass without creating any artifact files. Symptoms:

- No `.fleet-sessions/` directory is created
- No task brief files are written before delegation
- The `agent` built-in handles the entire request and returns a single response
- Subagents are described in the response but never actually dispatched

**Root cause:** The orchestrator skips the bootstrap gate and reasons about the work itself rather than routing it.

**Solution enforced in the prompt:**
1. The **First Action: Bootstrap the Session** block is a hard gate — no other step may begin until the bootstrap artifacts exist on disk.
2. The **Subagent Dispatch Rule** requires task brief files to be written and confirmed before any subagent is called.
3. Every routing decision must be grounded in the artifact file system, not in in-context inference.

If you are reviewing a fleet session and no `.fleet-sessions/` directory was created, the session was a single-pass execution failure, not a fleet session.

---

## Agent Skills

Agent skills are part of the orchestration contract, not an optional add-on.

- The orchestrator must identify relevant workspace skills before dispatching any subagent.
- Every task brief and subagent handoff must name the skills that should be activated for that work item.
- Prefer the most specific skill available in `skills/`; if no skill is relevant, state that explicitly in the task brief.
- Derived variants may add domain-specific skill requirements, but they should not remove this enforcement model.
- Skills are surfaced to subagents via the task brief artifact file — the orchestrator does not inline skill instructions into its routing decisions.

---

## Workflow Shape

The generic fleet runs a 10-step lifecycle:

| Step | Phase                    | Description                                                                                             |
| ---- | ------------------------ | ------------------------------------------------------------------------------------------------------- |
| 1    | **Initialize**           | Resolve the workspace root; create session and `iterations/1` bootstrap artifacts before any other step |
| 2    | **Master plan**          | Run a multi-pass planning cycle and collect `iterations/<N>/questions/<CATEGORY>.md`                    |
| 3    | **Plan polish**          | Finalize `iterations/<N>/plan.md` and derive the high-level task list and wave schedule                 |
| 4    | **Task materialization** | Create grounded `iterations/<N>/tasks/<TASK_ID>.md` files from the master plan                          |
| 5    | **Task execution**       | Run dedicated subagents, then write `iterations/<N>/reports/<TASK_ID>-report.md`                        |
| 6    | **Wave execution**       | Execute waves sequentially, parallelizing independent tasks only when safe                              |
| 7    | **Knowledge capture**    | After all tasks are done, run iteration-level knowledge extraction into `iterations/<N>/knowledge/`     |
| 8    | **Iteration review**     | Run `iterations/<N>/review.md`; loop back within the iteration if it fails                              |
| 9    | **Iteration commit**     | Commit only the current iteration scope and record commit history in `iterations/<N>/review.md`         |
| 10   | **Next iteration gate**  | Wait for human follow-up feedbacks in `iterations/<N>/feedbacks/` before starting `iterations/<N+1>/`   |

---

## Shared Artifact File System

The artifact store is the orchestration memory for the entire fleet session. Chat context carries only short summaries and file pointers.

### Session Root

```
.fleet-sessions/<SESSION_ID>/
```

**Session ID format:** `<YYMMDD>-<hhmmss>` (e.g., `260318-142300`).

**Session bootstrap:** `.fleet-sessions/<SESSION_ID>.instructions.md`

**Session start:** every session begins at `iterations/1`

**Working directory:** The orchestrator must resolve the workspace root (repository root) before writing any file. All artifact paths are relative to that root. In VS Code, the workspace root is the top-level folder open in the editor.

### Directory Schema

| Path                                                | Content                                                          | Written by                        |
| --------------------------------------------------- | ---------------------------------------------------------------- | --------------------------------- |
| `metadata.yaml`                                     | Session goal, scope, state, iteration list                       | Orchestrator at session start     |
| `iterations/<N>/metadata.yaml`                      | Iteration scope, source feedback, and status                     | Orchestrator at iteration start   |
| `iterations/<N>/plan.md`                            | Polished master plan                                             | Planner                           |
| `iterations/<N>/progress.md`                        | Status tracking and live state                                   | Planning, execution, review roles |
| `iterations/<N>/questions/<CATEGORY>.md`            | Questions and research gathered during master plan creation      | Questioner                        |
| `iterations/<N>/tasks/<TASK_ID>.md`                 | Grounded task brief derived from the master plan                 | Planner                           |
| `iterations/<N>/reports/<TASK_ID>-report.md`        | Task self-reflection and validation notes                        | Executor / reviewer               |
| `iterations/<N>/knowledge/`                         | Iteration-scoped knowledge extraction before review              | Librarian                         |
| `iterations/<N>/review.md`                          | Iteration review, pass/fail status, and commit history           | Reviewer                          |
| `iterations/<N>/feedbacks/<TIMESTAMP>/feedbacks.md` | Human follow-up feedback bundle that triggers the next iteration | Human                             |
| `scratch/`                                          | Disposable notes; safe to delete after cleanup                   | Orchestrator (temporary)          |

### Artifact Rules

| Rule                                                                 | Rationale                                       |
| -------------------------------------------------------------------- | ----------------------------------------------- |
| Write artifacts **before** dispatching the next subagent             | Prevents state loss if context resets           |
| Update in-place instead of duplicating                               | Avoids divergent state across wave boundaries   |
| Point subagents at artifact paths instead of re-pasting context      | Keeps chat context lean; artifacts are the SSOT |
| Keep each artifact focused on one decision, wave, or validation step | Reduces ambiguity when reviewing wave history   |
| Keep wave history and commit records after cleanup                   | Durable session memory for future reference     |
| Remove scratch artifacts during final cleanup                        | Reduces noise without losing structured history |

---

### Iteration Lifecycle

```
ITERATION START
  ↓ Initialize iteration/1
  ↓ Run multi-pass master plan and questions collection
  ↓ Write iterations/<N>/plan.md (objective, boundaries, exit criteria, task inventory)
  ↓ Derive waves from the polished task list
  ↓ Write iterations/<N>/tasks/<ID>.md for each work item
DISPATCH (parallel for independent items)
  ↓ Subagents run; write iterations/<N>/reports/<ID>-report.md
KNOWLEDGE
  ↓ Run iteration-level knowledge extraction into iterations/<N>/knowledge/
REVIEW
  ↓ Write iterations/<N>/review.md
  ↓ If issues found → fix → re-check → repeat
COMMIT
  ↓ Compose atomic commits for this iteration only
  ↓ Append commit grouping decisions + hashes to iterations/<N>/review.md
NEXT ITERATION GATE → wait for human follow-up feedbacks in iterations/<N>/feedbacks/
```

**Hard checkpoint:** No commit may be made until the review is complete and issues are resolved.

---

## Commit Discipline

| Rule                          | Details                                                                              |
| ----------------------------- | ------------------------------------------------------------------------------------ |
| **Per-iteration scope**       | Commits contain only the changes produced in the current iteration                   |
| **No cross-iteration mixing** | Never mix iteration N changes with iteration N+1 changes in the same commit          |
| **Atomic grouping**           | Each commit represents one coherent logical change                                   |
| **Git as iteration memory**   | The holistic review uses git log to recall what each iteration changed               |
| **Cleanup pass**              | After the final iteration, any remaining relevant changes get a final cleanup commit |
| **Unrelated changes**         | Ignored by default unless the user explicitly asks for broader scope                 |

---

## Knowledge Capture

Knowledge capture is a first-class output of every fleet session that surfaces new understanding.

| Target                                                   | What goes there                              |
| -------------------------------------------------------- | -------------------------------------------- |
| `.fleet-sessions/<SESSION_ID>/iterations/<N>/knowledge/` | Raw notes staged during the active iteration |
| `.docs/<category>/<domain>/`                             | Promoted documentation after refinement      |

**What qualifies for capture:**
- Reusable guidance not already in the wiki
- Workflow rules derived from solving the session's problems
- Naming conventions that emerged during the work
- Durable implementation lessons that will recur

**What does not qualify:**
- Session-specific decisions that will not generalize
- Narrative summaries of what the session did
- Content that duplicates existing `.docs` entries

---

## Subagent Routing Table

The routing model is JD-first: roles are defined as Job Descriptions first, then custom agents are recruited to fill them. An agent appears in the active routing table only after it has been created and verified to satisfy a specific JD.

### Job Descriptions

| JD | Core Responsibility | Reads from | Writes to |
| --- | --- | --- | --- |
| **Planning Specialist** | Decomposes the session goal into a structured plan, wave schedule, and individual task brief files | `metadata.yaml`, `iterations/<N>/metadata.yaml`, prior `questions/` | `iterations/<N>/plan.md`, `iterations/<N>/tasks/<TASK_ID>.md` |
| **Research Specialist** | Gathers and validates information across any domain; surfaces evidence needed for planning and execution | Task brief artifact, referenced prior artifacts | `iterations/<N>/questions/<CATEGORY>.md`, research notes in `scratch/` |
| **Synthesis Specialist** | Cross-task reasoning, conflict resolution, and arbitration when subagent outputs need coordination | Task brief artifact, relevant report artifacts | Synthesis notes in `iterations/<N>/reports/<TASK_ID>-report.md` |
| **Iteration Reviewer** | Validates iteration outputs against the plan; writes a structured pass/fail review with actionable findings | `iterations/<N>/plan.md`, all `iterations/<N>/reports/` | `iterations/<N>/review.md` |
| **Knowledge Curator** | Extracts reusable knowledge from completed iteration artifacts and promotes refined entries to `.docs` | `iterations/<N>/knowledge/`, `iterations/<N>/review.md` | `iterations/<N>/knowledge/`, `.docs/<category>/` |
| **Domain Execution Specialist** | Performs domain-specific work (coding, writing, analysis, etc.) guided entirely by the task brief artifact | Task brief artifact, referenced prior artifacts | `iterations/<N>/reports/<TASK_ID>-report.md` |

### Active Routing Table

An agent (specialized or fallback) is listed here only after it has been verified to satisfy its JD. Dispatch by JD name; use the agent + skills from this table.

| Agent | Satisfies JD | Skills |
| --- | --- | --- |
| `Generic-Research-Agent` | Research Specialist | |
| `Planner` | Planning Specialist | |
| `Nexus` | Synthesis Specialist | |
| `agent` | Iteration Reviewer | agent-evaluator, diataxis-categorizer |
| `agent` | Knowledge Curator | ralph-knowledge-merge-and-promotion, diataxis |
| `agent` | Domain Execution Specialist | git-atomic-commit, md-issue-writer |

> **Loose coupling principle:** Workflow Shape dispatches by JD name (e.g., "dispatch the Iteration Reviewer"). Routing resolves JD → agent + skills via this table. Changes to agents/skills do not require Workflow Shape edits. Scan `skills/` for relevant skills per JD when updating fallbacks.
> **Excluded by design:** Ralph-v2 agents excluded — fleet is the orchestration layer; no nested orchestration.

**Routing principle:** Prefer the smallest number of subagents needed for good coverage. Do not dispatch subagents for trivial single-step requests.

---

### Standalone Custom Agent Accumulation

The effectiveness of VS Code fleet scales directly with the breadth and quality of standalone specialized custom agents available in the workspace. Unlike Copilot CLI, which ships with many built-in specialized agent types, VS Code Copilot provides only a generic default agent — so the fleet orchestrator's team must be deliberately built up over time by filling the open JDs above.

| Principle | Detail |
| --- | --- |
| **JD first** | Every agent must satisfy a defined JD; do not add agents to the routing table without a matching JD |
| **Standalone only** | Agents must be self-contained (`agents/<name>.agent.md`), not coupled to another workflow system |
| **Generic fallback is temporary** | `Planner` or `Nexus` may substitute for an open JD temporarily — the fix is a new domain-specific agent |
| **Grow both tables** | When a new agent satisfies a JD, add it to the active table in both the reference doc and `fleet.prompt.md` |
| **Self-contained contract** | Each agent only needs to perform its domain work; fleet provides the orchestration layer on top |

---

## Operating Style Principles

| Principle | Description |
| --- | --- |
| **Narrow assignments** | Each subagent receives one focused goal; no mixed objectives |
| **Metadata-only briefs** | Task briefs contain only artifact paths and routing metadata — never inline work content |
| **Metadata-only responses** | Subagents respond with output artifact path, routing state, and blockers only — no work summaries |
| **Explicit wave boundaries** | Every wave definition includes: what belongs, what waits, exit criteria, artifact file locations |
| **Read artifacts before re-deriving** | Always read from the artifact store rather than re-inferring state from chat |
| **Direct handling for trivial requests** | If the request is too small for delegation, work in the current session instead of forcing multi-agent overhead |

---

## Orchestrator Summary Format

At the end of a session, the orchestrator returns:

```
- What was dispatched (wave summary)
- What completed (per-wave outcome)
- What remains, if anything
- Whether remaining work is parallelizable
- Commits created per iteration (with hashes from review.md)
- Whether .docs knowledge capture occurred
```

---

## Specialization Interface

This generic prompt is designed so domain-specific variants can be derived by overriding specific sections without changing the core wave lifecycle.

| Section to override                                      | What changes                                                         |
| -------------------------------------------------------- | -------------------------------------------------------------------- |
| **Frontmatter** (`name`, `description`, `argument-hint`) | Identity and discoverability of the specialized variant              |
| **Subagent Routing**                                     | Replace with domain-specialist standalone agents                     |
| **Wave Discipline**                                      | Adjust work-item granularity (e.g., "one test file per task" for SE) |
| **Commit Discipline**                                    | Optional or adapted for non-code domains                             |
| **Knowledge Capture**                                    | Point at domain-specific wiki paths                                  |
| **Operating Style**                                      | Add domain-specific assignment templates or result formats           |

**What must not change in derived variants:**
- The **Pure Router Contract** \u2014 derived variants must not collapse the orchestrator into an executor
- The **First Action bootstrap gate** \u2014 artifact creation must precede all other steps
- The 10-step lifecycle (initialize \u2192 master plan \u2192 polish \u2192 materialize \u2192 execute \u2192 knowledge \u2192 review \u2192 commit \u2192 next-iteration gate)
- The artifact file system schema (the stability of this schema is what makes sessions inspectable and resumable)
- The hard checkpoint between review and commit
- The constraint against nested orchestration layers

---

## Planned Specialized Variants

| Variant             | Domain                                            | Status          |
| ------------------- | ------------------------------------------------- | --------------- |
| `fleet` (this file) | Generic — any repository work                     | Active baseline |
| `fleet-se`          | Software engineering — code, test, review, deploy | Planned         |
| `fleet-marketing`   | Marketing — content, campaigns, copy              | Planned         |

All variants derive from and extend this reference.
