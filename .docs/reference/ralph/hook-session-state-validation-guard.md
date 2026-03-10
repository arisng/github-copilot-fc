---
category: reference
---

# Hook Session-State Validation Guard

## Summary

Both Ralph hook logger scripts (PowerShell and Bash) implement a defensive session-state validation guard that prevents logging to stale or completed sessions. The guard sits between session ID resolution and log directory creation, ensuring no log entries are written to sessions that no longer accept data.

## 4-Step Validation Sequence

1. **`.active-session` file check** — Read the session ID from `.ralph-sessions/.active-session`. If the file is missing or empty, exit early with `{"continue":true}`.
2. **Session ID resolution** — Resolve session ID from the hook event payload first, then fall back to the `.active-session` file content.
3. **Session directory existence** — Verify `.ralph-sessions/<SESSION_ID>/` exists. If missing, emit a stderr warning and exit with `{"continue":true}`.
4. **Metadata state check** — Read `.ralph-sessions/<SESSION_ID>/metadata.yaml` and check if `state: COMPLETE`. If the session is complete, emit a stderr warning and exit with `{"continue":true}`.

## Fail-Open Design

The guard is designed to never block agent operations:

| Failure Scenario | PowerShell | Bash | Outcome |
|------------------|------------|------|---------|
| Missing session directory | `Test-Path` returns `$false` | `[ ! -d "$SESSION_DIR" ]` | Exit with `{"continue":true}` |
| COMPLETE session state | Regex match on metadata content | `grep -qE` on metadata file | Exit with `{"continue":true}` |
| Unreadable `metadata.yaml` | `try/catch` swallows read error | `[ -f ]` guard + `2>/dev/null` | **Logging proceeds** (fail-open) |
| Missing `metadata.yaml` | `try/catch` swallows read error | `[ -f ]` guard skips check | **Logging proceeds** (fail-open) |

## Implementation Patterns

**PowerShell** (`ralph-tool-logger.ps1`):
```powershell
# Session directory existence
if (-not (Test-Path $sessionDir)) {
    Write-Warning "Session directory not found: $sessionDir"
    Write-Output '{"continue":true}'
    exit 0
}
# Metadata state check (fail-open on read error)
try {
    $metaContent = Get-Content "$sessionDir/metadata.yaml" -Raw
    if ($metaContent -match '(?m)^\s*state:\s*COMPLETE\s*$') {
        Write-Warning "Session $sessionId is COMPLETE — skipping log"
        Write-Output '{"continue":true}'
        exit 0
    }
} catch { <# fail-open: proceed if metadata unreadable #> }
```

**Bash** (`ralph-tool-logger.sh`):
```bash
# Session directory existence
if [ ! -d "$SESSION_DIR" ]; then
    echo "Warning: session directory not found: $SESSION_DIR" >&2
    echo '{"continue":true}'; exit 0
fi
# Metadata state check (fail-open on read error)
SESSION_METADATA="$SESSION_DIR/metadata.yaml"
if [ -f "$SESSION_METADATA" ]; then
    if grep -qE '^[[:space:]]*state:[[:space:]]*COMPLETE[[:space:]]*$' "$SESSION_METADATA" 2>/dev/null; then
        echo "Warning: session $SESSION_ID is COMPLETE — skipping" >&2
        echo '{"continue":true}'; exit 0
    fi
fi
```

## Non-Fatal Exit Contract

All validation failure paths exit with code 0 and emit `{"continue":true}` to stdout. This preserves the hook contract: validation failures produce observability warnings (stderr) but never block the agent session.
