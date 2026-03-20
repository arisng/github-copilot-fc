# Fleet Mode as Prompt Injection in Copilot CLI

> **Conceptual explanation** of why fleet mode is a prompt engineering pattern, not a new session type or runtime feature.

---

## The Core Mental Model

**Fleet mode = injecting a system prompt into the current session turn.**

No new session is created. No special runtime mode is activated. No additional infrastructure is spun up. When you run `/fleet`, this is the entirety of what happens:

```js
await t.session.instance.fleet.start({ prompt: userPrompt });
// which calls:
await session.send({ prompt: FLEET_SYSTEM_PROMPT + "\nUser request: " + userPrompt });
```

The current agent receives a prompt that tells it to behave as an orchestrator. The agent's LLM then interprets that prompt and begins dispatching subagents via `task()`. The "fleet mode" behavior emerges entirely from the LLM responding to the injected text — not from any code that runs differently.

This means:
- Any agent can be "in fleet mode" if it receives the fleet system prompt
- Fleet mode cannot be detected or blocked at the runtime level
- Fleet mode is as durable (or fragile) as the prompt that drives it

---

## Why the Injection Pattern Matters

### The Current Agent Becomes the Orchestrator

When the fleet system prompt lands in a session, the agent that receives it is promoted to orchestrator role. If you run `/fleet` while using a generic Copilot session, the generic Copilot agent becomes the orchestrator. If you run it while a ralph-v2 orchestrator agent is active, the ralph-v2 orchestrator — which already has its own orchestration instructions — receives the fleet prompt on top of its existing identity.

This has a practical implication: **the quality of fleet orchestration is bounded by the quality of the receiving agent's underlying instructions**. The fleet system prompt gives the agent the coordination protocol (SQL todo queries, parallel dispatch, status updates), but the agent's judgment about *what* tasks to create and *how* to describe them comes from its own instructions.

### The Fleet System Prompt Is Self-Contained

The fleet system prompt is not a configuration file or an agent definition — it is a complete behavioral specification delivered at runtime:

```
You are now in fleet mode. Dispatch sub-agents (via the task tool) in parallel to do the work.

**Getting Started**
1. Check for existing todos: SELECT id, title, status FROM todos WHERE status != 'done'
2. If todos exist, dispatch them in parallel (respecting dependencies)
3. If no todos exist, help decompose the work into todos first.
...
```

It tells the agent *exactly* what to do: check the SQL database, find ready todos, dispatch them with status-update instructions, validate results, iterate. No configuration required. No agent file changes. A single prompt injection activates the entire pattern.

---

## How the Fleet System Prompt Is Constructed

The `fleet.start()` function has two construction paths:

```js
// With user prompt:
n = `${FLEET_SYSTEM_PROMPT}\nUser request: ${e.prompt}`

// Without user prompt:
n = FLEET_SYSTEM_PROMPT
```

The `FLEET_SYSTEM_PROMPT` constant is a fixed string baked into the `index.js` bundle. When `/fleet some task` is typed, the user's task description is appended after the full system prompt. The agent sees both: the orchestration instructions first, then the specific task to accomplish.

The `displayPrompt` shown in the UI is separate and human-readable:
- With prompt: `"Fleet deployed: <user prompt>"`
- Without prompt: `"Fleet deployed"`

This is purely cosmetic — the LLM never sees the display prompt.

---

## The Todo-SQL Coordination Pattern

The fleet system prompt's core mechanism is the **session SQLite database** as a coordination bus:

```sql
-- Orchestrator: find ready todos (dependencies satisfied)
SELECT * FROM todos
WHERE status = 'pending'
AND id NOT IN (
  SELECT todo_id FROM todo_deps td
  JOIN todos t ON td.depends_on = t.id
  WHERE t.status != 'done'
)

-- Subagent: report success
UPDATE todos SET status = 'done' WHERE id = '<todo-id>'

-- Subagent: report blocker
UPDATE todos SET status = 'blocked' WHERE id = '<todo-id>'
```

The SQL database acts as shared mutable state between the orchestrator and all subagents running in background mode. The orchestrator writes the todo rows; subagents read their assignment from the prompt and write back status. The orchestrator can poll for completions by re-querying.

This is a significant design choice: coordination happens through data (a database row) rather than through direct message passing. This means:
- Subagents don't need to know about each other
- The orchestrator can track progress without blocking on individual agents
- The dependency graph (`todo_deps`) is explicit and queryable
- Session state survives agent restarts within the same session

---

## `autopilot_fleet` — The Implicit Trigger

Fleet mode can also activate without an explicit `/fleet` command:

```js
// index.js ~11678584
if (x === "autopilot_fleet") this.fleet.start({});
```

When `exit_plan_mode` is called with the value `autopilot_fleet`, fleet starts automatically with no user prompt. This is the path for autonomous plan-then-execute workflows: the agent generates a plan, the user approves it (or the agent decides to proceed), and fleet mode kicks in to execute the plan via the same injection mechanism.

The result is identical to running `/fleet` with no arguments — the fleet system prompt is injected, and the agent begins executing whatever todos already exist.

---

## Connection to Ralph-v2: Fleet Made Explicit

Ralph-v2 is the fleet pattern made **explicit, structured, and multi-iteration**.

Fleet mode gives any agent the coordination protocol. Ralph-v2 is an agent architecture that *embeds* the coordination protocol as its primary design:

| Aspect           | Fleet mode                       | Ralph-v2                                           |
| ---------------- | -------------------------------- | -------------------------------------------------- |
| Trigger          | `/fleet` or `autopilot_fleet`    | User invokes ralph orchestrator                    |
| Orchestrator     | Current session agent (ad-hoc)   | `ralph-v2-orchestrator-CLI` (dedicated)            |
| Task breakdown   | LLM decides what todos to create | Planner agent creates structured tasks             |
| Subagents        | Any available `agent_type`       | Named specialist agents (executor, reviewer, etc.) |
| Iteration        | Single pass to completion        | Explicit iteration cycles with review gates        |
| Task tracking    | SQL todos + todo_deps (session SQLite) | Markdown files: `iterations/<N>/tasks/<id>.md`; SSOT: `progress.md` |
| State tracking   | Session SQLite                   | `metadata.yaml` (state machine) + `progress.md` (SSOT) |

The fleet system prompt says: *"check todos, dispatch agents, validate results, iterate."* Ralph-v2's orchestrator instructions say the same thing, but with more structure: the planner writes structured task files (`iterations/<N>/tasks/<task-id>.md`), the executor reports results back into those files, the reviewer validates against spec, and the librarian extracts knowledge to the wiki. State is tracked via `metadata.yaml` (state machine) and `progress.md` (SSOT per iteration) — not SQL tables.

**Ralph-v2 is what happens when you productionize the fleet pattern.**

### Why Ralph-v2 Doesn't Need `/fleet`

The ralph-v2 orchestrator has `disable-model-invocation: true`, which means it cannot be *dispatched as a subagent* by another agent — including a fleet-mode session agent. And since the orchestrator's instructions already encode the parallel dispatch pattern, running `/fleet` while inside ralph-v2 would inject a duplicate, potentially conflicting orchestration prompt.

Ralph-v2 manages its own fleet behavior without the fleet injection.

---

## When to Use Fleet vs Ralph-v2

### Use `/fleet` when:

- **Ad-hoc parallelism**: You have a list of independent tasks and want to execute them now without setting up a structured workflow
- **Existing todos**: You've already populated the SQL todos table and just want to dispatch everything in parallel
- **Quick delegation**: You want the current agent to spin up specialist subagents for a one-off task
- **Exploration**: You want to understand what fleet orchestration does before building a structured workflow around it

### Use Ralph-v2 when:

- **Structured iteration**: The work spans multiple rounds of planning, execution, and review
- **Quality gates**: You need a reviewer to validate output before declaring a task done
- **Knowledge capture**: You want the librarian to extract and promote knowledge to the wiki
- **Reproducibility**: You need consistent task formats, frontmatter conventions, and artifact templates
- **Complex dependencies**: The dependency graph between tasks is non-trivial and needs explicit management
- **Multi-session work**: Tasks span multiple sessions and need durable state

### The decision heuristic:

> Fleet = "do this now, in parallel, best effort"  
> Ralph-v2 = "do this correctly, with review, capturing what we learn"

---

## Summary: Why This Mental Model Matters

Understanding fleet mode as prompt injection rather than a runtime feature has concrete implications:

1. **Any agent can be a fleet orchestrator** — the capability is not locked to specific agent types
2. **Fleet quality scales with agent quality** — injecting the fleet prompt into a poorly-scoped agent produces poor fleet orchestration
3. **Custom agents can replicate fleet behavior** — by encoding parallel dispatch and coordination in their own instructions (ralph-v2 does this, but uses structured markdown task files and `progress.md` rather than SQL todos)
4. **Fleet is stateless** — it relies entirely on the SQL database for coordination; if the session resets, the todos persist but the orchestrator's in-flight reasoning does not
5. **The prompt injection is the only thing** — there is no fleet "server," no background daemon, no special runtime. The LLM reading the fleet system prompt *is* the fleet mode

See also:
- [Fleet and Task Subagent Dispatch Reference](../../../../reference/copilot/cli/fleet-and-task-subagent-dispatch.md) — complete technical schema
- [Ralph Subagent Contracts](../../../../reference/ralph/ralph-subagent-contracts.md) — how ralph-v2 names and wires its agents
- [Orchestrator Router Contract Boundary](../../../../reference/ralph/orchestrator-router-contract-boundary.md) — `disable-model-invocation` design rationale
