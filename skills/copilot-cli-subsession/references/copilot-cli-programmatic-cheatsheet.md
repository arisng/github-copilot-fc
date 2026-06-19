# Copilot CLI Programmatic Invocation — Quick Reference

## Core command

```bash
copilot -p "PROMPT" --session-id "UUID" --agent "AGENT" --model "MODEL" -s
```

## Flags relevant to sub-session spawning

| Flag | Purpose |
|------|---------|
| `-p, --prompt` | Non-interactive prompt. |
| `-s, --silent` | Suppress status metadata. |
| `--resume UUID` | Start or resume a session by ID. |
| `--session-id UUID` | Alternative session ID flag. |
| `--name NAME` | Named session (v1.0.52+). |
| `--agent NAME` | Load a custom agent. |
| `--model MODEL` | Pin the model. |
| `--reasoning-effort LEVEL` | none, low, medium, high, xhigh, max. |
| `--output-format FORMAT` | `text` or `json` (JSONL). |
| `--stream MODE` | `on` or `off`. |
| `--config-dir DIR` | Isolated config directory. |
| `--allow-all` / `--yolo` | Full permissions. |
| `--allow-all-tools` | Allow every tool. |
| `--no-ask-user` | Disable clarification prompts. |
| `--no-custom-instructions` | Skip project instructions. |
| `--disable-builtin-mcps` | Disable built-in MCP servers. |
| `--available-tools LIST` | Restrict tool set. |
| `--excluded-tools LIST` | Exclude tools. |
| `--add-dir DIR` | Add allowed path. |
| `--log-dir DIR` / `--log-level LEVEL` | Logging control. |

## BYOK environment variables

```text
COPILOT_PROVIDER_BASE_URL
COPILOT_PROVIDER_TYPE        # openai (default) | azure | anthropic
COPILOT_MODEL
COPILOT_PROVIDER_API_KEY
COPILOT_PROVIDER_WIRE_API    # completions | responses
COPILOT_PROVIDER_MAX_PROMPT_TOKENS
COPILOT_PROVIDER_MAX_OUTPUT_TOKENS
COPILOT_OFFLINE              # true to avoid GitHub services
```

## Authentication precedence

1. `COPILOT_GITHUB_TOKEN`
2. `GH_TOKEN`
3. `GITHUB_TOKEN`

## Model precedence

1. `--model` command-line option
2. `COPILOT_MODEL` environment variable
3. `model` in settings.json
4. CLI built-in default

## JSONL event types (`--output-format json`)

| Type | When |
|------|------|
| `tool.execution_start` | Tool call begins. |
| `tool.execution_complete` | Tool call finishes. |
| `session.task_complete` | Agent reports completion. |
| `result` | Final event with `exitCode` and `usage`. |
| `error` | Fatal error. |

## Chaining sessions

Use the same UUID value for `--session-id` across calls:

```powershell
$shared = New-Guid

& Invoke-CopilotCliSubSession.ps1 -SessionId $shared -Prompt "Research the bug." -JsonOutput
& Invoke-CopilotCliSubSession.ps1 -SessionId $shared -Prompt "Now write a fix plan." -JsonOutput
```

## Custom agent discovery paths

- `~/.copilot/agents/`
- `.github/agents/`
- Installed plugins (`plugin-name/agent-name`)

## Plugin agent qualification

```bash
copilot --agent my-plugin/my-sub-agent -p "Execute task"
```

## Tool permission examples

```bash
--allow-tool shell(git:*)              # allow all git subcommands
--allow-tool write(README.md)          # allow writing README.md
--allow-tool url(github.com)           # allow calls to github.com
--available-tools "read, edit, grep"   # restrict to named tools
```
