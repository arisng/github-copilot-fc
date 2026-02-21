---
date: 2026-02-15
type: feedback
severity: medium
status: resolved
tags:
  - ralph-v2
  - workflow
---

# Ideas to Enhance Ralph v2 Workflow

## Agent Skills Enforcement

- Refining current mechanism to enforce agent skills discovery and activation in each subagent. Agent Skills are essential for the subagents to perform their tasks effectively, and we need to ensure that they are properly discovered and activated in each subagent. This may require adding more explicit checks and validations in the subagent's internal workflow to ensure that the required skills' full path are resolved correctly at runtime (Windows and Linux/WSL), thus ensure they are discovered successfully and activated before executing any task.
- For example, a subagent must proactively lookup available skills and activating the appropriate skills for the task at hand.
- Human (User) is responsible for curating the skills in the skills directory. The skills directory is a shared resource that all subagents can access to discover and activate skills. By default, the most effective way to discover and activate skills in the skills directory is to use the terminal commands (Windows or Linux/WSL).

## Iteration vs Session

- we must distinguish clearly the scope of iteration vs session:
  - iteration is a refinement on top of previous iteration with specific scope (if not first iteration) or an initial plan with specific scope (for first iteration). By convention, all iterations in a session should share the same scope, and the scope can be different across sessions.
  - For example: when we are in iteration 2 of a session, we should not have knowledge or assumptions about what will happen in iteration 3 or later iterations, because they may not even be planned yet. This also means that when we are in iteration 2 of a session, we should not have knowledge or assumptions about what happened in iteration 1 or previous iterations, because they may not be relevant, or up-to-date, or accurate for iteration 2.
  - For example: when in iteration 2, we should look back iteration 1 as committed work that is now part of the environment, but we should not look forward to iteration 3 as it is not yet planned and may change significantly. This means that when we are in iteration 2, we can refer to the outputs of iteration 1 as part of our context (inherit the direct previous iteration), but we should not refer to any outputs of iteration 3 or later iterations, because they are not even exist yet.
  - In a session, only the latest iteration is in active state, and all previous iterations are in completed state. The agents should only focus on the latest iteration and inherit context from the direct previous iteration (n: the current iteration, n-1: the direct previous iteration). The agents should not have any assumptions or expectations about what will happen in future iterations, because they are not planned yet and may change significantly. Each iteration should be treated as a self-contained unit of work with its own scope and context.

### Nomalizing shared artifacts structure

- ensure execution of atomic commits for each task in an iteration (using agent skill git-atomic-commit). Executor is not responsible for these atomic commits. The Reviewer should be responsible for executing these atomic commits after reviewing a task and pass the review.
- normalizing progress.md file structure so that each iteration should own its own progress.md file instead of sharing a single progress.md file across all iterations.
- normalizing tasks folder so that each iteration should own its own tasks folder instead of sharing a single tasks folder across all iterations. This is to ensure that each iteration is self-contained. Also moving task reports into the iteration folder as well, instead of sharing a single reports folder across all iterations.
- normalizing plan.md file structure so that each iteration should own its own plan.md file instead of sharing a single plan.md file across all iterations. Also stop creating `plan.iteration-<N>.md` in session level. This is to ensure that each iteration is self-contained. Considering stop creating delta.md file in iteration level as well, as the delta is kind of a report that is generated after the iteration plan is created. We are trying to concise the artifacts structure and avoid creating too many files that may cause confusion and unnecessary complexity.
- Critique if we also need to move signals folder into iteration level as well.

## Live Signal Enhancements

- refine current "Live Signals" checkpoint distribution across the workflow to ensure all agents (Orchestrator and all subagents) can receive and react to signals in a timely manner. For example, let's say you are a human (the watcher) observing the workflow, you want to be able to send a signal spontaneously at any point in time, and you want the Orchestrator or any relevant subagents to be able to react to that signal as soon as possible. This may require adding more "Live Signals" checkpoints in the orchestrator state machine and each subagent's internal workflow, and/or propose implementation plan of using "Hooks Integrations" to allow more solid and higher level of determinism of signal handling. Regarding the "Hooks Integrations", only propose the implementation plan and do not implement it yet, as it may require significant changes to the current workflow and we need to ensure that the implementation plan is well thought out and aligned with the overall goals of the Ralph v2 workflow.
- Clearly define definition of each Live Signal type (STEER, PAUSE, STOP, INFO, APPROVE, SKIP) and the expected behavior of the Orchestrator and subagents when receiving each type of signal.

### STEER vs INFO

- Critique the STEER vs INFO. STEER is more about re-routing the workflow to a different path, while INFO is more about providing additional information or context to the agents without necessarily changing the workflow path.
- For examples:
  - When the Orchestrator receives a STEER signal, it might re-route the workflow to REPLANNING state to adjust the plan.
  - When the Orchestrator receives an INFO signal, it refine the current context passed to subagents without changing the workflow path.
  - When a subagent receives a STEER signal, it re-route its internal workflow path based on the instructions in the signal, this includes trigger a loop back to any earlier steps in its internal workflow, or skip certain steps in its internal workflow, or even abort the current execution if necessary.
  - When a subagent receives an INFO signal, it adjust its internal context or parameters based on the information in the signal, but it does not change its internal workflow path. It continues to execute the next steps in its internal workflow as planned, but with the updated context or parameters from the INFO signal.

### PAUSE vs STOP/ABORT

- Critique the PAUSE vs STOP. PAUSE is more about temporarily halting the workflow with the intention to resume later, while STOP is more about permanently halting the workflow with no intention to resume. Considering rename STOP as ABORT to make it more clear that it is a permanent halt with no intention to resume, while PAUSE is a temporary halt with the intention to resume later.
- For examples:
  - When the Orchestrator receives a PAUSE signal, it would pause the entire workflow, then update relevant metadata files to reflect the paused state, and wait for user to resume the workflow with optional updates to the context.
  - When the Orchestrator receives a STOP/ABORT signal, it would terminate the entire workflow immediately and perform any necessary cleanup before exiting.
  - When a subagent receives a PAUSE signal, it might pause its current task and wait for further instructions from the Orchestrator or user before resuming.
  - When a subagent receives a STOP/ABORT signal, it might terminate its current task immediately and perform any necessary cleanup before exiting.

### APPROVE vs SKIP

- Human-in-the-loop approval is an important charactistic of an agentic workflow, and we are enabling for the Knowledge Staging and Promotion workflow in the Ralph-v2 Librarian agent.
- Human might not approve or skip extracted resuable knowledge in an iteration. This could mean that the human needs more time to review or defer to a later time, or would require a new iteration(s) for refinement then might approve the refined knowledge in the next new iteration or keep going through the refinement iterations until the human is satisfied and approve the knowledge.
- Should we allow human to approve knowledge of previous iteration(s)? It seems that this would introduce unnecessary complexity. Also if we enforce approval only on the lates iteration, then is it that we must always curate the knowledge from previous iterations to latest iteration and ensure they are reconciled with latest iteration's context? This might be a good practice to ensure that the knowledge is always up-to-date and relevant to the latest iteration, but it might also introduce additional overhead and complexity in curating the knowledge across iterations. We need to find a balance between ensuring the knowledge is relevant and up-to-date, while also minimizing the overhead and complexity of curating the knowledge across iterations. Let's critique this and implement the best approach.
