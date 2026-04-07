# [Hooks (.json)](https://docs.github.com/en/copilot/reference/hooks-configuration)

Deterministic lifecycle automation for Copilot CLI. Use hooks to enforce policy, block dangerous tool use, or inject runtime context.

## Locations

| Path | Scope |
|------|-------|
| `.github/hooks/*.json` | Repository, discovered from the current working directory |

In this workspace, authored hook sources live under `hooks/` and publish to `.github/hooks/`, but the runtime discovery path for Copilot CLI is `.github/hooks/`.

## Hook Events

| Event | Trigger |
|-------|---------|
| `sessionStart` | A new CLI session starts |
| `sessionEnd` | The CLI session finishes |
| `userPromptSubmitted` | A user prompt is submitted |
| `preToolUse` | Before a tool runs |
| `postToolUse` | After a tool runs |
| `agentStop` | The main agent stops |
| `subagentStop` | A subagent stops |
| `errorOccurred` | An error is raised during the session |

## Configuration Format

```json
{
  "version": 1,
  "hooks": {
    "preToolUse": [
      {
        "bash": "./scripts/validate-tool.sh",
        "powershell": "./scripts/validate-tool.ps1",
        "cwd": ".",
        "timeoutSec": 15
      }
    ]
  }
}
```

Each hook entry supports:

- `bash`
- `powershell`
- `cwd`
- `env`
- `timeoutSec`

## Input / Output Contract

Hooks receive JSON on stdin. Common CLI payloads include fields such as:

- `toolName`
- `toolArgs`
- `toolResult`

`preToolUse` is the main behavior-changing hook because it can allow, ask, or deny tool execution.

## Hooks vs Other Customizations

| Primitive | Behavior |
|-----------|----------|
| Instructions / Commands / Skills / Agents | Guidance and workflow shaping |
| Hooks | Deterministic enforcement and automation |

Use hooks when the behavior must always happen, not just be recommended.

## Core Principles

1. **Keep hooks fast and auditable**
2. **Use lowercase CLI event names**
3. **Prefer repository hooks for shared policy**
4. **Validate inputs and avoid hardcoded secrets**

## Anti-patterns

- **Using VS Code hook schema**: CLI does not use `command` with `windows` / `linux` / `osx`
- **Using CamelCase event names**: CLI events are lowercase names like `preToolUse`
- **Running long blocking hooks**: They slow normal CLI flow
- **Assuming hooks load outside the current working directory**: Discovery is repo-scoped
