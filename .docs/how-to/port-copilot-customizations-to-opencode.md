# How to Port GitHub Copilot CLI Customizations to OpenCode

This guide maps the GitHub Copilot CLI customization model to OpenCode so you can port agents, instructions, prompts, skills, hooks, and plugins on demand. It targets the CLI runtime only.

## What you need

- OpenCode installed (`opencode --version`)
- A GitHub Copilot CLI customization artifact from this repository
- The mapping rules below

---

## 1. Decide what the artifact is

Use the decision tree to select the correct OpenCode target format.

```
Is it a SKILL.md?
└── YES → Copy directly to .opencode/skills/<name>/ or ~/.config/opencode/skills/<name>/. Done.

Is it a Copilot Prompt (*.prompt.md)?
└── YES → Create an OpenCode command (.opencode/commands/<name>.md) with the prompt body.
          Name it clearly. Invoke via /<name> in the TUI.

Is it a Copilot Instruction (*.instructions.md)?
└── YES → Check applyTo scope:
           ├── applyTo: '**' or very broad → AGENTS.md or opencode.json instructions array
           ├── Agent-coupled              → Embed in agent's prompt markdown
           └── Narrow / file-type-specific → Create an OpenCode skill, invoke on demand

Is it a Copilot Agent (*.agent.md)?
└── YES → Create an OpenCode agent markdown file (.opencode/agents/<name>.md).
          Translate tool names in frontmatter.
          Convert runSubagent calls to @ mentions or task tool instructions.
          Map handoffs to subagent definitions with mode: subagent.

Is it a Copilot Hook (*.hooks.json)?
└── YES → OpenCode has no native lifecycle hooks system.
           Fallback options:
           ├── Port logic as a custom tool or formatter if it gates/edits behavior
           ├── Port as an OpenCode plugin if you need deep integration
           └── Document as an agent instruction or AGENTS.md rule

Is it a Copilot Plugin (plugin.json bundle)?
└── YES → Decompose:
           ├── Skills → Copy to .opencode/skills/
           ├── Agents → Port as agent markdown files in .opencode/agents/
           └── Executable tools/commands → Port as custom tools (.opencode/tools/*.ts) or plugins
```

---

## 2. Map primitives

### 2.1 Skills (1:1 native)

OpenCode uses the same open Agent Skills format as Claude and Kimi.

| Source | Target |
|--------|--------|
| `skills/<name>/SKILL.md` | `.opencode/skills/<name>/SKILL.md` or `~/.config/opencode/skills/<name>/SKILL.md` |

Copy the folder verbatim. OpenCode also discovers skills from `.claude/skills/` and `.agents/skills/` as fallbacks.

### 2.2 Prompts → Commands

Copilot prompts are reusable user-facing prompt templates. In OpenCode, the closest equivalent is a **custom command** invoked with `/<name>` in the TUI.

1. Create `.opencode/commands/<prompt-name>.md`.
2. Copy the prompt body into the markdown content.
3. Add YAML frontmatter with `description` and optionally `agent` or `model`.

Example:

```markdown
---
description: Generate a changelog from git history
agent: build
---

Determine the date range from the user's request, then run the appropriate git log command and summarize the results into a markdown changelog.
```

Usage in TUI: `/changelog from last Monday to today`

#### Command template features

- `$ARGUMENTS` — all arguments passed to the command
- `$1`, `$2`, `$3` … — positional arguments
- `` !`command` `` — injects shell command output into the prompt
- `@file` — injects file content into the prompt

### 2.3 Instructions → Rules

Copilot instructions support `applyTo` glob patterns. OpenCode does not have file-conditional instruction loading. You must decompose an instruction into one of three context layers.

#### Layer A: Workspace context (`AGENTS.md`)
- **When to use**: Broad, always-on project conventions (equivalent to `applyTo: '**'`).
- **Where**: `AGENTS.md` in the project root, or `~/.config/opencode/AGENTS.md` globally.
- **Behavior**: Automatically included in the LLM context for every session in that workspace.

#### Layer B: Config-based external instructions (`opencode.json`)
- **When to use**: When you want to reference multiple modular instruction files without duplicating them into `AGENTS.md`.
- **Where**: `instructions` array in `opencode.json`.
- **Behavior**: All listed files are combined with `AGENTS.md` and injected into context.

Example:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": ["docs/development-standards.md", "test/testing-guidelines.md"]
}
```

#### Layer C: Agent context (`prompt` field)
- **When to use**: Domain-specific behavior tightly coupled to a specific custom agent.
- **Where**: The `prompt` field in an agent markdown file or `opencode.json` agent config.
- **Behavior**: Loaded as the agent's system prompt. Supports `{file:./path.txt}` substitution.

#### Layer D: On-demand context (`skill` tool)
- **When to use**: Narrow or file-type-specific rules (e.g., `applyTo: '**/*.py'`).
- **Where**: A skill under `.opencode/skills/<name>/SKILL.md`.
- **Behavior**: Injected only when the agent invokes the `skill` tool.

### 2.4 Agents → Agent markdown files

OpenCode agents are defined as markdown files with YAML frontmatter, which is structurally very similar to Copilot's `.agent.md` format.

#### File structure

```
.opencode/agents/
└── planner.md
```

#### Example agent file

```markdown
---
description: Researches and outlines multi-step plans
mode: primary
prompt: "{file:./prompts/planner.txt}"
permission:
  edit: deny
  bash: ask
---

You are a PLANNING AGENT. Your sole responsibility is planning. NEVER start implementation.
```

The markdown filename becomes the agent identifier (e.g., `planner.md` → `planner` agent).

You can also define agents in `opencode.json`:

```json
{
  "agent": {
    "planner": {
      "description": "Researches and outlines multi-step plans",
      "mode": "primary",
      "prompt": "You are a PLANNING AGENT...",
      "permission": {
        "edit": "deny",
        "bash": "ask"
      }
    }
  }
}
```

#### Tool name remapping

Copilot CLI agents use VS Code/Copilot-native tool names. OpenCode uses simpler tool identifiers.

| Copilot tool | OpenCode tool | Notes |
|--------------|---------------|-------|
| `read` / `readFile` | `read` | |
| `write` / `createFile` | `write` | Controlled by `edit` permission |
| `editFiles` / `strReplaceFile` | `edit` | Controlled by `edit` permission |
| `search` / `searchCodebase` | `grep` | Use with `glob` for broader search |
| `execute/runInTerminal` | `bash` | |
| `execute/getTerminalOutput` | `bash` | OpenCode `bash` is synchronous; no separate task output tool |
| `execute/awaitTerminal` | `bash` | |
| `execute/killTerminal` | N/A | No background task management in OpenCode |
| `vscode/askQuestions` | `question` | |
| `agent` / `runSubagent` | `task` / `@mention` | Subagents invoked via `@name` or the Task tool |
| `web` / `fetchURL` | `webfetch` | |
| `github/*` | N/A | Add a GitHub MCP server or custom tool |
| `memory` | N/A | Rely on session context |
| `todowrite` | `todowrite` | Built-in todo list tool |

#### Subagents

Copilot uses `#tool:agent/runSubagent` with arbitrary agent files. OpenCode supports:

1. **Built-in subagents**: `general` (multi-step research), `explore` (read-only search)
2. **Custom subagents**: Create an agent file with `mode: subagent`

For multi-agent systems (e.g., Ralph-v2), define each specialized agent as a separate markdown file with `mode: subagent`, then instruct the orchestrator agent to invoke them via `@planner`, `@executor`, etc., or through the `task` tool.

Example subagent:

```markdown
---
description: Fast read-only codebase exploration
mode: subagent
permission:
  edit: deny
  bash: deny
---

You are an exploration subagent. Use read, grep, and glob to research the codebase. Do not modify any files.
```

#### Handoffs

Copilot agents can declare `handoffs:` (UI buttons). OpenCode has no handoff UI primitive. Replace handoffs with natural language instructions in the system prompt that tell the agent when to return results to the user or delegate to a subagent via `@name`.

### 2.5 Hooks → No native equivalent

OpenCode does **not** have a lifecycle hooks system comparable to Copilot's `.hooks.json` or Kimi's `[[hooks]]`.

**Fallback strategies:**

1. **Post-edit automation** → Use [formatters](/docs/formatters) in `opencode.json` to run commands after file edits.
2. **Behavior gating** → Implement the logic as a [custom tool](/docs/custom-tools) that wraps or validates operations.
3. **Plugin** → Build an OpenCode plugin if you need deep runtime integration.
4. **Agent instructions** → Document the desired behavior in `AGENTS.md` or the agent's prompt so the LLM follows the protocol voluntarily.

### 2.6 Plugins → Decomposed skills, agents, and custom tools

GitHub Copilot plugins are bundles (agents + skills + hooks). OpenCode plugins are **npm packages** or local extensions that provide custom tools, hooks, and integrations.

When porting a Copilot plugin:

1. **Skills** → Copy directly to `.opencode/skills/`.
2. **Agents** → Port as agent markdown files in `.opencode/agents/`.
3. **Executable commands/tools** → Port as [custom tools](/docs/custom-tools) (TypeScript/JavaScript files in `.opencode/tools/`) or as OpenCode plugins.

There is no OpenCode equivalent for a "bundle manifest" that groups agents and skills. You must distribute components separately.

#### Custom tool example

If the Copilot plugin provided an executable command, wrap it as a custom tool:

```typescript
// .opencode/tools/greet.ts
import { tool } from "@opencode-ai/plugin"

export default tool({
  description: "Generate a greeting message",
  args: {
    name: tool.schema.string().describe("Name to greet"),
  },
  async execute(args) {
    return `Hello, ${args.name}!`
  },
})
```

---

## 3. Multi-target factory maintenance

To keep this repository a source factory for multiple coding agents (Copilot, OpenCode, Kimi, Claude, etc.), use a **source + renderer** pattern:

1. Keep neutral source definitions in `sources/` (abstract specs and system prompts without runtime-specific tool names).
2. Render target-specific artifacts into `targets/opencode/`, `targets/copilot-cli/`, `targets/kimi/`, etc.
3. Publish from the rendered target directories.

If you are not ready to restructure, add a `targets/opencode/` directory alongside the existing Copilot-first layout and maintain both until you adopt rendering scripts.

---

## 4. Quick reference: gaps and fallbacks

| Copilot feature | OpenCode support | Fallback |
|-----------------|------------------|----------|
| `applyTo` glob instructions | Not supported | Use `AGENTS.md` + on-demand skills |
| `handoffs` UI buttons | Not supported | Natural language delegation instructions |
| `github/*` built-in tools | Not supported | Add GitHub MCP server or custom tool |
| `memory` tool | Not supported | Rely on session context |
| Hooks (lifecycle events) | Not supported | Formatters, custom tools, plugins, or AGENTS.md rules |
| Plugin bundles | Not supported | Distribute skills, agents, and custom tools separately |
| Background terminal tasks | Not supported | Use `bash` synchronously or run processes externally |

---

## See also

- [OpenCode Agents docs](https://opencode.ai/docs/agents/)
- [OpenCode Rules docs](https://opencode.ai/docs/rules/)
- [OpenCode Skills docs](https://opencode.ai/docs/skills/)
- [OpenCode Commands docs](https://opencode.ai/docs/commands/)
- [OpenCode Custom Tools docs](https://opencode.ai/docs/custom-tools/)
- [OpenCode MCP Servers docs](https://opencode.ai/docs/mcp-servers/)
