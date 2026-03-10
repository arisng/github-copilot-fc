---
category: how-to
---

# How to Add a New Hook Event Type

This guide shows you how to extend the Ralph hook loggers with a new event type — adding the handler in both `ralph-tool-logger.sh` and `ralph-tool-logger.ps1`, registering the event in the hooks manifest, and publishing the updated hooks.

## When to use this guide

Use this when you need to capture a new Copilot hook event (beyond the current `preToolUse`, `postToolUse`, `subagentStart`, `subagentStop`) in the Ralph session telemetry pipeline.

## Before you start

- Familiarity with the hook payload structure for your target event
- Access to the workspace at the repository root
- PowerShell available for publishing (`pwsh`)

**Reference docs to review first:**

- [Ralph hook log field inventory and gaps](../../reference/ralph/ralph-hook-log-field-inventory-and-gaps.md) — existing field schema
- [VS Code vs CLI hook payload field mapping](../../reference/ralph/vscode-vs-cli-hook-payload-field-mapping.md) — cross-runtime field naming
- [Ralph hook manifest cross-runtime status](../../reference/ralph/ralph-hook-manifest-cross-runtime-status.md) — manifest compatibility rules
- [Workspace-Level Hook Deployment Model](../../reference/ralph/workspace-level-hook-deployment-model.md) — deployment layout

## Steps

### 1. Identify the event name and payload fields

Determine the lowerCamelCase event name (e.g., `preToolUse`) and the payload fields your handler needs. Both VS Code and CLI may use different field names for the same concept — VS Code tends to use `snake_case`, CLI uses `camelCase`. Plan your dual-fallback field lookups accordingly.

> **Convention**: Always check the VS Code `snake_case` field first, then fall back to the CLI `camelCase` variant. See the [payload field mapping reference](../../reference/ralph/vscode-vs-cli-hook-payload-field-mapping.md) for the established pattern.

### 2. Add the handler to the Bash logger

Open `hooks/scripts/ralph-tool-logger.sh` and add a new `case` branch in the main event dispatch (the `case "$EVENT_NAME" in` block near the end of the file).

```bash
    yourNewEvent)
        # Extract fields with dual-fallback (snake_case first, camelCase second)
        YOUR_FIELD=$(echo "$INPUT" | jq -r '.your_field // .yourField // empty')

        # Build the JSONL entry using jq conditional object merging
        jq -cn \
            --arg ts "$TIMESTAMP" \
            --arg ts_iso "$TS_ISO" \
            --arg sid "$SESSION_ID" \
            --arg ev "$EVENT_NAME" \
            --arg cwd "$CWD" \
            --arg yf "$YOUR_FIELD" \
            '{ts:$ts,sid:$sid,event:$ev,cwd:$cwd}
            + (if $ts_iso != "null" then {ts_iso:$ts_iso} else {} end)
            + (if $yf != "" then {your_field:$yf} else {} end)' >> "$YOUR_LOG_FILE"
        ;;
```

Key patterns to follow:

- Use `jq -r '... // empty'` for field extraction with fallback
- Use `jq -cn` with conditional merging (`+ (if ... then ... else {} end)`) for JSONL assembly — see the [jq conditional object merging reference](../../reference/ralph/jq-conditional-object-merging-pattern.md)
- Append to the appropriate log file (`$TOOL_LOG_FILE` for tool events, `$SUBAGENT_LOG_FILE` for agent events, or define a new log file variable)

### 3. Add the handler to the PowerShell logger

Open `hooks/scripts/ralph-tool-logger.ps1` and add a new branch in the `switch ($normalizedEventName)` block.

```powershell
        'yourNewEvent' {
            $entry = New-LogEntry -Event $event -SessionId $sessionId `
                -NormalizedEventName $normalizedEventName `
                -Timestamp $timestamp -TranscriptPath $transcriptPath

            # Extract fields using Get-HookProperty with dual-fallback
            $yourField = [string](Get-HookProperty -Event $event -Names @('your_field', 'yourField'))
            if ($yourField) {
                $entry.your_field = $yourField
            }

            Add-Content -Path $yourLogFile -Value ($entry | ConvertTo-Json -Compress -Depth 10) -Encoding UTF8
        }
```

Key patterns to follow:

- Use `Get-HookProperty -Names @('snake_case', 'camelCase')` for dual-fallback field extraction
- Use `New-LogEntry` to create the base entry with common fields (`ts`, `ts_iso`, `sid`, `event`, `cwd`, `transcript_path`)
- Conditionally add fields only when present (don't write nulls)

### 4. Register the event name normalizer

Both loggers normalize PascalCase and lowerCamelCase variants of event names.

**Bash** — add entries to the `normalize_event_name()` function:

```bash
normalize_event_name() {
    case "$1" in
        # ... existing entries ...
        YourNewEvent|yourNewEvent) printf 'yourNewEvent\n' ;;
        *) printf '%s\n' "$1" ;;
    esac
}
```

**PowerShell** — add entries to `Get-NormalizedEventName`:

```powershell
function Get-NormalizedEventName {
    param([string]$HookEventName)
    switch ($HookEventName) {
        # ... existing entries ...
        'YourNewEvent' { return 'yourNewEvent' }
        'yourNewEvent' { return 'yourNewEvent' }
        default { return $HookEventName }
    }
}
```

### 5. Update the hooks manifest

Open `hooks/ralph-tool-logger.hooks.json` and add your event to the `hooks` object:

```json
{
  "version": 1,
  "hooks": {
    "yourNewEvent": [
      {
        "type": "command",
        "bash": "bash hooks/scripts/ralph-tool-logger.sh",
        "powershell": "powershell -NoProfile -File hooks\\scripts\\ralph-tool-logger.ps1",
        "timeoutSec": 5
      }
    ]
  }
}
```

To enable payload logging for the event, add the `env` block:

```json
{
  "type": "command",
  "bash": "bash hooks/scripts/ralph-tool-logger.sh",
  "powershell": "powershell -NoProfile -File hooks\\scripts\\ralph-tool-logger.ps1",
  "timeoutSec": 5,
  "env": {
    "RALPH_LOG_PAYLOAD": "true"
  }
}
```

> **Important**: Use lowerCamelCase for the event key (e.g., `yourNewEvent` not `YourNewEvent`). This is the cross-runtime compatible format accepted by both VS Code and Copilot CLI.

### 6. Publish the updated hooks

Run the publish script to deploy the updated manifest to `.github/hooks/`:

```powershell
pwsh -NoProfile -File scripts/publish/publish-hooks.ps1
```

This copies the hooks manifest from `hooks/` to `.github/hooks/` where VS Code auto-discovers it. The logger scripts remain in `hooks/scripts/` and are referenced by workspace-relative paths.

### 7. Verify the new event fires

1. Start a Copilot session that triggers your event type
2. Check the JSONL log file in the active session's log directory:
   - Iteration-scoped: `.ralph-sessions/<SESSION_ID>/iterations/<N>/logs/`
   - Session-level fallback: `.ralph-sessions/<SESSION_ID>/logs/`
3. Confirm the new event entries contain the expected fields

## Troubleshooting

**Problem: Event handler never fires**
Check that the event name in `hooks.json` matches the exact lowerCamelCase name that the Copilot runtime emits. VS Code may use PascalCase internally but the manifest key must be lowerCamelCase.

**Problem: Fields are missing in the log entry**
The VS Code and CLI runtimes may send different field names. Enable `RALPH_LOG_PAYLOAD=true` to log the full payload, then compare against the [payload field mapping reference](../../reference/ralph/vscode-vs-cli-hook-payload-field-mapping.md).

**Problem: Bash handler produces no output**
Check for jq empty-propagation: if any `jq -r '... // empty'` extraction yields no result, downstream `--arg` variables may be empty, causing the conditional merge to silently drop fields. See the [jq empty-propagation reference](../../reference/ralph/jq-empty-propagation-in-ralph-hook-logger.md).

## See also

- [How to Debug Hook Payloads](how-to-debug-hook-payloads.md)
- [How to Publish Hooks](how-to-publish-hooks.md)
- [How to Test Hook Scripts Locally](how-to-test-hook-scripts-locally.md)
