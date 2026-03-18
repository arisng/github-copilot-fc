# Fleet and Task Subagent Dispatch Reference

**Version:** Copilot CLI v1.0.2  
**Sources:** `index.js`, `sdk/index.d.ts`, `definitions/*.agent.yaml`

Authoritative reference for `/fleet`, `session.fleet.start()`, and the `task` tool subagent dispatch mechanism.

---

## `/fleet` Command

```ts
// index.js ~12471712
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

`/fleet` is a thin wrapper that delegates immediately to `session.fleet.start()`. It accepts an optional prompt string and returns a `noop` result — no new session is created.

---

## `session.fleet.start()`

```js
// index.js ~11574950 (function HEr)
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

**Behavior:**
- With `prompt`: prepends `FLEET_SYSTEM_PROMPT`, appends `User request: <prompt>`
- Without `prompt`: sends `FLEET_SYSTEM_PROMPT` as-is
- Calls `session.send()` on the **current** session — no new session is started
- `displayPrompt` is the human-readable label shown in the UI

### Alternative trigger: `autopilot_fleet`

```js
// index.js ~11678584
if (x === "autopilot_fleet") this.fleet.start({});
```

When `exit_plan_mode` is called with the `autopilot_fleet` value, fleet starts automatically with no user prompt.

---

## Fleet System Prompt (verbatim)

```
You are now in fleet mode. Dispatch sub-agents (via the task tool) in parallel to do the work.

**Getting Started**
1. Check for existing todos: SELECT id, title, status FROM todos WHERE status != 'done'
2. If todos exist, dispatch them in parallel (respecting dependencies)
3. If no todos exist, help decompose the work into todos first.

**Parallel Execution**
- Dispatch independent todos simultaneously
- Never dispatch just a single background subagent. Prefer one sync subagent, or better,
  prefer to efficiently dispatch multiple background subagents in the same turn.
- Only serialize todos with true dependencies (check todo_deps)
- Query ready todos: SELECT * FROM todos WHERE status = 'pending' AND id NOT IN (
    SELECT todo_id FROM todo_deps td JOIN todos t ON td.depends_on = t.id WHERE t.status != 'done')

**Sub-Agent Instructions**
When dispatching a sub-agent, include these instructions in your prompt:
1. Update the todo status when finished:
   - Success: UPDATE todos SET status = 'done' WHERE id = '<todo-id>'
   - Blocked: UPDATE todos SET status = 'blocked' WHERE id = '<todo-id>'
2. Always return a response summarizing what was completed, whether done, any blockers.

**After Sub-Agents Complete**
- Check work done by sub-agents and validate the original request is fully satisfied
- Ensure implementation is sensible, robust, and handles edge cases
- If not fully satisfied, decompose remaining work into new todos and dispatch more sub-agents

Now proceed with the user's request using fleet mode.
```

---

## `task` Tool

### Parameter Schema

```ts
// sdk/index.d.ts + index.js ~10284849
{
  description: string,          // 3-5 words, shown as intent in UI
  prompt: string,               // full task instructions for the agent
  agent_type: string,           // built-in type name OR custom agent name: field
  model?: string,               // optional LLM override (validated against available models)
  mode?: "sync" | "background"  // default: "sync"
}
```

### Agent Type Resolution Order

```js
// index.js ~10279000 (function Bsr)
if (ZBt(J))       // J is a built-in type?
  ne = await (await bms(J, cache, ...)).createAgentTool(callback, Ie).callback({...});
else if (E(J))    // J is in customAgents map?
  ne = await (await Gms(J, cache, customAgentsMap, ...)).createAgentTool(callback, Ie).callback({...});
else
  throw new Error(`Unknown agent type: ${J}`);
```

1. **Built-in check** (`ZBt`): tests against a hardcoded set of built-in type names (`explore`, `task`, `code-review`, `research`, `general-purpose`)
2. **Custom agent lookup** (`E` = `customAgentsMap.has`): the map is built from all loaded `*.agent.md` files, filtered to exclude `disableModelInvocation === true`
3. **Error**: if neither matches, throws `Unknown agent type`

> **Key fact:** For custom agents, `agent_type` must equal the `name:` frontmatter field of the target agent exactly.

### Background vs Sync Mode

**Sync (default):**  
The orchestrator blocks until the subagent returns a result string. Use for sequential dependencies.

**Background:**

```js
// index.js ~9738564
if (mode === "background") {
  let id = taskRegistry.startAgent(agentType, description, prompt, executeAgent, {
    modelOverride: Ie,
    toolCallId: ...,
    ownerId: sessionId,
    parentId: sessionId
  });
  return { textResultForLlm: `Agent started with agent_id: ${id}. Use read_agent...`, ... };
}
```

The orchestrator receives an `agent_id` immediately and continues. Use `read_agent` to collect results. Use for truly independent parallel tasks.

---

## Built-in Agent Types

| `agent_type` | Default Model | Tools | Purpose |
|---|---|---|---|
| `task` | `claude-haiku-4.5` | `["*"]` | General command execution |
| `explore` | `claude-haiku-4.5` | Read-only subset | Codebase exploration |
| `code-review` | `claude-sonnet-4.5` | `["*"]` | Code review (no modifications) |
| `research` | `claude-sonnet-4.6` | GitHub + web | Research across sources |
| `general-purpose` | _(session model)_ | `["*"]` | Full-capability, high-quality reasoning |

Source: `definitions/*.agent.yaml` from Copilot CLI v1.0.2 package.

---

## `SweCustomAgent` Type

```ts
// sdk/index.d.ts:686176
type SweCustomAgent = {
  name: string;                              // maps to name: frontmatter
  displayName: string;                       // maps to (derived from name)
  description: string;                       // maps to description: frontmatter
  tools: string[] | null;                    // maps to tools: frontmatter
  prompt: () => Promise<string>;             // lazily loads the markdown body
  mcpServers?: Record<string, MCPServerConfig>; // maps to mcp-servers: frontmatter
  disableModelInvocation: boolean;           // maps to disable-model-invocation: frontmatter
  /** When unset, inherits the outer agent's model.
   *  When set but unavailable, falls back to the outer agent's model. */
  model?: string;                            // maps to model: frontmatter
};
```

### Frontmatter → `SweCustomAgent` Field Map

| `*.agent.md` frontmatter key | `SweCustomAgent` field | Notes |
|---|---|---|
| `name:` | `name` | Used as `agent_type` in `task()` calls |
| `description:` | `description` | Shown in agent picker UI |
| `model:` | `model` | Optional; inherits session model if absent |
| `tools:` | `tools` | `null` resolves to `["*"]` (all tools) |
| `mcp-servers:` | `mcpServers` | Loaded on first invocation |
| `disable-model-invocation:` | `disableModelInvocation` | Excludes agent from `task()` target list |

**`getCustomAgents(authInfo, workingDir, integrationId?, logger?, settings?)`** scans `skillDirectories` for `*.agent.md` files and parses them into `SweCustomAgent` objects.

### Custom agent config builder

```js
// index.js ~10274211 (function ums)
function ums(agent, promptBody) {
  return {
    name:        agent.name,
    displayName: agent.displayName,
    description: agent.description,
    model:       agent.model,          // from model: frontmatter
    tools:       agent.tools ?? ["*"], // from tools: frontmatter
    promptParts: {
      includeAISafety:                true,
      includeToolInstructions:        true,
      includeParallelToolCalling:     true,
      includeCustomAgentInstructions: false,
      includeEnvironmentContext:      true,
    },
    prompt:     promptBody,            // loaded markdown body
    mcpServers: agent.mcpServers,      // from mcp-servers: frontmatter
  };
}
```

---

## `disable-model-invocation: true`

When a custom agent has `disable-model-invocation: true` in its frontmatter:

1. **Excluded from `task()` targets**: filtered out of `customAgentsMap` before agent type resolution
   ```js
   c = (t.customAgents ?? []).filter(k => k.disableModelInvocation !== true)
   ```
2. **Still usable as top-level session agent**: the flag only affects `task()` dispatch, not direct user invocation
3. **Prevents recursive dispatch**: no subagent can call the orchestrator as a subagent
4. **Orchestrator still makes LLM calls**: the flag does not suppress model invocation in the agent's own top-level turns

**Canonical usage (ralph-v2):**
- `ralph-v2-orchestrator-CLI` → `disable-model-invocation: true` (dispatches via `task()`)
- `ralph-v2-planner-CLI`, `ralph-v2-executor-CLI`, etc. → no `disable-model-invocation` (are dispatched via `task()`)

---

## Model Resolution Priority Chain

Model is resolved in this order (highest priority first):

```
Priority (highest → lowest):
┌──────────────────────────────────────────────────────────────────┐
│ 1. model: parameter passed to task() call                        │
│    → task("my-agent", "...", model="claude-opus-4.5")            │
├──────────────────────────────────────────────────────────────────┤
│ 2. model: frontmatter in the agent's *.agent.md                  │
│    → model: claude-sonnet-4.5                                    │
├──────────────────────────────────────────────────────────────────┤
│ 3. Session model (outer/parent agent's model)                    │
│    → inherited if neither 1 nor 2 is set, or if set model is     │
│      unavailable in the current user's subscription              │
└──────────────────────────────────────────────────────────────────┘

Cost guard (always applied after 1-3):
  If session model multiplier = 0 (free plan)
  AND target model multiplier > 0 (paid)
  → Downgrade to session model regardless of override
```

### Implementation: `Art.resolveDefinitionModel()`

```js
// index.js ~11430912 (Art class)
resolveDefinitionModel() {
  let definitionModel = this.definition.model;
  if (!definitionModel) {
    return sessionModel;                      // Level 3: inherit session
  }
  if (!availableModels.some(m => m.id === definitionModel)) {
    return sessionModel;                      // Level 3: model unavailable
  }
  let sessionMultiplier  = availableModels.find(m => m.id === sessionModel)?.multiplier;
  let targetMultiplier   = availableModels.find(m => m.id === definitionModel)?.multiplier;
  if (sessionMultiplier === 0 && targetMultiplier > 0) {
    return sessionModel;                      // Cost guard
  }
  return definitionModel;                     // Level 2: use definition model
}
```

### Implementation: `Art.getOrCreateAgent()`

```js
// index.js ~11430912 (Art class)
async getOrCreateAgent(callback, toolCallId, modelOverride?) {
  let finalModel = modelOverride || this.resolveDefinitionModel(); // Level 1: override wins
  // Creates CAPI client with model = finalModel
  // Loads tools, MCP servers
  // Returns { agent, tools }
}
```

---

## Full Data Flow

```
User types: /fleet [prompt]
         │
         ▼
  session.fleet.start({prompt})
         │  Prepends FLEET_SYSTEM_PROMPT to prompt
         │  Calls session.send({prompt: combined})
         ▼
  Current session agent (e.g. Copilot or ralph-v2 orchestrator)
  receives: "You are now in fleet mode. Dispatch sub-agents..."
         │
         │  LLM reasons: check todos, pick ready ones, dispatch
         ▼
  task(agent_type, description, prompt, model?, mode?)
         │
         ├─ agent_type is built-in? → load from definitions/*.agent.yaml
         │                              → bms() → Art instance
         │
         └─ agent_type is custom?  → find in customAgents map by name:
                                      → Gms() → load *.agent.md body
                                      → ums() → build definition
                                      → Art instance
                    │
                    ▼
            Art.createAgentTool(callback, modelOverride?)
                    │
                    ▼
            Art.getOrCreateAgent(callback, toolCallId, modelOverride?)
                    │
                    │  Final model = modelOverride OR resolveDefinitionModel()
                    │
                    ▼
            CAPI client with model=finalModel
            + tools (filtered by tools: frontmatter)
            + MCP servers (from mcp-servers: frontmatter)
                    │
                    ▼
            Subagent runs its task, returns textResultForLlm
                    │
         ◄──────────┘
  Orchestrator receives result string
  Updates todos, dispatches more subagents or declares done
```

---

## Source Index

All code extracted from Copilot CLI v1.0.2:

| File | Location | Content |
|---|---|---|
| `index.js:12471712` | `/fleet` command | Execute handler |
| `index.js:11574900` | `HEr()` | `fleet.start()` + `FLEET_SYSTEM_PROMPT` |
| `index.js:11678584` | `autopilot_fleet` path | Alternative fleet trigger |
| `index.js:10274211` | `ums()` | Custom agent config builder |
| `index.js:10275000` | `Bsr()` | Task tool: full agent resolution logic |
| `index.js:10284849` | `bms()` / `Gms()` | Built-in and custom agent loaders |
| `index.js:11430912` | `Art` class | Model resolution + agent runner |
| `index.js:9738564` | `TaskRegistry.startAgent()` | Background agent tracker |
| `sdk/index.d.ts:686176` | `SweCustomAgent` | Type definition |
| `sdk/index.d.ts:146257` | `getCustomAgents()` | Function signature |
| `definitions/*.agent.yaml` | Built-in agents | Agent type definitions |
