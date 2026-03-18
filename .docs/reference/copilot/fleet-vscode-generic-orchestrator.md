# Fleet VS Code Generic Orchestrator Reference

**File:** `prompts/fleet.prompt.md`  
**Type:** VS Code `.prompt.md` customization  
**Version:** 1.0.0  
**Role:** Generic multi-wave orchestrator for repository-safe parallel work in VS Code

This document is the authoritative specification for the custom fleet prompt. It describes the artifact's structure, wave lifecycle, artifact schema, subagent routing, and specialization interface — serving as the stable baseline from which domain-specific fleet variants are derived.

See also:
- [Fleet Orchestration: CLI vs VS Code Comparative Analysis](../../explanation/copilot/fleet-cli-vs-vscode-comparison.md) — why this design differs from CLI `/fleet`
- [Fleet Mode as Prompt Injection](../../explanation/copilot/fleet-mode-as-prompt-injection.md) — how CLI `/fleet` works internally
- [Fleet and Task Subagent Dispatch Reference](fleet-and-task-subagent-dispatch.md) — full CLI `task()` schema

---

## Frontmatter Specification

```yaml
---
name: fleet
description: "Simulate Copilot CLI fleet mode for wave-based VS Code subagent orchestration with critique, commits, and knowledge capture."
argument-hint: "Describe the work to orchestrate in waves"
agent: agent
metadata:
  version: 1.0.0
  author: arisng
---
```

| Field | Value | Purpose |
|---|---|---|
| `name` | `fleet` | Prompt identifier; used to invoke it from the picker |
| `description` | … | Shown in the VS Code prompt picker |
| `argument-hint` | "Describe the work to orchestrate in waves" | Prompt shown to user when selecting this workflow |
| `agent` | `agent` | Runs in the default Copilot VS Code agent mode |

---

## Identity Constraints

The prompt opens with explicit constraints that prevent confusion with CLI fleet:

- **Not** Copilot CLI `/fleet`
- Do **not** use CLI-only built-in agent types: `task`, `explore`, `code-review`, `research`, `general-purpose`
- Do **not** assume a session SQLite todo database exists
- Use only VS Code-compatible custom agents present in this workspace
- Default scope: current session and current changes only
- Ignore unrelated workspace changes unless explicitly requested

These constraints are the primary divergence point from CLI fleet and must be preserved in any derived variant.

---

## Workflow Shape

The generic fleet runs a 10-step lifecycle:

| Step | Phase | Description |
|---|---|---|
| 1 | **Decompose** | Read user request; break into work items |
| 2 | **Wave planning** | Group independent items into the same wave; order dependent items across waves |
| 3 | **Wave execution** | Execute waves sequentially |
| 4 | **Parallel dispatch** | Within a wave, execute independent work items in parallel |
| 5 | **Wave critique** | After each wave: self-critique all changes; fix all issues; re-check until clean |
| 6 | **Wave commit** | Once clean: compose atomic commits for the wave only; auto-commit |
| 7 | **Holistic critique** | After all waves: review the entire session using git history as memory |
| 8 | **Holistic repair** | Resolve all issues found in the holistic critique |
| 9 | **Knowledge capture** | Extract durable lessons into `.docs` |
| 10 | **Cleanup commit** | Compose and commit any remaining relevant changes |

---

## Shared Artifact File System

The artifact store is the orchestration memory for the entire fleet session. Chat context carries only short summaries and file pointers.

### Session Root

```
.fleet-sessions/<SESSION_ID>/
```

**Session ID format:** `<YYMMDD>-<hhmmss>` — same convention as Ralph sessions (e.g., `260318-142300`).

### Directory Schema

| Path | Content | Written by |
|---|---|---|
| `metadata.yaml` | Session goal, scope, state, wave list | Orchestrator at session start |
| `waves/<WAVE_ID>/wave.md` | Wave objective, boundaries, exit criteria | Orchestrator before executing the wave |
| `waves/<WAVE_ID>/tasks/<TASK_ID>.md` | Individual work item brief, context, expected output | Orchestrator before dispatching the subagent |
| `waves/<WAVE_ID>/results/<TASK_ID>.md` | Subagent output summary and validation notes | Subagent (or orchestrator on behalf of subagent) |
| `waves/<WAVE_ID>/critique.md` | Wave-level self-critique findings | Orchestrator in critique step |
| `waves/<WAVE_ID>/repairs.md` | Issue resolution notes and follow-up edits | Orchestrator in repair step |
| `waves/<WAVE_ID>/commits.md` | Atomic commit grouping decisions and resulting commit hashes | Orchestrator in commit step |
| `knowledge/` | Durable insights staged for promotion into `.docs` | Orchestrator in knowledge capture step |
| `scratch/` | Disposable notes; safe to delete after cleanup | Orchestrator (temporary) |

### Artifact Rules

| Rule | Rationale |
|---|---|
| Write artifacts **before** dispatching the next subagent | Prevents state loss if context resets |
| Update in-place instead of duplicating | Avoids divergent state across wave boundaries |
| Point subagents at artifact paths instead of re-pasting context | Keeps chat context lean; artifacts are the SSOT |
| Keep each artifact focused on one decision, wave, or validation step | Reduces ambiguity when reviewing wave history |
| Keep wave history and commit records after cleanup | Durable session memory for future reference |
| Remove scratch artifacts during final cleanup | Reduces noise without losing structured history |

---

## Wave Lifecycle

```
WAVE START
  ↓ Write wave.md (objective, boundaries, exit criteria)
  ↓ Write tasks/<ID>.md for each work item
DISPATCH (parallel for independent items)
  ↓ Subagents run; write results/<ID>.md
CRITIQUE
  ↓ Write critique.md
  ↓ If issues found → fix → re-check → repeat
REPAIR
  ↓ Write repairs.md
  ↓ Confirm all issues resolved
COMMIT
  ↓ Compose atomic commits for this wave only
  ↓ Write commits.md with grouping decisions + hashes
WAVE END → advance to next wave, or holistic review
```

**Hard checkpoint:** No commit may be made until critique and repairs are complete.

---

## Commit Discipline

| Rule | Details |
|---|---|
| **Per-wave scope** | Commits contain only the changes produced in the current wave |
| **No cross-wave mixing** | Never mix wave N changes with wave N+1 changes in the same commit |
| **Atomic grouping** | Each commit represents one coherent logical change |
| **Git as wave memory** | The holistic review (step 7) uses git log to recall what each wave changed |
| **Cleanup pass** | After the final wave, any remaining relevant changes get a final cleanup commit |
| **Unrelated changes** | Ignored by default unless the user explicitly asks for broader scope |

---

## Knowledge Capture

Knowledge capture is a first-class output of every fleet session that surfaces new understanding.

| Target | What goes there |
|---|---|
| `.fleet-sessions/<SESSION_ID>/knowledge/` | Raw notes staged during the session |
| `.docs/<category>/<domain>/` | Promoted documentation after refinement |

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

| Agent | Use when |
|---|---|
| `Explore` | Read-only repository exploration, codebase Q&A, file discovery |
| `Generic-Research-Agent` | Broad validated research across any domain |
| `Planner` | Multi-step planning, task decomposition, dependency mapping |
| `Nexus` | Structured reasoning, synthesis, coordination across agents |
| `Ralph-v2-Orchestrator-VSCode` | Ralph-specific orchestration work (nested orchestration) |
| `Ralph-v2-Planner-VSCode` | Ralph planning subtasks |
| `Ralph-v2-Questioner-VSCode` | Discovery and Q&A within a Ralph session |
| `Ralph-v2-Executor-VSCode` | Ralph task execution |
| `Ralph-v2-Reviewer-VSCode` | Ralph quality validation |
| `Ralph-v2-Librarian-VSCode` | Ralph knowledge extraction and wiki promotion |
| `PM-Changelog` | Changelog or history-sensitive summarization |
| `Mermaid-Agent` | Wave, dependency, or flow diagrams |
| `Knowledge-Graph-Agent` | Durable knowledge extraction and synthesis |

**Routing principle:** Prefer the smallest number of subagents needed for good coverage. Do not create subagents for trivial single-step requests.

---

## Operating Style Principles

| Principle | Description |
|---|---|
| **Narrow assignments** | Each subagent receives one focused goal; no mixed objectives |
| **Explicit wave boundaries** | Every wave definition includes: what belongs, what waits, exit criteria, artifact file locations |
| **Concise results request** | Ask each subagent for: what completed, any blockers, any follow-up needed |
| **Reconcile before continuing** | After receiving results, validate against original goal before advancing |
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
- Commits created per wave (with hashes from commits.md)
- Whether .docs knowledge capture occurred
```

---

## Specialization Interface

This generic prompt is designed so domain-specific variants can be derived by overriding specific sections without changing the core wave lifecycle.

| Section to override | What changes |
|---|---|
| **Frontmatter** (`name`, `description`, `argument-hint`) | Identity and discoverability of the specialized variant |
| **Identity Constraints** | Remove or relax constraints irrelevant to the domain |
| **Subagent Routing** | Replace with domain-specialist agents |
| **Wave Discipline** | Adjust work-item granularity (e.g., "one test file per task" for SE) |
| **Commit Discipline** | Optional or adapted for non-code domains |
| **Knowledge Capture** | Point at domain-specific wiki paths |
| **Operating Style** | Add domain-specific assignment templates or result formats |

**What must not change in derived variants:**
- The 10-step lifecycle (decompose → wave → critique → repair → commit → holistic → knowledge → cleanup)
- The artifact file system schema (the stability of this schema is what makes sessions inspectable and resumable)
- The hard checkpoint between critique/repair and commit

---

## Planned Specialized Variants

| Variant | Domain | Status |
|---|---|---|
| `fleet` (this file) | Generic — any repository work | Active baseline |
| `fleet-se` | Software engineering — code, test, review, deploy | Planned |
| `fleet-marketing` | Marketing — content, campaigns, copy | Planned |

All variants derive from and extend this reference.
