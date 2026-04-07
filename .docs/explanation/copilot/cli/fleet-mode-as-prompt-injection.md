# Understanding `/fleet` orchestration in Copilot CLI

> **Last grounded**: April 2026 — current GitHub Docs + `github/copilot-cli` changelog, with older v1.0.2 bundle analysis preserved as historical context
> **Audience**: Readers who want to understand what `/fleet` is, why it behaves the way it does, and where the older "prompt injection" mental model still helps

Current public sources:

- [Running tasks in parallel with the `/fleet` command](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/fleet)
- [Speeding up task completion with the `/fleet` command](https://docs.github.com/en/copilot/how-tos/copilot-cli/speeding-up-task-completion)
- [Allowing GitHub Copilot CLI to work autonomously](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/autopilot)
- [Custom agents configuration](https://docs.github.com/en/copilot/reference/custom-agents-configuration)
- [`github/copilot-cli` changelog](https://github.com/github/copilot-cli/blob/main/changelog.md)

---

## Background

This page originally explained `/fleet` almost entirely through a reverse-engineered Copilot CLI v1.0.2 bundle. That framing was useful when `/fleet` had little or no public product documentation, but it is no longer the best primary explanation.

As of April 2026, GitHub documents `/fleet` as a first-class Copilot CLI feature for parallel subagent execution. The current public contract is product-level and workflow-level: the main agent decomposes work, chooses subagents when appropriate, runs tasks in parallel when dependencies allow, and exposes progress through the CLI UI.

The older bundle-derived "prompt injection" model still has value, but it is best treated as **historical implementation context**, not as the primary definition of what `/fleet` is.

---

## The core concept

`/fleet` is best understood as a **parallel orchestration feature**.

When you use `/fleet`, the main Copilot CLI agent analyzes the request, decides whether the work can be broken into smaller tasks, and acts as orchestrator for any subtasks that can be delegated to subagents. The orchestrator manages dependencies and synthesizes results back into the main session.

This means the important present-tense mental model is:

- the **main agent** stays in charge;
- **subagents** are workers for parts of the task;
- **parallelism** happens only where the work is independent enough to benefit from it.

That model is stable even if the underlying runtime implementation evolves.

---

## Why autopilot is related but distinct

Autopilot and `/fleet` are often used together, but they answer different questions.

- **Autopilot** answers: *should Copilot keep going without waiting for me?*
- **`/fleet`** answers: *should Copilot split this work and run parts in parallel?*

Current GitHub Docs explicitly describe them as distinct features. A common workflow is:

1. Use plan mode to shape the work.
2. Accept the plan and continue with **autopilot + `/fleet`** when the work looks parallelizable.
3. Let the main agent orchestrate subagents while still driving the overall task to completion.

This distinction matters because older internal trigger names such as `autopilot_fleet` are not the user-facing contract anymore. The user-facing contract is the documented plan/autopilot/`/fleet` workflow.

---

## Why `/tasks` matters

`/tasks` is the operational surface that makes modern `/fleet` behavior visible.

GitHub's `/fleet` how-to now tells users to monitor subagent/background work through `/tasks`, where they can inspect progress, open task details, kill a task, and remove completed entries. The upstream changelog also shows steady post-launch work on task visibility: `/tasks` was added, background-agent progress became richer, subagent IDs became human-readable, recent activity was added, and idle subagents stopped cluttering the list.

This is one of the clearest reasons the older "fleet is only prompt injection" framing is now incomplete. Whatever the low-level implementation details are, `/fleet` now has a visible orchestration workflow and a visible monitoring surface in the product.

---

## Why the historical prompt-injection model is still useful

The older v1.0.2 reverse-engineering work still explains something real: `/fleet` appears to have worked by injecting orchestration instructions into the current session turn, causing the active agent to adopt orchestrator behavior.

That historical model remains useful for understanding:

- why the **current agent** becomes the orchestrator rather than spawning a second top-level user session;
- why the **quality of the active agent's instructions** can shape fleet behavior;
- why **custom agents** and their configuration matter when subagents are selected.

But that insight is best phrased like this:

> A historical v1.0.2 implementation appears to have activated fleet by injecting orchestration instructions into the main session. Treat that as an implementation note that helps explain behavior, not as the primary product contract.

That wording keeps the useful intuition without overstating undocumented internals as current truth.

---

## Historical implementation notes from v1.0.2 analysis

The following points are preserved because they are still useful for advanced reasoning, but they are **version-scoped** observations rather than April 2026 product guarantees.

### Historical prompt-construction model

The earlier bundle analysis observed `/fleet` dispatching through `session.fleet.start()` and then calling `session.send()` with an orchestration prompt plus the user request. That historical note supports the intuition that the active agent received additional orchestration instructions instead of switching to a separate "fleet session" type.

### Historical SQL coordination pattern

The earlier observed fleet prompt coordinated work through the per-session SQLite database, especially `todos` and `todo_deps`. That historical detail helps explain why fleet could reason about readiness and dependencies inside one session.

However, current public docs do **not** require readers to understand `/fleet` through SQL tables. For most users, the higher-level orchestrator/subagent model plus `/tasks` is the correct conceptual layer.

### Historical `autopilot_fleet` trigger

The older bundle analysis also observed an `autopilot_fleet` path tied to exiting plan mode. That remains useful as historical evidence that plan-to-build flows were wired into fleet execution early on.

Today, the clearer explanation is the public one: plan mode can hand off to **autopilot + `/fleet`** through the CLI's approval flow.

---

## Comparison to Ralph-v2 in this workspace

Ralph-v2 is a useful local analogy because it makes orchestration explicit and durable.

| Aspect | Copilot CLI `/fleet` | Ralph-v2 in this workspace |
|---|---|---|
| Primary purpose | Ad-hoc parallel orchestration for the current task | Structured multi-step orchestration with review and knowledge capture |
| Main orchestrator | Current Copilot CLI session agent | Dedicated Ralph orchestrator |
| User-visible monitoring | `/tasks` and timeline | Ralph artifacts, iteration state, review outputs |
| Best mental model | Product-level orchestration feature | Repository-specific orchestration workflow |

This comparison is helpful for local readers, but it should stay secondary. Ralph-v2 explains **this repository's** workflow choices; it does not define Copilot CLI's `/fleet` semantics.

---

## Different perspectives

Some readers care most about the **current product contract**. For them, the right explanation is simple: `/fleet` parallelizes suitable work by letting the main agent orchestrate subagents, often alongside autopilot, and `/tasks` is the operational window into that work.

Other readers care about the **historical implementation story**. For them, the prompt-injection model is still useful because it explains why the active agent's prompt and instruction set matter so much to fleet quality.

Both perspectives are valid. The important documentation change is only the ordering:

1. current public behavior first;
2. historical implementation notes second.

---

## Further reading

- **Reference**: [Fleet and Task Subagent Dispatch in Copilot CLI](../../../../reference/copilot/cli/fleet-and-task-subagent-dispatch.md)
- **Related explanation**: [Copilot CLI Session Topology and Orchestration Layer](./copilot-cli-session-topology.md)
- **Shared comparison**: [Fleet Orchestration: CLI vs VS Code Comparative Analysis](../../shared/fleet-cli-vs-vscode-comparison.md)
