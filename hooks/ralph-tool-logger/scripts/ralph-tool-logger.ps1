<#
.SYNOPSIS
    Logs tool usage and subagent lifecycle events for Ralph-v2 sessions.

.DESCRIPTION
    Receives hook event JSON via stdin, resolves the active Ralph session,
    and appends JSONL entries to iteration-scoped logs when metadata is readable.
    Falls back to the session-level log path when iteration metadata cannot be resolved.

    Tracks active subagents by transcript path via
    .ralph-sessions/.hook-state/active-agents.json so tool events can be
    attributed to the correct agent across runtime payload shapes.

    Environment variables:
        RALPH_LOG_PAYLOAD  - Set to "true" to include tool arguments and results.
#>

$ErrorActionPreference = 'Stop'

function Get-HookProperty {
    param(
        [Parameter(Mandatory)]$Event,
        [Parameter(Mandatory)][string[]]$Names
    )

    foreach ($name in $Names) {
        $property = $Event.PSObject.Properties[$name]
        if ($null -ne $property -and $null -ne $property.Value) {
            return $property.Value
        }
    }

    return $null
}

function Get-NormalizedEventName {
    param([string]$HookEventName)

    switch ($HookEventName) {
        'PreToolUse' { return 'preToolUse' }
        'preToolUse' { return 'preToolUse' }
        'PostToolUse' { return 'postToolUse' }
        'postToolUse' { return 'postToolUse' }
        'SubagentStart' { return 'subagentStart' }
        'subagentStart' { return 'subagentStart' }
        'SubagentStop' { return 'subagentStop' }
        'subagentStop' { return 'subagentStop' }
        default { return $HookEventName }
    }
}

function ConvertTo-IsoTimestamp {
    param($Timestamp)

    if ($null -eq $Timestamp) {
        return $null
    }

    try {
        if ($Timestamp -is [ValueType] -or $Timestamp -match '^\d+(\.\d+)?$') {
            $numeric = [double]$Timestamp
            if ($numeric -ge 1000000000000) {
                return [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$numeric).ToString('o')
            }

            if ($numeric -ge 1000000000) {
                return [DateTimeOffset]::FromUnixTimeSeconds([int64]$numeric).ToString('o')
            }
        }

        return ([DateTimeOffset]::Parse($Timestamp.ToString())).ToString('o')
    }
    catch {
        return $null
    }
}

function ConvertFrom-JsonSafe {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -isnot [string]) {
        return $Value
    }

    $trimmed = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return $null
    }

    if ($trimmed.StartsWith('{') -or $trimmed.StartsWith('[')) {
        try {
            return $trimmed | ConvertFrom-Json
        }
        catch {
            return $Value
        }
    }

    return $Value
}

function Get-HookState {
    param([string]$StatePath)

    $defaultState = [ordered]@{
        activeAgents = [ordered]@{}
        lastAgent = $null
    }

    if (-not (Test-Path $StatePath)) {
        return $defaultState
    }

    try {
        $rawState = Get-Content $StatePath -Raw | ConvertFrom-Json
    }
    catch {
        return $defaultState
    }

    $activeAgents = [ordered]@{}
    if ($null -ne $rawState.activeAgents) {
        foreach ($property in $rawState.activeAgents.PSObject.Properties) {
            $activeAgents[$property.Name] = $property.Value
        }
    }

    return [ordered]@{
        activeAgents = $activeAgents
        lastAgent = $rawState.lastAgent
    }
}

function Save-HookState {
    param(
        [Parameter(Mandatory)][string]$StatePath,
        [Parameter(Mandatory)]$State
    )

    $payload = [ordered]@{
        activeAgents = [ordered]@{}
        lastAgent = $State.lastAgent
    }

    foreach ($key in $State.activeAgents.Keys) {
        $payload.activeAgents[$key] = $State.activeAgents[$key]
    }

    Set-Content -Path $StatePath -Value ($payload | ConvertTo-Json -Compress -Depth 10) -Encoding UTF8
}

function Resolve-AgentName {
    param(
        [Parameter(Mandatory)]$State,
        [string]$TranscriptPath,
        [string]$AgentName
    )

    if ($AgentName) {
        return $AgentName
    }

    if ($TranscriptPath -and $State.activeAgents.Contains($TranscriptPath)) {
        return $State.activeAgents[$TranscriptPath]
    }

    return $State.lastAgent
}

function Get-ToolArgumentsPayload {
    param($Event)

    # VS Code sends tool_input as a parsed object; CLI may send toolInput
    $toolInput = Get-HookProperty -Event $Event -Names @('tool_input', 'toolInput')
    if ($null -ne $toolInput) {
        return $toolInput
    }

    # CLI sends toolArgs as a JSON string; parse to object for normalization
    $toolArgs = Get-HookProperty -Event $Event -Names @('toolArgs')
    return ConvertFrom-JsonSafe -Value $toolArgs
}

function Get-ToolResultPayload {
    param($Event)

    $toolResult = Get-HookProperty -Event $Event -Names @('tool_result', 'toolResult', 'tool_response', 'toolResponse')
    return ConvertFrom-JsonSafe -Value $toolResult
}

function New-LogEntry {
    param(
        [Parameter(Mandatory)]$Event,
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][string]$NormalizedEventName,
        [Parameter(Mandatory)][string]$Timestamp,
        [string]$TranscriptPath
    )

    $entry = [ordered]@{
        ts = $Timestamp
        ts_iso = ConvertTo-IsoTimestamp -Timestamp $Timestamp
        sid = $SessionId
        event = $NormalizedEventName
        cwd = $Event.cwd
    }

    if ($TranscriptPath) {
        $entry.transcript_path = $TranscriptPath
    }

    return $entry
}

function Get-LogDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$SessionRoot,

        [Parameter(Mandatory)]
        [string]$SessionId
    )

    $sessionPath = Join-Path $SessionRoot $SessionId
    $fallbackDir = Join-Path $sessionPath 'logs'
    $metadataPath = Join-Path $sessionPath 'metadata.yaml'

    if (-not (Test-Path $metadataPath)) {
        return $fallbackDir
    }

    try {
        $metadataContent = Get-Content $metadataPath -Raw
    }
    catch {
        return $fallbackDir
    }

    $iterationMatch = [regex]::Match($metadataContent, '(?m)^iteration:\s*(\d+)\s*$')
    if (-not $iterationMatch.Success) {
        return $fallbackDir
    }

    $iteration = $iterationMatch.Groups[1].Value
    return Join-Path $sessionPath (Join-Path (Join-Path 'iterations' $iteration) 'logs')
}

try {
    $inputJson = [Console]::In.ReadToEnd()
    $event = $inputJson | ConvertFrom-Json
    $normalizedEventName = Get-NormalizedEventName -HookEventName $event.hookEventName
    $timestamp = [string](Get-HookProperty -Event $event -Names @('timestamp'))
    $transcriptPath = [string](Get-HookProperty -Event $event -Names @('transcript_path', 'transcriptPath'))
    $eventSessionId = [string](Get-HookProperty -Event $event -Names @('sessionId'))

    $sessionRoot = Join-Path $event.cwd '.ralph-sessions'
    $activeSessionFile = Join-Path $sessionRoot '.active-session'

    # No active Ralph session; pass through silently
    if (-not (Test-Path $activeSessionFile)) {
        Write-Output '{"continue":true}'
        exit 0
    }

    $sessionId = $eventSessionId
    if (-not $sessionId) {
        $sessionId = (Get-Content $activeSessionFile -Raw).Trim()
    }

    if (-not $sessionId) {
        Write-Output '{"continue":true}'
        exit 0
    }

    # Defensive session-state validation: reject stale/completed sessions
    $sessionDir = Join-Path $sessionRoot $sessionId
    if (-not (Test-Path $sessionDir)) {
        Write-Warning "[ralph-tool-logger] Session directory not found: $sessionId - skipping log entry"
        Write-Output '{"continue":true}'
        exit 0
    }

    $sessionMetadataPath = Join-Path $sessionDir 'metadata.yaml'
    if (Test-Path $sessionMetadataPath) {
        try {
            $metaContent = Get-Content $sessionMetadataPath -Raw
            if ($metaContent -match '(?m)^\s*state:\s*COMPLETE\s*$') {
                Write-Warning "[ralph-tool-logger] Session $sessionId is COMPLETE - skipping log entry"
                Write-Output '{"continue":true}'
                exit 0
            }
        }
        catch {
            # metadata unreadable; allow logging (fail-open)
        }
    }

    $logDir = Get-LogDirectory -SessionRoot $sessionRoot -SessionId $sessionId
    $toolLogFile = Join-Path $logDir 'tool-usage.jsonl'
    $subagentLogFile = Join-Path $logDir 'subagent-usage.jsonl'
    $hookStateDir = Join-Path $sessionRoot '.hook-state'
    $hookStateFile = Join-Path $hookStateDir 'active-agents.json'

    # Ensure directories
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    if (-not (Test-Path $hookStateDir)) { New-Item -ItemType Directory -Path $hookStateDir -Force | Out-Null }

    $state = Get-HookState -StatePath $hookStateFile
    $agentName = [string](Get-HookProperty -Event $event -Names @('agent_id', 'agentName'))
    $agentType = [string](Get-HookProperty -Event $event -Names @('agent_type'))
    $resolvedAgentName = Resolve-AgentName -State $state -TranscriptPath $transcriptPath -AgentName $agentName

    switch ($normalizedEventName) {
        'subagentStart' {
            $entry = New-LogEntry -Event $event -SessionId $sessionId -NormalizedEventName $normalizedEventName -Timestamp $timestamp -TranscriptPath $transcriptPath
            if ($resolvedAgentName) {
                $entry.agent = $resolvedAgentName
            }
            if ($agentType) {
                $entry.agent_type = $agentType
            }

            if ($transcriptPath -and $resolvedAgentName) {
                $state.activeAgents[$transcriptPath] = $resolvedAgentName
            }

            if ($resolvedAgentName) {
                $state.lastAgent = $resolvedAgentName
            }

            Save-HookState -StatePath $hookStateFile -State $state
            Add-Content -Path $subagentLogFile -Value ($entry | ConvertTo-Json -Compress -Depth 10) -Encoding UTF8
        }
        'subagentStop' {
            $entry = New-LogEntry -Event $event -SessionId $sessionId -NormalizedEventName $normalizedEventName -Timestamp $timestamp -TranscriptPath $transcriptPath
            if ($resolvedAgentName) {
                $entry.agent = $resolvedAgentName
            }
            if ($agentType) {
                $entry.agent_type = $agentType
            }

            $stopHookActive = Get-HookProperty -Event $event -Names @('stop_hook_active', 'stopHookActive')
            if ($null -ne $stopHookActive) {
                $entry.stop_hook_active = [bool]$stopHookActive
            }

            if ($transcriptPath -and $state.activeAgents.Contains($transcriptPath)) {
                $state.activeAgents.Remove($transcriptPath)
            }

            $remainingAgents = @($state.activeAgents.Values)
            $state.lastAgent = if ($remainingAgents.Count -gt 0) { $remainingAgents[-1] } else { $null }

            Save-HookState -StatePath $hookStateFile -State $state
            Add-Content -Path $subagentLogFile -Value ($entry | ConvertTo-Json -Compress -Depth 10) -Encoding UTF8
        }
        { $_ -in @('preToolUse', 'postToolUse') } {
            $entry = New-LogEntry -Event $event -SessionId $sessionId -NormalizedEventName $normalizedEventName -Timestamp $timestamp -TranscriptPath $transcriptPath

            if ($resolvedAgentName) {
                $entry.agent = $resolvedAgentName
            }

            $toolName = [string](Get-HookProperty -Event $event -Names @('tool_name', 'toolName'))
            if ($toolName) {
                $entry.tool = $toolName
            }
            if ($agentType) {
                $entry.agent_type = $agentType
            }

            $toolArguments = Get-ToolArgumentsPayload -Event $event
            if ($env:RALPH_LOG_PAYLOAD -eq 'true' -and $null -ne $toolArguments) {
                $entry.tool_args = $toolArguments
            }

            $toolResult = Get-ToolResultPayload -Event $event
            if ($null -ne $toolResult) {
                $resultType = Get-HookProperty -Event $toolResult -Names @('resultType')
                if ($null -ne $resultType) {
                    $entry.result_type = [string]$resultType
                }

                $resultText = Get-HookProperty -Event $toolResult -Names @('textResultForLlm')
                if ($resultText) {
                    $entry.result_text = [string]$resultText
                }

                if ($env:RALPH_LOG_PAYLOAD -eq 'true') {
                    $entry.tool_result = $toolResult
                }
            }

            Add-Content -Path $toolLogFile -Value ($entry | ConvertTo-Json -Compress -Depth 10) -Encoding UTF8
        }
    }
}
catch {
    # Hook failures must not crash the agent session
}

Write-Output '{"continue":true}'
exit 0
