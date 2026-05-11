# How to Port GitHub Copilot CLI Customizations to Pi

This guide maps the GitHub Copilot CLI customization model to Pi so you can port agents, instructions, prompts, skills, hooks, and plugins on demand. It targets the CLI runtime only.

## What you need

- Pi installed (`pi --version`)
- A GitHub Copilot CLI customization artifact from this repository
- The mapping rules below

---

## 1. Decide what the artifact is

Use the decision tree to select the correct Pi target format.

```
Is it a SKILL.md?
└── YES → Copy directly to .pi/skills/<name>/ or ~/.pi/agent/skills/<name>/. Done.

Is it a Copilot Prompt (*.prompt.md)?
└── YES → Create a Pi prompt template (.pi/prompts/<name>.md).
          Name it clearly. Invoke via /name in the TUI.

Is it a Copilot Instruction (*.instructions.md)?
└── YES → Check applyTo scope:
           ├── applyTo: '**' or very broad → AGENTS.md or SYSTEM.md
           ├── Agent-coupled              → Port as a prompt template or skill
           └── Narrow / file-type-specific → Create a Pi skill, invoke on demand

Is it a Copilot Agent (*.agent.md)?
└── YES → Pi has no native agent primitive. Choose a fallback:
           ├── Simple, reusable behavior  → Prompt template (.pi/prompts/)
           ├── Complex, on-demand logic   → Skill (.pi/skills/)
           ├── Always-on system behavior  → Extension intercepting before_agent_start
           └── Read-only variant          → Tool allowlist (--tools read,grep,find,ls)

Is it a Copilot Hook (*.hooks.json)?
└── YES → Pi has no native hooks system.
           Fallback: implement as an Extension subscribing to tool_call events.

Is it a Copilot Plugin (plugin.json bundle)?
└── YES → Decompose:
           ├── Skills  → Copy to .pi/skills/
           ├── Prompts → Copy to .pi/prompts/
           ├── Agents  → Port as prompt templates, skills, or extensions
           └── Executable tools/commands → Port as extensions (.pi/extensions/*.ts)
```

---

## 2. Map primitives

### 2.1 Skills (1:1 native)

Pi implements the same open Agent Skills standard as Claude and Kimi.

| Source | Target |
|--------|--------|
| `skills/<name>/SKILL.md` | `.pi/skills/<name>/SKILL.md` or `~/.pi/agent/skills/<name>/SKILL.md` |

Copy the folder verbatim. Pi also discovers skills from `.agents/skills/` and supports cross-loading from `~/.claude/skills/` or `~/.codex/skills/` via the `skills` array in `settings.json`.

### 2.2 Prompts → Prompt templates

Copilot prompts are reusable user-facing prompt templates. Pi has a native **prompt template** system that is a direct equivalent.

1. Create `.pi/prompts/<prompt-name>.md`.
2. Copy the prompt body into the markdown content.
3. Optionally add `description` and `argument-hint` to the YAML frontmatter.

Example:

```markdown
---
description: Generate a changelog from git history
argument-hint: "[from-date] [to-date]"
---

Determine the date range from the user's request, then run the appropriate git log command and summarize the results into a markdown changelog.
```

Usage in TUI: `/changelog last Monday today`

#### Template argument syntax

- `$1`, `$2`, ... — positional arguments
- `$@` or `$ARGUMENTS` — all arguments joined
- `${@:N}` — args from the Nth position (1-indexed)
- `${@:N:L}` — `L` args starting at N

### 2.3 Instructions → Context files

Copilot instructions support `applyTo` glob patterns. Pi does not have file-conditional instruction loading. You must decompose an instruction into one of Pi's context layers.

#### Layer A: Workspace context (`AGENTS.md` / `CLAUDE.md`)
- **When to use**: Broad, always-on project conventions (equivalent to `applyTo: '**'`).
- **Where**: `AGENTS.md` or `CLAUDE.md` in the project root (or parent directories, walking up to the git root), plus `~/.pi/agent/AGENTS.md` globally.
- **Behavior**: Automatically included in the LLM context for every session in that workspace.

#### Layer B: System prompt override (`SYSTEM.md` / `APPEND_SYSTEM.md`)
- **When to use**: When you need to fully replace or append to the default system prompt.
- **Where**: `.pi/SYSTEM.md` or `~/.pi/agent/SYSTEM.md` to replace; `APPEND_SYSTEM.md` in the same locations to append.
- **Behavior**: Replaces or extends the system prompt that Pi sends to the model.

#### Layer C: On-demand context (`skill` tool)
- **When to use**: Narrow or file-type-specific rules (e.g., `applyTo: '**/*.py'`).
- **Where**: A skill under `.pi/skills/<name>/SKILL.md`.
- **Behavior**: Injected only when the agent invokes the `skill` tool or the user runs `/skill:name`.

### 2.4 Agents → Prompt templates, skills, or extensions

**Pi has no native custom agent primitive.** There are no `.agent.md` files, agent frontmatter schemas, or built-in subagent delegation. Pi intentionally keeps the core small and pushes workflow-specific behavior into extensions, skills, and prompt templates.

When porting a Copilot agent, choose the fallback that best matches the agent's complexity and scope:

| Agent characteristic | Pi fallback |
|----------------------|-------------|
| Simple, reusable prompt | Prompt template (`.pi/prompts/<name>.md`) |
| Complex, multi-step workflow | Skill (`.pi/skills/<name>/SKILL.md`) |
| Always-on system behavior | Extension intercepting `before_agent_start` |
| Read-only exploration | Tool allowlist (`--tools read,grep,find,ls`) |

#### Prompt template fallback

For agents that primarily provide a specialized system prompt:

```markdown
---
description: Reviews code for best practices and potential issues
---

You are a code reviewer. Focus on security, performance, and maintainability. Provide constructive feedback without making direct changes.
```

Usage: `/review @src/components/Button.tsx`

#### Skill fallback

For agents that need helper scripts, references, or complex instructions:

```markdown
---
name: code-reviewer
description: Reviews code for quality and best practices
---

## Review Checklist

- [ ] Input validation vulnerabilities
- [ ] Authentication and authorization flaws
- [ ] Data exposure risks
- [ ] Dependency vulnerabilities
```

Usage: `/skill:code-reviewer @src/components/Button.tsx`

#### Extension fallback

For agents that need deep runtime integration (injecting system prompts, blocking tools, custom UI):

```typescript
// .pi/extensions/my-agent.ts
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent"

export default function (pi: ExtensionAPI) {
  pi.on("before_agent_start", async (event, ctx) => {
    return {
      systemPrompt: event.systemPrompt + "\n\nYou are a PLANNING AGENT. Never write code."
    }
  })
}
```

#### Tool allowlists for read-only agents

Pi supports restricting available tools via the `--tools` CLI flag. This is the closest equivalent to a "plan" or "explore" agent mode.

```bash
pi --tools read,grep,find,ls -p "Review this codebase"
```

### 2.5 Hooks → Extensions

Pi has **no native lifecycle hooks system** comparable to Copilot's `.hooks.json` or Kimi's `[[hooks]]`. However, Pi's **extension event system** is significantly more powerful and can replicate any hook behavior.

The key event for hook-like behavior is `tool_call`:

```typescript
// .pi/extensions/hooks.ts
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent"

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName === "bash" && event.input.command?.includes("rm -rf")) {
      return { block: true, reason: "Dangerous command blocked" }
    }

    if (event.toolName === "write" && event.input.path?.endsWith(".env")) {
      return { block: true, reason: "Direct modification of .env files is not allowed" }
    }
  })
}
```

Other relevant events:

| Event | Use case |
|-------|----------|
| `tool_call` | Block or mutate tools before execution |
| `tool_result` | Modify tool results before they reach the LLM |
| `before_agent_start` | Inject context, modify system prompt |
| `context` | Filter or prune messages before LLM call |
| `session_before_compact` | Customize compaction behavior |
| `input` | Intercept or transform user input |

### 2.6 Plugins → Pi packages or decomposed resources

GitHub Copilot plugins are bundles (agents + skills + hooks). Pi **packages** bundle extensions, skills, prompt templates, and themes. They are distributed via npm or git and installed with `pi install`.

When porting a Copilot plugin:

1. **Skills** → Copy to `.pi/skills/`.
2. **Prompts** → Copy to `.pi/prompts/`.
3. **Agents** → Port as prompt templates, skills, or extensions.
4. **Executable tools/commands** → Port as extensions (TypeScript/JavaScript in `.pi/extensions/*.ts`).
5. **Hooks** → Port as extensions subscribing to relevant events.

#### Creating a Pi package

To bundle ported components for distribution:

```json
{
  "name": "my-ported-bundle",
  "keywords": ["pi-package"],
  "pi": {
    "extensions": ["./extensions"],
    "skills": ["./skills"],
    "prompts": ["./prompts"]
  }
}
```

Install: `pi install /path/to/package`

---

## 3. Multi-target factory maintenance

To keep this repository a source factory for multiple coding agents (Copilot, Pi, Kimi, OpenCode, Claude, etc.), use a **source + renderer** pattern:

1. Keep neutral source definitions in `sources/` (abstract specs and system prompts without runtime-specific tool names).
2. Render target-specific artifacts into `targets/pi/`, `targets/copilot-cli/`, `targets/kimi/`, etc.
3. Publish from the rendered target directories.

If you are not ready to restructure, add a `targets/pi/` directory alongside the existing Copilot-first layout and maintain both until you adopt rendering scripts.

---

## 4. Quick reference: gaps and fallbacks

| Copilot feature | Pi support | Fallback |
|-----------------|------------|----------|
| Custom agents | Not supported | Prompt templates, skills, or extensions |
| `applyTo` glob instructions | Not supported | `AGENTS.md` + on-demand skills |
| `handoffs` UI buttons | Not supported | Natural language delegation instructions |
| `github/*` built-in tools | Not supported | Add via extension or package |
| `web` / `fetchURL` | Not built-in | Add via extension or package |
| `vscode/askQuestions` | Not supported | Extension using `ctx.ui.confirm` / `select` / `input` |
| Hooks (lifecycle events) | Not native | Extensions subscribing to `tool_call`, `before_agent_start`, etc. |
| Subagents / `runSubagent` | Not supported | Prompt templates, skills, or extensions |
| Plugin bundles | No exact equivalent | Pi packages (`pi install`) bundle extensions, skills, and prompts |
| Background terminal tasks | Not supported | Use `bash` synchronously or run processes externally |
| `memory` tool | Not supported | Rely on session context |
| `todowrite` | Not supported | Implement via extension |

---

## See also

- [Pi Prompt Templates docs](https://pi.dev/docs/latest/prompt-templates)
- [Pi Skills docs](https://pi.dev/docs/latest/skills)
- [Pi Extensions docs](https://pi.dev/docs/latest/extensions)
- [Pi Packages docs](https://pi.dev/docs/latest/packages)
- [Pi Settings docs](https://pi.dev/docs/latest/settings)
- [Pi Usage docs](https://pi.dev/docs/latest/usage)
