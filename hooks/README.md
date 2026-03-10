# Agent Hooks

Agent hooks are VS Code Copilot lifecycle hooks that execute custom shell commands at key points during agent sessions. Use hooks to automate workflows, enforce security policies, validate operations, and integrate with external tools.

## References (Official Documentation)

Periodically check official documentation for updates on hook capabilities and best practices:

- [About hooks](https://docs.github.com/en/copilot/concepts/agents/coding-agent/about-hooks)
- [Using hooks with GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-hooks)
- [Hooks configuration](https://docs.github.com/en/copilot/reference/hooks-configuration)
- [Agent hooks in Visual Studio Code (Preview)](https://code.visualstudio.com/docs/copilot/customization/hooks)

For shared hook files that must work in both VS Code and Copilot CLI, prefer the CLI-style schema:

- lowerCamelCase event keys such as `preToolUse` and `subagentStop`
- `bash` and `powershell` command properties
- `timeoutSec` instead of VS Code-only `timeout`

The VS Code hooks documentation explicitly states that VS Code can parse Copilot CLI hook configurations and map the lowerCamelCase event names plus `bash` and `powershell` properties into the VS Code runtime shape.

## Hook File Format

Each hook is a JSON file containing a `hooks` object with arrays of hook commands keyed by event type.

**Naming convention:** `hooks/<name>.hooks.json`

### Minimal Example

```json
{
  "version": 1,
  "hooks": {
    "PostToolUse": [
      {
        "type": "command",
        "command": "./scripts/format.sh",
        "windows": "powershell -File scripts\\format.ps1"
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
| `bash`    | string | POSIX shell command in the CLI schema     |
| `powershell` | string | PowerShell command in the CLI schema   |
| `command` | string | VS Code preview cross-platform command    |
| `windows` | string | VS Code preview Windows override          |
| `linux`   | string | VS Code preview Linux override            |
| `osx`     | string | VS Code preview macOS override            |
| `cwd`     | string | Working directory (relative to repo root) |
| `env`     | object | Additional environment variables          |
| `timeoutSec` | number | Cross-runtime timeout in seconds       |
| `timeout` | number | VS Code preview timeout in seconds        |

## Hook I/O

Hook scripts receive JSON via stdin and emit JSON via stdout. The payload schema differs between VS Code and CLI runtimes.

### Common Fields (Both Runtimes)

`timestamp`, `cwd`, `sessionId`, `hookEventName`, `transcript_path`

### Tool Hook Fields (`preToolUse` / `postToolUse`)

| Field | VS Code (snake_case) | CLI (camelCase) | Notes |
|-------|---------------------|-----------------|-------|
| Tool name | `tool_name` | `toolName` | |
| Tool arguments | `tool_input` (parsed object) | `toolArgs` (JSON string) | VS Code sends a native object; CLI sends a serialized JSON string |
| Tool result | `tool_response` | `toolResult` | |

### Subagent Hook Fields (`subagentStart` / `subagentStop`)

| Field | VS Code (snake_case) | CLI (camelCase) |
|-------|---------------------|------------------|
| Agent name | `agent_id` | `agentName` |
| Agent type | `agent_type` | *(not present)* |

### Output

- JSON via stdout: `continue`, `stopReason`, `systemMessage`, plus event-specific `hookSpecificOutput`.
- **Exit codes**: `0` = success, `2` = blocking error, other = non-blocking warning.

### Cross-Runtime Compatibility

The Ralph logger scripts use dual-field fallback to consume both schemas. For tool arguments, VS Code `tool_input` (object) is returned directly while CLI `toolArgs` (string) is parsed to an object — both normalize to the same internal representation.

**VS Code payload example** (snake_case, `tool_input` is an object):
```json
{
  "hookEventName": "postToolUse",
  "tool_name": "readFile",
  "tool_input": { "path": "src/index.ts", "startLine": 1, "endLine": 50 },
  "tool_response": { "resultType": "text", "textResultForLlm": "..." },
  "agent_id": "Executor-VSCode",
  "agent_type": "participant",
  "timestamp": 1741588800000,
  "cwd": "/workspace"
}
```

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

## Ralph Hook Logs

The Ralph hook logger writes into the active session log directory:

- `tool-usage.jsonl` for `preToolUse` and `postToolUse`
- `subagent-usage.jsonl` for `subagentStart` and `subagentStop`

The logger also keys agent attribution by `transcript_path` instead of a single global active-agent file so tool usage can still be attributed correctly when multiple subagents are active.

## Deployment Locations

`.github/hooks/` is the **primary default** deployment target. VS Code discovers hook files in this workspace directory automatically. User-level deployment to `~/.copilot/hooks/` is **opt-in** and requires both the `-UserLevel` publish switch and the `chat.hookFilesLocations` VS Code setting — it is **not** a default VS Code search path.

| Location | Scope | Discovery |
| --- | --- | --- |
| `.github/hooks/*.json` | Workspace (shared) | **Default** — VS Code searches automatically |
| `~/.copilot/hooks/*.json` | User (global) | **Opt-in** — requires `chat.hookFilesLocations` setting and `-UserLevel` publish |

## Publishing

The publish script copies hook files from `hooks/` to `.github/hooks/` for workspace deployment (default). User-level publishing to `~/.copilot/hooks/` is available via the `-UserLevel` switch:

```powershell
# Publish all hooks (workspace-level only, default)
pwsh -NoProfile -File scripts/publish/publish-hooks.ps1

# Publish with user-level deployment (requires chat.hookFilesLocations setting)
pwsh -NoProfile -File scripts/publish/publish-hooks.ps1 -UserLevel

# Publish specific hooks
pwsh -NoProfile -File scripts/publish/publish-hooks.ps1 -Hooks "security-policy"

# Via the artifact router
pwsh -NoProfile -File scripts/publish/publish-artifact.ps1 -Type hook -Name "security-policy"
```

## Authoring Guidelines

1. Author hook configs in `hooks/` (not directly in `.github/hooks/`).
2. Use the `*.hooks.json` naming convention for clarity.
3. Provide `windows` overrides alongside the default `command` for cross-platform compatibility.
4. Keep hook scripts under `hooks/scripts/` or the relevant skill's `scripts/` folder.
5. Always validate and sanitize stdin input in hook scripts to prevent injection.
6. Never hardcode secrets — use environment variables or credential stores.

## Security

- Hooks execute with VS Code's permissions. Review all hook scripts before enabling.
- Use `chat.tools.edits.autoApprove` to prevent the agent from editing hook scripts without approval.
- Check `stop_hook_active` in `Stop`/`SubagentStop` hooks to prevent infinite loops.

