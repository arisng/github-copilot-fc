# Agent Hooks

Agent hooks are GitHub Copilot lifecycle hooks that execute custom shell commands at key points during agent sessions. Use hooks to automate workflows, enforce security policies, validate operations, and integrate with external tools.

## References (Official Documentation)

Periodically check official documentation for updates on hook capabilities and best practices:

- [About hooks](https://docs.github.com/en/copilot/concepts/agents/coding-agent/about-hooks)
- [Using hooks with GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-hooks)
- [Hooks configuration](https://docs.github.com/en/copilot/reference/hooks-configuration)

## Hook File Format

Each hook manifest is a JSON file containing a `hooks` object with arrays of hook commands keyed by event type.

**Naming convention:** `hooks/<name>/<name>.json` (matches Copilot CLI discovery of `*.json` in hook directories)

Prefer the Copilot CLI schema for new hooks: lowerCamelCase event keys (`preToolUse`, `subagentStop`, ...), `bash`/`powershell` command properties, and `timeoutSec`.

**Authoring layout:**

```text
hooks/
└── <name>/
    ├── <name>.json
    └── scripts/
        ├── <script>.ps1
        └── <script>.sh
```

### Minimal Example

```json
{
  "version": 1,
  "hooks": {
    "postToolUse": [
      {
        "type": "command",
        "bash": "bash hooks/security-policy/scripts/format.sh",
        "powershell": "powershell -NoProfile -File hooks\\security-policy\\scripts\\format.ps1",
        "timeoutSec": 5
      }
    ]
  }
}
```

## Hook Lifecycle Events

| Event              | When it fires                                  |
| ------------------ | ---------------------------------------------- |
| `sessionStart` / `SessionStart`         | User submits the first prompt of a new session |
| `userPromptSubmitted` / `UserPromptSubmit` | User submits a prompt                       |
| `preToolUse` / `PreToolUse`             | Before agent invokes any tool                  |
| `postToolUse` / `PostToolUse`           | After tool completes, including failures       |
| `preCompact` / `PreCompact`             | Before conversation context is compacted       |
| `subagentStart` / `SubagentStart`       | Subagent is spawned                            |
| `subagentStop` / `SubagentStop`         | Subagent completes                             |
| `agentStop` / `Stop`                    | Agent session ends                             |

## Hook Command Properties

| Property  | Type   | Description                               |
| --------- | ------ | ----------------------------------------- |
| `type`    | string | Must be `"command"`                       |
| `bash`    | string | POSIX shell command                       |
| `powershell` | string | PowerShell command                    |
| `cwd`     | string | Working directory (relative to repo root) |
| `env`     | object | Additional environment variables          |
| `timeoutSec` | number | Timeout in seconds                    |

## Hook I/O

Hook scripts receive JSON via stdin and emit JSON via stdout.

### Common Fields

`timestamp`, `cwd`, `sessionId`, `hookEventName`, `transcript_path`

### Tool Hook Fields (`preToolUse` / `postToolUse`)

| Field | CLI (camelCase) | Notes |
|-------|-----------------|-------|
| Tool name | `toolName` | |
| Tool arguments | `toolArgs` (JSON string) | serialized JSON string |
| Tool result | `toolResult` | |

### Subagent Hook Fields (`subagentStart` / `subagentStop`)

Agent name arrives as `agentName`.

### Output

- JSON via stdout: `continue`, `stopReason`, `systemMessage`, plus event-specific `hookSpecificOutput`.
- **Exit codes**: `0` = success, `2` = blocking error, other = non-blocking warning.

**CLI payload example** (camelCase, `toolArgs` is a JSON string):

```json
{
  "hookEventName": "postToolUse",
  "toolName": "readFile",
  "toolArgs": "{\"path\":\"src/index.ts\",\"startLine\":1,\"endLine\":50}",
  "toolResult": { "resultType": "text", "textResultForLlm": "..." },
  "agentName": "Executor-CLI",
  "timestamp": 1741588800000,
  "cwd": "/workspace"
}
```

## Deployment Locations

`hooks/<name>/` is the **authored source** location. Deploy by copying a hook folder where the runtime discovers it:

| Location | Scope | Discovery |
| --- | --- | --- |
| `.github/hooks/<name>/` | Workspace (shared) | Discovered automatically from the repository |
| `~/.copilot/hooks/<name>/` | User (global) | Discovered automatically at startup |

## Deployment

There is no publish script — deployment is an explicit copy (the repository is the distribution source):

```powershell
# Workspace-level deployment (committed, shared via the repository)
Copy-Item -Recurse hooks/<name> .github/hooks/<name>

# User-level deployment
Copy-Item -Recurse hooks/<name> "$HOME\.copilot\hooks\<name>"
```

Hook commands are written repo-root-relative (`hooks\<name>\scripts\...`). When deploying, keep the same relative layout or update the `bash`/`powershell` command paths in the copied JSON to match the destination.

## Authoring Guidelines

1. Author each hook in its own `hooks/<name>/` directory (not directly in `.github/hooks/`).
2. Use the `*.json` naming convention (matches Copilot CLI discovery of `*.json` in hook directories).
3. Provide `windows` overrides alongside the default `command` for cross-platform compatibility.
4. Keep hook scripts under the owning hook's `scripts/` folder (for example, `hooks/security-policy/scripts/`) or, for skill-owned hooks, under the skill folder (for example, `skills/<skill>/hooks/<name>/scripts/`).
5. Always validate and sanitize stdin input in hook scripts to prevent injection.
6. Never hardcode secrets — use environment variables or credential stores.

## Security

- Hooks execute with your user privileges. Review all hook scripts before enabling.
- Restrict write access to hook folders so the agent cannot silently edit them.
- Check `stop_hook_active` in `Stop`/`SubagentStop` hooks to prevent infinite loops.
