<#
.SYNOPSIS
    Logs tool usage and subagent lifecycle events for Ralph-v2 sessions.

.DESCRIPTION
    Receives hook event JSON via stdin, resolves the active Ralph session,
    and appends a JSONL entry to .ralph-sessions/<SESSION_ID>/logs/tool-usage.jsonl.

    Tracks active subagent via .ralph-sessions/.hook-state/active-agent.txt
    using SubagentStart/SubagentStop events.

    Environment variables:
        RALPH_LOG_PAYLOAD  - Set to "true" to include tool input in log entries.
#>

$ErrorActionPreference = 'Stop'

try {
    $inputJson = [Console]::In.ReadToEnd()
    $event = $inputJson | ConvertFrom-Json

    $sessionRoot = Join-Path $event.cwd '.ralph-sessions'
    $activeSessionFile = Join-Path $sessionRoot '.active-session'

    # No active Ralph session — pass through silently
    if (-not (Test-Path $activeSessionFile)) {
        Write-Output '{"continue":true}'
        exit 0
    }

    $sessionId = (Get-Content $activeSessionFile -Raw).Trim()
    if (-not $sessionId) {
        Write-Output '{"continue":true}'
        exit 0
    }

    $logDir = Join-Path $sessionRoot "$sessionId\logs"
    $logFile = Join-Path $logDir 'tool-usage.jsonl'
    $hookStateDir = Join-Path $sessionRoot '.hook-state'
    $activeAgentFile = Join-Path $hookStateDir 'active-agent.txt'

    # Ensure directories
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    if (-not (Test-Path $hookStateDir)) { New-Item -ItemType Directory -Path $hookStateDir -Force | Out-Null }

    # Read current active agent
    $activeAgent = ''
    if (Test-Path $activeAgentFile) {
        $activeAgent = (Get-Content $activeAgentFile -Raw).Trim()
    }

    # Build log entry
    $entry = [ordered]@{
        ts    = $event.timestamp
        sid   = $sessionId
        event = $event.hookEventName
    }

    switch ($event.hookEventName) {
        'SubagentStart' {
            $agentName = $event.agentName
            if ($agentName) {
                Set-Content -Path $activeAgentFile -Value $agentName -NoNewline -Encoding UTF8
                $entry.agent = $agentName
            }
        }
        'SubagentStop' {
            $entry.agent = $activeAgent
            if (Test-Path $activeAgentFile) {
                Remove-Item $activeAgentFile -Force
            }
        }
        { $_ -in @('PreToolUse', 'PostToolUse') } {
            if ($activeAgent) { $entry.agent = $activeAgent }
            if ($event.toolName) { $entry.tool = $event.toolName }
            if ($env:RALPH_LOG_PAYLOAD -eq 'true' -and $null -ne $event.toolInput) {
                $entry.input = $event.toolInput
            }
        }
    }

    $jsonLine = $entry | ConvertTo-Json -Compress -Depth 5
    Add-Content -Path $logFile -Value $jsonLine -Encoding UTF8
}
catch {
    # Hook failures must not crash the agent session
}

Write-Output '{"continue":true}'
exit 0
