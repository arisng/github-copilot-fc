# Fleet and Task Subagent Dispatch in Copilot CLI

> **Last grounded**: April 2026 — current GitHub Docs + `github/copilot-cli` changelog, with historical v1.0.2 reverse-engineering preserved below
> **Scope**: Current verified behavior first; older bundle-derived internals second

Current public sources:

- [Running tasks in parallel with the `/fleet` command](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/fleet)
- [Speeding up task completion with the `/fleet` command](https://docs.github.com/en/copilot/how-tos/copilot-cli/speeding-up-task-completion)
- [Allowing GitHub Copilot CLI to work autonomously](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/autopilot)
- [GitHub Copilot CLI command reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference)
- [Custom agents configuration](https://docs.github.com/en/copilot/reference/custom-agents-configuration)
- [`github/copilot-cli` changelog](https://github.com/github/copilot-cli/blob/main/changelog.md)

---

## Overview

`/fleet` is the documented Copilot CLI command for parallel subagent execution. It lets the main agent decompose suitable work into subtasks and orchestrate subagents where dependencies allow.

The user-visible operational surfaces around that behavior are now:

- `/fleet` for starting parallel orchestration;
- `/tasks` for viewing and managing background task execution;
- `/agent` and custom-agent configuration for influencing which specialist agents are available.

The detailed `task()` schema and dispatch flow described later in this document remain useful, but they should be read as **historical reverse-engineering of v1.0.2 internals**, not as the current public product contract.

---

## Current verified behavior (March-April 2026)

### `/fleet`

Current GitHub Docs describe `/fleet` as a command that lets the **main agent** analyze a request, break it into subtasks, and run subagents in parallel where possible. The orchestrator agent remains responsible for dependencies and result synthesis.

### Relationship to autopilot

Autopilot and `/fleet` are distinct features:

- **Autopilot** governs whether Copilot keeps working autonomously.
- **`/fleet`** governs whether Copilot parallelizes suitable work with subagents.

The documented plan-mode workflow now includes an **autopilot + `/fleet`** approval path for work that looks parallelizable.

### Monitoring with `/tasks`

The `/fleet` how-to now tells users to monitor subagent/background work through `/tasks`, including:

- opening task details;
- killing a running task;
- removing completed or killed entries.

The upstream changelog shows continuing refinement of this surface: `/tasks` was added, recent activity was added, human-readable subagent IDs were introduced, idle subagents stopped cluttering the list, and background-agent progress became more visible.

### Current default and custom agent surfaces

Current public docs explicitly name four default agents:

- **Explore**
- **Task**
- **General-purpose**
- **Code-review**

Current public docs also document the following custom-agent frontmatter fields as supported:

- `model`
- `disable-model-invocation`
- `user-invocable`
- `mcp-servers`

The command reference also exposes agent/task delegation tools in the CLI tool inventory, including:

- `task`
- `read_agent`
- `list_agents`

The public docs do **not** currently publish a full parameter-by-parameter `task()` schema. That lower-level detail is preserved below as version-scoped historical analysis.

---

## Current surface summary

| Surface | Current public meaning | Notes |
|---|---|---|
| `/fleet [PROMPT]` | Start parallel subagent orchestration for suitable work | Main agent stays orchestrator |
| Autopilot mode | Continue autonomously without waiting for user input | Often paired with `/fleet`, but separate |
| `/tasks` | View/manage background tasks and subagent work | Operational monitoring surface |
| `/agent` | Manually select a custom agent | User-facing custom-agent picker |
| `model` in custom agents | Pin a model for a custom agent | Publicly documented in current schema |
| `disable-model-invocation` | Prevent automatic model selection of a custom agent | Still allows manual invocation unless `user-invocable: false` |

---

## Historical v1.0.2 reverse-engineered internals

The sections below preserve the earlier v1.0.2 analysis because they still help explain how `/fleet` and task-based dispatch appeared to work internally. Read them as **historical notes**, not April 2026 guarantees.

### Observed `/fleet` command

```ts
{
  name: "/fleet",
  args: "[prompt]",
  help: "Enable fleet mode for parallel subagent execution",
  execute: async (t, e) => {
    let n = e.join(" ").trim();
    await t.session.instance.fleet.start({ prompt: n || undefined });
    return { kind: "noop" };
  }
}
```

In the observed v1.0.2 bundle, `/fleet` delegated directly to `session.fleet.start()` and returned a `noop` result rather than switching to a separate top-level session type.

### Observed `session.fleet.start()` behavior

```js
function HEr(t) {
  return {
    async start(e) {
      let n = e?.prompt
        ? `${FLEET_SYSTEM_PROMPT}\nUser request: ${e.prompt}`
        : FLEET_SYSTEM_PROMPT;
      await t.send({
        prompt: n,
        displayPrompt: e?.prompt ? `Fleet deployed: ${e.prompt}` : "Fleet deployed"
      });
      return { started: true };
    }
  };
}
```

Observed v1.0.2 behavior:

- with a prompt, the user request was appended to a fixed orchestration prompt;
- without a prompt, only the orchestration prompt was sent;
- the orchestration text was delivered to the **current** session agent.

### Historical alternative trigger: `autopilot_fleet`

```js
if (x === "autopilot_fleet") this.fleet.start({});
```

The earlier bundle analysis observed an `autopilot_fleet` path when leaving plan mode. Current public docs explain the same workflow through the plan approval UX instead of internal trigger names.

### Historical orchestration prompt excerpt

The observed v1.0.2 orchestration prompt told the active agent to:

```text
You are now in fleet mode. Dispatch sub-agents (via the task tool) in parallel to do the work.

1. Check for existing todos
2. Dispatch ready todos in parallel
3. Update todo status when sub-agents finish
4. Validate the completed work
```

That historical prompt is why older documentation often explained fleet through the session SQLite `todos` and `todo_deps` tables.

### Observed v1.0.2 `task()` schema

```ts
{
  description: string,
  prompt: string,
  agent_type: string,
  model?: string,
  mode?: "sync" | "background"
}
```

Observed meaning in the older bundle analysis:

| Field | Historical meaning |
|---|---|
| `description` | Short UI intent label |
| `prompt` | Full instructions for the subagent |
| `agent_type` | Built-in type name or custom-agent `name:` |
| `model` | Per-dispatch model override |
| `mode` | `sync` or `background` |

### Observed built-in agent types in the v1.0.2 bundle

The earlier bundle analysis observed this set:

| `agent_type` | Default model | Purpose |
|---|---|---|
| `task` | `claude-haiku-4.5` | General command execution |
| `explore` | `claude-haiku-4.5` | Codebase exploration |
| `code-review` | `claude-sonnet-4.5` | Code review |
| `research` | `claude-sonnet-4.6` | Research across sources |
| `general-purpose` | session model | Full-capability reasoning |

This table is **version-scoped**. Current public docs only name Explore, Task, General-purpose, and Code-review as the default agent set.

### Observed custom-agent resolution

The older analysis observed:

1. built-in agent-type resolution first;
2. custom-agent lookup by exact `name:` match second;
3. an error if neither matched.

It also observed `disable-model-invocation: true` filtering an agent out of `task()` target resolution while still allowing direct top-level user invocation.

Those observations remain directionally consistent with today's public custom-agent schema, but the exact runtime behavior should still be treated as historical until revalidated against a current bundle.

### Observed v1.0.2 model resolution priority

The older analysis observed this priority order:

1. `model` parameter passed to `task()`
2. `model` set in custom-agent frontmatter
3. outer session model

That historical chain is now less speculative than it used to be because current public docs explicitly document the `model` field in custom-agent configuration. Even so, the exact fallback logic and cost guards described in the v1.0.2 bundle remain version-scoped details.

### Historical v1.0.2 dispatch flow

```text
User types /fleet [prompt]
        │
        ▼
session.fleet.start({prompt})
        │
        ▼
Current session agent receives orchestration prompt
        │
        ▼
task(agent_type, description, prompt, model?, mode?)
        │
        ├─ built-in type?  -> built-in loader
        └─ custom type?    -> custom-agent loader
        │
        ▼
Subagent runs
        │
        ▼
Orchestrator receives result and continues
```

---

## Historical source index (v1.0.2 analysis)

The earlier reverse-engineering pass extracted details from these bundle locations:

| Source | Historical content |
|---|---|
| `index.js:12471712` | `/fleet` command handler |
| `index.js:11574900` | `fleet.start()` and orchestration prompt |
| `index.js:11678584` | `autopilot_fleet` path |
| `index.js:10274211` | Custom-agent config builder |
| `index.js:10275000` | Task-tool agent resolution |
| `index.js:10284849` | Built-in and custom agent loaders |
| `index.js:11430912` | Model resolution and agent runner |
| `index.js:9738564` | Background-agent tracker |
| `sdk/index.d.ts:686176` | `SweCustomAgent` type |
| `sdk/index.d.ts:146257` | `getCustomAgents()` signature |

---

## Constraints

- Use the **current public docs and changelog** for present-tense product behavior.
- Use the **historical sections above** only when the version scope matters.
- Do not treat the v1.0.2 built-in agent table, prompt text, or exact loader call graph as the current public contract without revalidation.

---

## Related docs

- [Understanding `/fleet` orchestration in Copilot CLI](../../../../explanation/copilot/cli/fleet-mode-as-prompt-injection.md)
- [Copilot CLI Session Topology and Orchestration Layer](../../../../explanation/copilot/cli/copilot-cli-session-topology.md)
- [Fleet Orchestration: CLI vs VS Code Comparative Analysis](../../../../explanation/copilot/shared/fleet-cli-vs-vscode-comparison.md)
