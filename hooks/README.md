# Agent Hooks

Agent hooks are VS Code Copilot lifecycle hooks that execute custom shell commands at key points during agent sessions. Use hooks to automate workflows, enforce security policies, validate operations, and integrate with external tools.

## References (Official Documentation)

Periodically check official documentation for updates on hook capabilities and best practices:

- [About hooks](https://docs.github.com/en/copilot/concepts/agents/coding-agent/about-hooks)
- [Using hooks with GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-hooks)
- [Hooks configuration](https://docs.github.com/en/copilot/reference/hooks-configuration)
- [Agent hooks in Visual Studio Code (Preview)](https://code.visualstudio.com/docs/copilot/customization/hooks)

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
| `SessionStart`     | User submits the first prompt of a new session |
| `UserPromptSubmit` | User submits a prompt                          |
| `PreToolUse`       | Before agent invokes any tool                  |
| `PostToolUse`      | After tool completes successfully              |
| `PreCompact`       | Before conversation context is compacted       |
| `SubagentStart`    | Subagent is spawned                            |
| `SubagentStop`     | Subagent completes                             |
| `Stop`             | Agent session ends                             |

## Hook Command Properties

| Property  | Type   | Description                               |
| --------- | ------ | ----------------------------------------- |
| `type`    | string | Must be `"command"`                       |
| `command` | string | Default command to run (cross-platform)   |
| `windows` | string | Windows-specific command override         |
| `linux`   | string | Linux-specific command override           |
| `osx`     | string | macOS-specific command override           |
| `cwd`     | string | Working directory (relative to repo root) |
| `env`     | object | Additional environment variables          |
| `timeout` | number | Timeout in seconds (default: 30)          |

## Hook I/O

- **Input**: JSON via stdin with common fields (`timestamp`, `cwd`, `sessionId`, `hookEventName`, `transcript_path`) plus event-specific fields.
- **Output**: JSON via stdout (`continue`, `stopReason`, `systemMessage`, plus event-specific `hookSpecificOutput`).
- **Exit codes**: `0` = success, `2` = blocking error, other = non-blocking warning.

## Deployment Locations

VS Code searches for hook configuration files in these locations (workspace hooks take precedence):

| Location                      | Scope              |
| ----------------------------- | ------------------ |
| `.github/hooks/*.json`        | Workspace (shared) |
| `.claude/settings.local.json` | Workspace (local)  |
| `.claude/settings.json`       | Workspace          |
| `~/.claude/settings.json`     | User (global)      |

## Publishing

The publish script copies hook files from `hooks/` to `.github/hooks/` for workspace deployment:

```powershell
# Publish all hooks
pwsh -NoProfile -File scripts/publish/publish-hooks.ps1

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

