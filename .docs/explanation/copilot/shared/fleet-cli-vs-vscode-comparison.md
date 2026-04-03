# Fleet Orchestration: CLI `/fleet` vs VS Code `fleet.prompt.md`

> **Explanation** — understanding why the VS Code custom fleet prompt is designed differently from Copilot CLI's built-in `/fleet`, and how each design choice shapes orchestration behavior.

---

## Background

The VS Code `fleet.prompt.md` in this workspace is a **custom implementation** of the fleet orchestration concept, directly inspired by the built-in `/fleet` slash command in Copilot CLI — but adapted for the VS Code agent runtime, repository-safety requirements, and long-term quality goals.

Understanding how and why they differ is essential for:
- Refining the custom fleet prompt over time
- Knowing when to use one vs. the other
- Deriving domain-specific fleet variants from the generic VS Code baseline

See also:
- [Fleet Mode as Prompt Injection](../../cli/fleet-mode-as-prompt-injection.md) — deep-dive into how CLI `/fleet` works at the code level
- [Fleet and Task Subagent Dispatch Reference](../../../../reference/copilot/cli/fleet-and-task-subagent-dispatch.md) — authoritative schema for the CLI `task()` tool and agent type resolution
- [Fleet VS Code Generic Orchestrator Reference](../../../../reference/copilot/vscode/fleet-vscode-generic-orchestrator.md) — specification of the custom fleet prompt itself

---

## What They Share

Both are **prompt injection patterns**: they activate multi-agent orchestration by injecting a set of instructions into an active session. Neither creates a new runtime, session, or background daemon. The LLM receiving the injected text *is* the orchestrator — it interprets the instructions and begins dispatching subagents.

Both share:
- **Wave/parallel dispatch model**: independent tasks execute concurrently; serialized tasks wait for dependencies
- **Validation loop**: after subagents complete, the orchestrator validates and dispatches further work as needed
- **Single orchestrator turn**: there is no dedicated scheduling process — the orchestrator's LLM calls are the scheduler

Both also benefit from skills, but only the VS Code prompt can make workspace skills part of the repo-owned orchestration contract.

---

## Comparative Analysis

### 1. Nature and Activation

| Dimension                | VS Code `fleet.prompt.md`                                                    | CLI `/fleet`                                                                                       |
| ------------------------ | ---------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| **Nature**               | A `.prompt.md` customization file — repo-owned, version-controlled, editable | A built-in CLI slash command wrapping a fixed `FLEET_SYSTEM_PROMPT` constant baked into `index.js` |
| **Activation**           | User selects it from the VS Code prompt picker or types the prompt name      | `copilot /fleet [prompt]`, or auto-triggered by `exit_plan_mode` with `autopilot_fleet`            |
| **System prompt source** | The markdown body of `prompts/fleet.prompt.md`                               | `FLEET_SYSTEM_PROMPT` — immutable at runtime                                                       |
| **Customizable**         | Yes — editing the `.prompt.md` changes behavior for every future invocation  | No — requires forking the CLI source                                                               |

**Key implication:** The VS Code fleet prompt is a living artifact that evolves with the repository. The CLI fleet prompt is fixed infrastructure.

---

### 2. Orchestration Model

| Dimension                    | VS Code `fleet.prompt.md`                                                                                                    | CLI `/fleet`                                                                                                                                         |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Who becomes orchestrator** | The VS Code agent running the prompt (default Copilot agent, `agent: agent` frontmatter)                                     | The current session agent at the moment `/fleet` is typed                                                                                            |
| **Subagent dispatch**        | Named VS Code custom agents via `runSubagent` — routing table is encoded in the prompt                                       | `task(agent_type, prompt, mode?)` — resolves built-in types first, then custom agents by `name:` frontmatter                                         |
| **Parallelism model**        | Wave-based: items in the same wave are launched in parallel within a turn                                                    | True background dispatch: `mode: "background"` lets the orchestrator continue dispatching while prior agents run; results collected via `read_agent` |
| **Agent pool**               | VS Code custom agents only: `Planner`, `Nexus`, `Mermaid-Agent`, `Knowledge-Graph-Agent`, `Release-Notes-Writer`, `Ralph-v2-*`, etc. | Built-in types (`task`, `explore`, `code-review`, `research`, `general-purpose`) + custom agents by `name:` field                                    |
| **CLI-only agents**          | Explicitly disallowed — the prompt states "Do not rely on CLI-only built-in agent types"                                     | Native — the built-in types are the default pool                                                                                                     |

**Key implication:** CLI fleet has true background parallelism (agents continue running while the orchestrator moves on). VS Code fleet achieves parallelism by issuing multiple subagent calls within the same turn — a different model with similar outcomes for most use cases.

### 2.5 Agent Skills

| Dimension             | VS Code `fleet.prompt.md`                                                                                                     | CLI `/fleet`                                                                                                   |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| **Skill contract**    | The prompt can require the orchestrator and each subagent to activate the relevant workspace skills for the current work item | Skill use is external to the built-in slash command; it is not part of the CLI fleet contract itself           |
| **Routing shape**     | The prompt should route by generic role first, then map that role to the actual VS Code agent available in the workspace      | Routing is centered on CLI built-in agent types first, then custom agents by `name:`                           |
| **Repository safety** | Skill requirements and artifact references are repo-owned and version-controlled alongside the prompt                         | Any skill guidance lives outside the fleet system prompt and is not part of the built-in orchestration surface |

**Key implication:** The VS Code version can enforce skill activation as part of the orchestration text itself, which makes the workflow easier to review and keep in sync with repository documentation.

---

### 3. Coordination and State

| Dimension                 | VS Code `fleet.prompt.md`                                                                                                                | CLI `/fleet`                                                                                                   |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| **Shared state medium**   | Persistent files on disk: `.fleet-sessions/<SESSION_ID>/iterations/<N>/…` plus session-level `metadata.yaml` and per-iteration artifacts | Session SQLite database: `todos` + `todo_deps` tables                                                          |
| **Dependency tracking**   | Wave ordering by authoring discipline — B in a later wave than A means B depends on A                                                    | Explicit SQL: `todo_deps` rows queried at dispatch time                                                        |
| **State durability**      | Files survive session resets and LLM context loss; inspectable by humans                                                                 | SQLite persists within a session; survives agent restarts in the same session but is session-scoped            |
| **Context hand-off**      | Orchestrator points subagents at artifact file paths; chat context carries only summaries                                                | Orchestrator embeds the `todo_id` and full context in the `task()` prompt; subagents write status back via SQL |
| **Coordination coupling** | Loose — subagents write results to files the orchestrator reads later                                                                    | Tight — subagents must execute the exact SQL `UPDATE` statement included in their prompt                       |

**Key implication:** The file system approach is more durable and human-readable. SQL coordination is more automated and dependency-exact, but disappears with the session.

---

### 4. Iteration and Quality Discipline

| Dimension                | VS Code `fleet.prompt.md`                                                                                                         | CLI `/fleet`                                                                                                      |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| **Per-iteration review** | Mandatory — an iteration does not advance until `iterations/<N>/review.md` is complete and issues are resolved                    | None built-in — the prompt recommends validation but provides no enforcement mechanism                            |
| **Review gate**          | Hard checkpoint — commit step blocked until the review gate is clean                                                              | None — orchestrator may spawn additional todos if validation fails, but no formal barrier                         |
| **Holistic review**      | Steps 7–8: full review across all waves using git history as ground truth                                                         | Implicit — "ensure implementation is sensible" but no structured final pass                                       |
| **Commit discipline**    | Per-iteration atomic commits; no cross-iteration mixing; final cleanup pass; commit hashes recorded in `iterations/<N>/review.md` | No commit behavior specified — fleet delivers outputs, committing is the calling agent's or user's responsibility |
| **Knowledge capture**    | Steps 9–10: durable insights staged into `.docs`; `knowledge/` sub-directory in the session folder                                | None — no knowledge promotion concept in the CLI fleet system prompt                                              |

**Key implication:** The VS Code fleet prompt is a quality-first orchestration pattern. CLI fleet is a throughput-first pattern.

---

### 5. Artifact Storage

| Dimension           | VS Code `fleet.prompt.md`                                                                                                                                                                                                                                                                                                                                          | CLI `/fleet`                                             |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------- |
| **Artifact medium** | Named markdown files under `.fleet-sessions/<SESSION_ID>/`                                                                                                                                                                                                                                                                                                         | SQLite rows in the session database                      |
| **Types**           | `metadata.yaml`, `iterations/<N>/metadata.yaml`, `iterations/<N>/plan.md`, `iterations/<N>/progress.md`, `iterations/<N>/tasks/<ID>.md`, `iterations/<N>/reports/<ID>-report.md`, `iterations/<N>/questions/<CATEGORY>.md`, `iterations/<N>/feedbacks/<TIMESTAMP>/feedbacks.md`, `iterations/<N>/knowledge/`, `iterations/<N>/review.md`, `knowledge/`, `scratch/` | `todos` rows + `todo_deps` rows                          |
| **Human-readable**  | Yes — any artifact can be opened directly                                                                                                                                                                                                                                                                                                                          | No — requires a SQL query to inspect state               |
| **Post-session**    | Iteration history, review history, and commit records are kept in `review.md`; scratch artifacts are cleaned up                                                                                                                                                                                                                                                    | Session SQLite is session-scoped; no explicit cleanup    |
| **Resumability**    | Session can be resumed by reading `metadata.yaml` and iteration/task state from files                                                                                                                                                                                                                                                                              | Todos persist in SQLite; orchestrator reasoning does not |

---

## Key Structural Differences Explained

### The fleet system prompt is fixed; the VS Code prompt is repo-owned

Every `/fleet` invocation gets the same instructions, regardless of which repository you're working in. `fleet.prompt.md` is checked into this repo and encodes repo-specific rules: which agent types are available, what the wiki path is, what the commit format is. This is the foundation for domain-specific specialization.

### SQL coordination is session-ephemeral; file system coordination is durable

The SQL database is elegant for true parallel runtime coordination. But it disappears with the session context. File artifacts outlive sessions, can be reviewed by humans, and can be referenced across multiple sessions working on the same goal.

### VS Code fleet has mandatory quality gates; CLI fleet has optional validation

The CLI fleet prompt recommends validation. The VS Code fleet prompt encodes a *structural barrier*: the critique and repair steps are required before the commit step can proceed. The orchestrator's own instructions are the enforcement mechanism rather than a separate runtime check.

### CLI fleet captures no knowledge; VS Code fleet makes knowledge capture explicit

Steps 9–10 of the VS Code prompt, plus the `Knowledge Capture` section and the `knowledge/` sub-directory, make knowledge promotion to `.docs` a first-class output of every fleet session. This is the mechanism for continuous refinement of the repository's knowledge base.

---

## Conceptual Lineage

```
CLI /fleet                 fleet.prompt.md              Ralph-v2
─────────────────          ──────────────────────       ──────────────────────
Fixed prompt injection  →  Repo-owned, editable      →  Dedicated specialist 
SQL todos                  File system artifacts          agents
No quality gates           Critique + repair gates        Review gates + spec checks
No commits                 Per-wave atomic commits        Reviewer-guarded commits
No knowledge capture       .docs knowledge promotion      Librarian agent
Single pass                Single pass + cleanup          Multi-iteration cycles
                           (inspirable by humans)         State machine
```

`fleet.prompt.md` sits between CLI fleet and Ralph-v2:
- It inherits fleet's wave-and-dispatch *shape*
- It replaces SQL coordination with *file system artifacts* (closer to Ralph-v2)
- It adds *quality gates* and *knowledge capture*
- It does not have Ralph-v2's dedicated specialist agents, `metadata.yaml` state machine, or multi-iteration support

---

## The Specialization Strategy

`fleet.prompt.md` is designed as a **generic orchestration baseline**. The plan is to derive domain-specific variants that specialize the generic orchestration pattern for particular workflows:

| Variant                            | Specialization                      | Subagent Pool Adjustments                                      |
| ---------------------------------- | ----------------------------------- | -------------------------------------------------------------- |
| **Generic** (current)              | Any repository work                 | Generic role table first, then runtime-specific agent mappings |
| **Software Engineering** (planned) | Code changes, test, review, deploy  | Executor, Reviewer, repository exploration tools, test agents  |
| **Marketing** (planned)            | Content creation, campaign planning | Research, writing specialist agents                            |
| _(future domains)_                 | …                                   | …                                                              |

Points of specialization in the generic prompt that derived variants would override:
- **Subagent Routing** section — swap in domain-specialist agents
- **Agent Skills** section — add domain-specific skill requirements without removing the base enforcement model
- **Wave discipline** — adjust granularity for domain work units (e.g., "one test file per task" for SE, "one content asset per task" for marketing)
- **Knowledge Capture** — domain-specific wiki paths and nomenclature
- **Commit Discipline** — optional for non-code domains
- **Frontmatter** — `name`, `description`, `argument-hint` updated for the domain

The generic version deliberately does not hard-code domain assumptions, making it a valid orchestrator for mixed or exploratory work.

---

## Decision Guide

| Situation                                                     | Use                                                                 |
| ------------------------------------------------------------- | ------------------------------------------------------------------- |
| Quick parallel task dispatch in Copilot CLI                   | `/fleet`                                                            |
| Repo-aware orchestration in VS Code with quality gates        | `fleet.prompt.md`                                                   |
| Work that needs per-wave critique and atomic commits          | `fleet.prompt.md`                                                   |
| Work that needs wiki knowledge promotion                      | `fleet.prompt.md`                                                   |
| Structured multi-iteration work with review and spec-checking | Ralph-v2                                                            |
| Understanding how CLI fleet works internally                  | [Fleet Mode as Prompt Injection](../../cli/fleet-mode-as-prompt-injection.md) |
