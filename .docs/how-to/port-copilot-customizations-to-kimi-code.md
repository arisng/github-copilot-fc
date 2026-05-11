# How to Port GitHub Copilot CLI Customizations to Kimi Code

This guide maps the GitHub Copilot CLI customization model to Kimi Code so you can port agents, instructions, prompts, skills, hooks, and plugins on demand. It is runtime-agnostic except where noted: only CLI targeting is covered here.

## What you need

- Kimi Code CLI installed (`kimi --version`)
- A GitHub Copilot CLI customization artifact from this repository
- The mapping rules below

---

## 1. Decide what the artifact is

Use the decision tree to select the correct Kimi Code target format.

```
Is it a SKILL.md?
└── YES → Copy directly to ~/.kimi/skills/<name>/. Done.

Is it a Copilot Prompt (*.prompt.md)?
└── YES → Create a Kimi skill (SKILL.md) with the prompt body.
          Name it clearly. Invoke via /skill:<name>.

Is it a Copilot Instruction (*.instructions.md)?
└── YES → Check applyTo scope:
           ├── applyTo: '**' or very broad → ~/.kimi/AGENTS.md or .kimi/AGENTS.md
           ├── Agent-coupled              → Embed in agent's system_prompt_path markdown
           └── Narrow / file-type-specific → Create a Kimi skill, invoke on demand

Is it a Copilot Agent (*.agent.md)?
└── YES → Create agent YAML + system markdown.
          Translate all tool names.
          Convert runSubagent calls to Agent tool with subagent_type.
          Map handoffs to subagents definitions in YAML.

Is it a Copilot Hook (*.hooks.json)?
└── YES → Convert to [[hooks]] entries in ~/.kimi/config.toml.
          Unify bash/ps1 dispatch if needed.

Is it a Copilot Plugin (plugin.json bundle)?
└── YES → Decompose:
           ├── Skills → Copy to ~/.kimi/skills/
           ├── Agents → Port as custom agent YAMLs
           └── Executable tools → Port as Kimi plugins (plugin.json tools)
```

---

## 2. Map primitives

### 2.1 Skills (1:1 native)

Kimi Code uses the same open Agent Skills format.

| Source | Target |
|--------|--------|
| `skills/<name>/SKILL.md` | `~/.kimi/skills/<name>/SKILL.md` |

Copy the folder verbatim. Kimi auto-discovers it on the next run.

### 2.2 Prompts → Skills

Copilot prompts are reusable user-facing prompt templates. In Kimi, turn each prompt into a skill so it can be invoked with `/skill:<name>`.

1. Create `~/.kimi/skills/<prompt-name>/SKILL.md`.
2. Copy the prompt body into the skill markdown.
3. Add YAML frontmatter with `name` and `description`.

Example:

```markdown
---
name: changelog
description: Generate a changelog from git history for a date range
---

## Changelog Workflow

1. Determine the date range from the user's request.
2. Run `git log --pretty=format:"..."` for that range.
3. Summarize into a markdown changelog.
```

Usage: `/skill:changelog from last Monday to today`

### 2.3 Instructions → Context layers

Copilot instructions support `applyTo` glob patterns, which Kimi does not. You must decompose an instruction into one of three Kimi context layers.

#### Layer A: Workspace context (`AGENTS.md`)
- **When to use**: Broad, always-on project conventions (equivalent to `applyTo: '**'`).
- **Where**: `.kimi/AGENTS.md` (project-level) or `~/.kimi/AGENTS.md` (user-level).
- **Behavior**: Content is injected into the `${KIMI_AGENTS_MD}` variable in every system prompt for that workspace.

#### Layer B: Agent context (`system_prompt_path`)
- **When to use**: Domain-specific behavior tied to a specific custom agent.
- **Where**: A markdown file referenced by the agent YAML (`system_prompt_path: ./system.md`).
- **Behavior**: Loaded as the agent's system prompt template. Supports Jinja2 `{% include %}` and `${VAR}` substitution.

#### Layer C: On-demand context (`/skill:<name>`)
- **When to use**: Narrow or file-type-specific rules (e.g., `applyTo: '**/*.py'`).
- **Where**: A skill under `~/.kimi/skills/<name>/SKILL.md`.
- **Behavior**: Injected only when the user or agent invokes `/skill:<name>`.

### 2.4 Agents → Custom agent YAML + system markdown

A Copilot agent is a single markdown file with YAML frontmatter. A Kimi agent is a YAML file plus a separate system prompt markdown file.

#### File structure

```
my-agent/
├── agent.yaml
└── system.md
```

#### `agent.yaml` example

```yaml
version: 1
agent:
  name: planner
  system_prompt_path: ./system.md
  tools:
    - "kimi_cli.tools.ask_user:AskUserQuestion"
    - "kimi_cli.tools.shell:Shell"
    - "kimi_cli.tools.file:ReadFile"
    - "kimi_cli.tools.file:Glob"
    - "kimi_cli.tools.file:Grep"
    - "kimi_cli.tools.agent:Agent"
    - "kimi_cli.tools.web:SearchWeb"
    - "kimi_cli.tools.web:FetchURL"
  subagents:
    explore:
      path: ./explore-sub.yaml
      description: "Fast read-only codebase exploration"
```

#### `system.md` example

```markdown
# Planner

You are a PLANNING AGENT.

Your job: research the codebase → clarify with the user → produce a comprehensive plan. NEVER start implementation.

## Rules

- STOP if you consider running file editing tools.
- Use AskUserQuestion freely to clarify requirements.
- Present a well-researched plan before any implementation begins.
```

Usage: `kimi --agent-file ./my-agent/agent.yaml`

#### Tool name remapping

Every Copilot tool name must be translated to a Kimi fully-qualified tool path.

| Copilot tool | Kimi tool path |
|--------------|----------------|
| `read` / `readFile` | `kimi_cli.tools.file:ReadFile` |
| `search` / `searchCodebase` | `kimi_cli.tools.file:Grep` (use with `Glob` for broader search) |
| `web` | `kimi_cli.tools.web:SearchWeb` |
| `fetchURL` | `kimi_cli.tools.web:FetchURL` |
| `agent` / `runSubagent` | `kimi_cli.tools.agent:Agent` |
| `execute/runInTerminal` | `kimi_cli.tools.shell:Shell` |
| `execute/getTerminalOutput` | `kimi_cli.tools.background:TaskOutput` |
| `execute/awaitTerminal` | `kimi_cli.tools.background:TaskOutput` with `block=true` |
| `execute/killTerminal` | `kimi_cli.tools.background:TaskStop` |
| `vscode/askQuestions` | `kimi_cli.tools.ask_user:AskUserQuestion` |
| `write` / `createFile` / `editFiles` | `kimi_cli.tools.file:WriteFile`, `kimi_cli.tools.file:StrReplaceFile` |
| `github/*` | None native — add an MCP server or write a Kimi plugin |
| `memory` | None exact — rely on session context or external state |

#### Subagents

Copilot uses `#tool:agent/runSubagent` with arbitrary agent files. Kimi supports:

1. **Built-in subagent types**: `coder`, `explore`, `plan`
2. **Custom subagents**: Defined in `agent.yaml` under `subagents:`

For multi-agent systems (e.g., Ralph-v2), define each subagent as a separate YAML file and reference it from the orchestrator agent.

```yaml
subagents:
  planner:
    path: ./planner-sub.yaml
    description: "Creates implementation plans"
  executor:
    path: ./executor-sub.yaml
    description: "Executes a single task brief"
```

The orchestrator's system prompt must instruct it to call the `Agent` tool with the matching `subagent_type` name.

#### Handoffs

Copilot agents can declare `handoffs:` (UI buttons). Kimi has no handoff UI primitive. Replace handoffs with natural language instructions in the system prompt that tell the agent when to delegate to a subagent or return results to the user.

### 2.5 Hooks → `[[hooks]]` in `~/.kimi/config.toml`

Kimi hooks are TOML array entries, not JSON manifests. Each hook receives JSON via stdin and controls flow via exit code.

#### Mapping example

**Copilot hook manifest** (`logger.hooks.json`):

```json
{
  "version": 1,
  "hooks": {
    "preToolUse": [
      {
        "type": "command",
        "bash": "bash scripts/logger.sh",
        "powershell": "powershell -NoProfile -File scripts\\logger.ps1",
        "timeoutSec": 5
      }
    ]
  }
}
```

**Kimi equivalent** in `~/.kimi/config.toml`:

```toml
[[hooks]]
event = "PreToolUse"
matcher = "WriteFile|StrReplaceFile|Shell"
command = "pwsh -NoProfile -File scripts/logger.ps1"
timeout = 5
```

On Linux/macOS, change `command` to `bash scripts/logger.sh` or use a cross-platform wrapper script.

#### Hook behavior reference

| Exit code | Behavior |
|-----------|----------|
| `0` | Allow. stdout is added to context if non-empty. |
| `2` | Block. stderr is fed back to the LLM as a correction. |
| Other | Allow. stderr is logged only. |

### 2.6 Plugins → Decomposed skills, agents, and executable tools

GitHub Copilot plugins are bundles (agents + skills + hooks). Kimi plugins are **executable tool wrappers only** (`plugin.json` that declares commands receiving JSON via stdin).

When porting a Copilot plugin:

1. **Skills** → Copy directly to `~/.kimi/skills/`.
2. **Agents** → Port as custom agent YAMLs and distribute as files.
3. **Executable tools/commands** → Port as Kimi plugins under `~/.kimi/plugins/<name>/`.

There is no Kimi equivalent for a "bundle manifest." You must distribute components separately.

#### Kimi plugin example

```json
{
  "name": "my-tool",
  "version": "1.0.0",
  "description": "Sample tool wrapper",
  "tools": [
    {
      "name": "greet",
      "description": "Generate a greeting",
      "command": ["python3", "scripts/greet.py"],
      "parameters": {
        "type": "object",
        "properties": {
          "name": { "type": "string", "description": "Name to greet" }
        },
        "required": ["name"]
      }
    }
  ]
}
```

Install: `kimi plugin install /path/to/my-tool/`

---

## 3. Multi-target factory maintenance

To keep this repository a source factory for multiple coding agents (Copilot, Kimi, Claude, OpenCode, etc.), use a **source + renderer** pattern:

1. Keep neutral source definitions in `sources/` (abstract specs and system prompts without runtime-specific tool names).
2. Render target-specific artifacts into `targets/kimi/`, `targets/copilot-cli/`, etc.
3. Publish from the rendered target directories.

If you are not ready to restructure, add a `targets/kimi/` directory alongside the existing Copilot-first layout and maintain both until you adopt rendering scripts.

---

## 4. Quick reference: gaps and fallbacks

| Copilot feature | Kimi support | Fallback |
|-----------------|--------------|----------|
| `applyTo` glob instructions | Not supported | Use `.kimi/AGENTS.md` + on-demand skills |
| `handoffs` UI buttons | Not supported | Natural language delegation instructions |
| `github/*` built-in tools | Not supported | Add GitHub MCP server or write a plugin |
| `memory` tool | Not supported | Rely on session context or external files |
| Plugin bundles | Not supported | Distribute skills, agents, and plugins separately |

---

## See also

- [Kimi Code CLI Agents docs](https://moonshotai.github.io/kimi-cli/en/customization/agents.md)
- [Kimi Code CLI Skills docs](https://moonshotai.github.io/kimi-cli/en/customization/skills.md)
- [Kimi Code CLI Plugins docs](https://moonshotai.github.io/kimi-cli/en/customization/plugins.md)
- [Kimi Code CLI Hooks docs](https://moonshotai.github.io/kimi-cli/en/customization/hooks.md)
