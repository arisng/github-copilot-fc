---
category: how-to
---

# How to Debug Hook Payloads

This guide shows you how to diagnose payload field mismatches between VS Code and Copilot CLI hook events — using `RALPH_LOG_PAYLOAD=true` to capture full payloads, reading JSONL log output, and identifying cross-runtime field naming differences.

## When to use this guide

Use this when hook log entries are missing expected fields, when tool arguments or results are not being captured, or when you need to understand what payload data a specific Copilot runtime is actually sending to hook scripts.

## Before you start

- An active Ralph session with hooks deployed (see [Workspace-Level Hook Deployment Model](../../reference/ralph/workspace-level-hook-deployment-model.md))
- `jq` available for parsing JSONL (bash/WSL) or PowerShell for JSON inspection
- Familiarity with which runtime you are debugging (VS Code or Copilot CLI)

**Reference docs to review first:**

- [VS Code vs CLI hook payload field mapping](../../reference/ralph/vscode-vs-cli-hook-payload-field-mapping.md) — canonical field name mapping table
- [Ralph hook log field inventory and gaps](../../reference/ralph/ralph-hook-log-field-inventory-and-gaps.md) — what fields are logged and known gaps
- [Hook Session-State Validation Guard](../../reference/ralph/hook-session-state-validation-guard.md) — why logging may be silently skipped

## Steps

### 1. Enable full payload logging

Set `RALPH_LOG_PAYLOAD=true` in the hooks manifest to capture tool arguments and results. This is configured per-event in `hooks/ralph-tool-logger.hooks.json`:

```json
"preToolUse": [
  {
    "type": "command",
    "bash": "bash hooks/scripts/ralph-tool-logger.sh",
    "powershell": "powershell -NoProfile -File hooks\\scripts\\ralph-tool-logger.ps1",
    "timeoutSec": 5,
    "env": {
      "RALPH_LOG_PAYLOAD": "true"
    }
  }
]
```

By default, `preToolUse` and `postToolUse` already have `RALPH_LOG_PAYLOAD=true` set. The `subagentStart` and `subagentStop` events do not, because subagent payloads typically contain only identity fields.

After editing the manifest, publish the updated hooks:

```powershell
pwsh -NoProfile -File scripts/publish/publish-hooks.ps1 -Force
```

### 2. Trigger hook events

Run a Copilot interaction that invokes the event types you want to debug. For tool events, any tool call (file read, terminal command, search, etc.) generates both `preToolUse` and `postToolUse` events.

### 3. Locate the JSONL log files

Log files are written to the active Ralph session's log directory:

- **Iteration-scoped** (when `metadata.yaml` has a valid `iteration: <N>`):
  `.ralph-sessions/<SESSION_ID>/iterations/<N>/logs/`
- **Session-level fallback** (when iteration metadata is unresolvable):
  `.ralph-sessions/<SESSION_ID>/logs/`

Two log files are produced:

| File | Events |
|------|--------|
| `tool-usage.jsonl` | `preToolUse`, `postToolUse` |
| `subagent-usage.jsonl` | `subagentStart`, `subagentStop` |

See the [log directory resolution reference](../../reference/ralph/ralph-hook-log-directory-resolution.md) for the full resolution algorithm.

### 4. Read and inspect log entries

**Using jq (bash/WSL):**

```bash
# View the last 5 tool-usage entries, pretty-printed
tail -5 .ralph-sessions/<SESSION_ID>/iterations/<N>/logs/tool-usage.jsonl | jq .

# Filter for a specific tool
cat tool-usage.jsonl | jq 'select(.tool == "read_file")'

# Show only entries with tool_args (payload logging was active)
cat tool-usage.jsonl | jq 'select(.tool_args != null)'

# Find entries missing the agent field
cat tool-usage.jsonl | jq 'select(.agent == null)'
```

**Using PowerShell:**

```powershell
# Read and parse JSONL entries
$entries = Get-Content "tool-usage.jsonl" | ForEach-Object { $_ | ConvertFrom-Json }

# Filter for specific tool
$entries | Where-Object { $_.tool -eq "read_file" }

# Show entries with tool_args
$entries | Where-Object { $null -ne $_.tool_args }
```

### 5. Identify field mapping mismatches

The most common debugging scenario is a field that appears in one runtime but not the other. Use the field mapping table to diagnose:

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `tool_args` is null but tool was called with arguments | VS Code sends `tool_input` (object), CLI sends `toolArgs` (JSON string). Logger may not be checking the right field. | Verify the dual-fallback order in both scripts covers your runtime's field name |
| `agent` is null on tool events | No `subagentStart` event fired before the tool call, so agent attribution has no data | Check `subagent-usage.jsonl` for corresponding start events |
| `result_type` is missing on `postToolUse` | The tool result structure varies — `tool_response` (VS Code) vs `toolResult` (CLI) | Check which result container your runtime uses |
| `ts_iso` is null | Timestamp conversion failed — Bash requires a working `python3` for epoch-to-ISO conversion | See the [python3 bash pitfall reference](../../reference/ralph/windows-app-alias-python3-bash-pitfall.md) |
| No log entries at all | Session-state validation guard rejected the session (COMPLETE state or missing `.active-session`) | Check `metadata.yaml` state field and `.active-session` file existence |

### 6. Compare payloads across runtimes

To compare what VS Code vs CLI actually sends for the same event type:

1. Run the same tool operation in both runtimes with `RALPH_LOG_PAYLOAD=true`
2. Extract the raw `tool_args` and `tool_result` from each JSONL file
3. Compare the field names and value types:

```bash
# Extract tool_args structure from VS Code session
jq '.tool_args | keys' tool-usage.jsonl

# Compare with CLI session
jq '.tool_args | keys' tool-usage-cli.jsonl
```

Key structural differences to watch for:

- **`tool_input` (VS Code)** is a parsed JSON object — arrives pre-structured
- **`toolArgs` (CLI)** is a JSON string — must be parsed via `fromjson?` (jq) or `ConvertFrom-JsonSafe` (PowerShell)
- **`agent_type`** is only present in VS Code payloads — CLI does not send it

See the [payload field mapping reference](../../reference/ralph/vscode-vs-cli-hook-payload-field-mapping.md) for the complete cross-runtime field table.

### 7. Inspect raw hook input (advanced)

If the JSONL logs don't contain enough information, temporarily add raw payload dumping to the logger scripts:

**Bash** — add at the top of the script, after `INPUT=$(cat)`:

```bash
# DEBUG: dump raw hook input to a file
echo "$INPUT" >> "/tmp/ralph-hook-debug-$(date +%s).json"
```

**PowerShell** — add after `$inputJson = [Console]::In.ReadToEnd()`:

```powershell
# DEBUG: dump raw hook input to a file
$inputJson | Set-Content "$env:TEMP\ralph-hook-debug-$(Get-Date -Format 'yyyyMMddHHmmss').json"
```

> **Remember** to remove debug lines before committing — they write sensitive payload data to temp files.

## Troubleshooting

**Problem: Log file does not exist**
The session-state validation guard may be rejecting the session silently. Check:
1. `.ralph-sessions/.active-session` exists and contains a valid session ID
2. The session directory `.ralph-sessions/<SESSION_ID>/` exists
3. `metadata.yaml` does not show `state: COMPLETE`

See the [Hook Session-State Validation Guard reference](../../reference/ralph/hook-session-state-validation-guard.md).

**Problem: Bash logger produces no tool-usage entries**
The Bash logger's jq conditional merging pipeline can silently drop entries if a `--arg` variable receives an unexpected value. Check the [jq empty-propagation reference](../../reference/ralph/jq-empty-propagation-in-ralph-hook-logger.md) for known edge cases.

**Problem: PowerShell logger crashes on malformed input**
The PowerShell logger uses `$ErrorActionPreference = 'Stop'` — any parsing error terminates the script. Check the hook's stderr output for the specific error. The outer `try/catch` at the bottom of the script should catch these and still emit `{"continue":true}`.

## See also

- [How to Add a New Hook Event Type](how-to-add-hook-event-type.md)
- [How to Publish Hooks](how-to-publish-hooks.md)
- [How to Test Hook Scripts Locally](how-to-test-hook-scripts-locally.md)
