<#
.SYNOPSIS
    Enhances machina status output by cross-referencing enabled_events against
    evidence checks that _enabled_events() does not evaluate.

.DESCRIPTION
    PostToolUse hook that fires after powershell/bash tool invocations. When the
    command runs `machine-driver.py status`, this hook reads the check results
    from the status output and re-categorizes enabled_events as truly enabled
    (all checks pass) or conditionally enabled (checks fail or missing).

    Exit code 0 always — this is a non-blocking hook.
#>

$ErrorActionPreference = 'Stop'

# --- Helpers ---

function Get-JsonInput {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    try {
        return ($raw | ConvertFrom-Json)
    }
    catch {
        # Malformed JSON — silently pass (non-blocking hook)
        return $null
    }
}

function Get-ToolInput {
    param([psobject]$Event)
    # VS Code: tool_input (object), CLI: toolArgs (JSON string)
    $inputObj = $null
    $prop = $Event.PSObject.Properties['tool_input']
    if ($null -ne $prop -and $null -ne $prop.Value) {
        $inputObj = $prop.Value
    }
    else {
        $prop = $Event.PSObject.Properties['toolArgs']
        if ($null -ne $prop -and $null -ne $prop.Value) {
            $val = $prop.Value
            if ($val -is [string]) {
                $inputObj = ($val | ConvertFrom-Json)
            }
            else {
                $inputObj = $val
            }
        }
    }
    return $inputObj
}

function Get-ObjectProperty {
    param([psobject]$Obj, [string[]]$Names)
    if ($null -eq $Obj) { return $null }
    foreach ($name in $Names) {
        $p = $Obj.PSObject.Properties[$name]
        if ($null -ne $p -and $null -ne $p.Value) { return $p.Value }
    }
    return $null
}

function Extract-CommandFromInput {
    param([psobject]$InputObj)
    if ($null -eq $InputObj) { return $null }
    foreach ($name in @('command', 'cmd')) {
        $p = $InputObj.PSObject.Properties[$name]
        if ($null -ne $p -and $null -ne $p.Value -and $p.Value -is [string]) {
            return $p.Value
        }
    }
    return $null
}

function Get-MachineJson {
    param([string]$RunDirPath)
    if ([string]::IsNullOrWhiteSpace($RunDirPath)) { return $null }

    $candidates = @(
        (Join-Path $RunDirPath 'machine.json'),
        (Join-Path (Split-Path $RunDirPath -Parent) 'machine.json'),
        (Join-Path (Get-Location).Path 'machine.json'),
        (Join-Path (Get-Location).Path '.machina' | Join-Path -ChildPath 'machines' | Join-Path -ChildPath 'machine.json')
    )

    foreach ($c in $candidates) {
        if (Test-Path $c) {
            try {
                return (Get-Content -Raw -Path $c | ConvertFrom-Json)
            }
            catch {
                continue
            }
        }
    }
    return $null
}

function Get-MachinaRunDir {
    param(
        [string]$SessionId,
        [string]$RunDir,
        [string]$RunId
    )
    if ([string]::IsNullOrWhiteSpace($SessionId)) { return $null }
    $sessionDir = Join-Path $env:USERPROFILE ".copilot-dojo\session-state\$SessionId"
    $machinaDir = Join-Path $sessionDir "machina-runs"
    if ($RunId) {
        return Join-Path $machinaDir $RunId
    }
    return $machinaDir
}

function Get-SessionId {
    param([psobject]$Event)
    foreach ($name in @('sessionId', 'session_id')) {
        $prop = $Event.PSObject.Properties[$name]
        if ($null -ne $prop -and $null -ne $prop.Value) {
            return $prop.Value
        }
    }
    return $null
}

function Write-HookLog {
    param(
        [string]$RunDir,
        [string]$HookName,
        [string]$Event,
        [string]$ToolName,
        [string]$Command,
        [string]$Action,
        [object]$Output
    )
    if ([string]::IsNullOrWhiteSpace($RunDir)) { return }
    try {
        $logDir = $RunDir
        if (-not (Test-Path $logDir)) {
            try { New-Item -ItemType Directory -Path $logDir -Force | Out-Null } catch { return }
        }
        $logFile = Join-Path $logDir "hooks.jsonl"
        $entry = @{
            ts = (Get-Date -Format "o")
            hook = $HookName
            event = $Event
            tool = $ToolName
            cmd = if ($Command.Length -gt 200) { $Command.Substring(0, 200) + "..." } else { $Command }
            action = $Action
            out = $Output
        }
        $line = $entry | ConvertTo-Json -Compress -Depth 10
        Add-Content -Path $logFile -Value $line -Encoding UTF8
    }
    catch {
        # Graceful: logging failure must not affect hook behavior
    }
}

# --- Main ---

$event = Get-JsonInput
if ($null -eq $event) { Write-Output '{}'; exit 0 }

# Determine tool name (VS Code: tool_name, CLI: toolName)
$toolName = Get-ObjectProperty -Obj $event -Names @('tool_name', 'toolName')

$shellTools = @('powershell', 'bash', 'shell')
if ($toolName -notin $shellTools) { Write-Output '{}'; exit 0 }

# Get tool input and extract command
$inputObj = Get-ToolInput -Event $event
$command = Extract-CommandFromInput -InputObj $inputObj

if ([string]::IsNullOrWhiteSpace($command)) { Write-Output '{}'; exit 0 }

# Extract session ID and run ID for logging
$sessionId = Get-SessionId -Event $event
$logRunId = $null
if ($command -match '--run\s+(\S+)') {
    $logRunId = $Matches[1].Trim('"', "'")
}
$logRunDir = Get-MachinaRunDir -SessionId $sessionId -RunId $logRunId

# Only fire for machine-driver.py status commands
# Handle both quoted and unquoted paths: machine-driver.py" status or machine-driver.py status
if ($command -notmatch 'machine-driver\.py["\s]+status') {
    Write-HookLog -RunDir $logRunDir -HookName "event-gate" -Event "postToolUse" -ToolName $toolName -Command $command -Action "pass-through" -Output @{}
    Write-Output '{}'; exit 0
}

# Get tool result (VS Code: tool_response/result, CLI: toolResult)
$toolResult = Get-ObjectProperty -Obj $event -Names @('tool_response', 'toolResult', 'result')
if ($null -eq $toolResult) {
    Write-HookLog -RunDir $logRunDir -HookName "event-gate" -Event "postToolUse" -ToolName $toolName -Command $command -Action "pass-through" -Output @{}
    Write-Output '{}'; exit 0
}

# textResultForLlm
$textResult = Get-ObjectProperty -Obj $toolResult -Names @('textResultForLlm', 'text_result_for_llm')
if ([string]::IsNullOrWhiteSpace($textResult)) {
    Write-HookLog -RunDir $logRunDir -HookName "event-gate" -Event "postToolUse" -ToolName $toolName -Command $command -Action "pass-through" -Output @{}
    Write-Output '{}'; exit 0
}

# Parse status JSON
$status = $null
try {
    $status = $textResult | ConvertFrom-Json
}
catch {
    Write-HookLog -RunDir $logRunDir -HookName "event-gate" -Event "postToolUse" -ToolName $toolName -Command $command -Action "pass-through" -Output @{}
    Write-Output '{}'; exit 0
}

if ($null -eq $status) {
    Write-HookLog -RunDir $logRunDir -HookName "event-gate" -Event "postToolUse" -ToolName $toolName -Command $command -Action "pass-through" -Output @{}
    Write-Output '{}'; exit 0
}

# Handle both {data:{...}} (actual) and flat {...} (edge case) formats
# Check ok at outer level first, then extract data
$ok = Get-ObjectProperty -Obj $status -Names @('ok')
$statusData = $status.data
if ($null -eq $statusData) { $statusData = $status }

if ($ok -ne $true) {
    Write-HookLog -RunDir $logRunDir -HookName "event-gate" -Event "postToolUse" -ToolName $toolName -Command $command -Action "pass-through" -Output @{}
    Write-Output '{}'; exit 0
}

$enabledEvents = Get-ObjectProperty -Obj $statusData -Names @('enabled_events')
if ($null -eq $enabledEvents -or $enabledEvents.Count -eq 0) {
    Write-HookLog -RunDir $logRunDir -HookName "event-gate" -Event "postToolUse" -ToolName $toolName -Command $command -Action "pass-through" -Output @{}
    Write-Output '{}'; exit 0
}

# Parse --run-dir and --run from command to find machine.json
$runDir = $null
$runId = $null
if ($command -match '--run-dir\s+"?([^"\s]+)"?') {
    $runDir = $Matches[1]
}
if ($command -match '--run\s+"?([^"\s]+)"?') {
    $runId = $Matches[1]
}
if (-not $runDir) { $runDir = 'machina-runs' }

if ($runId) {
    $runDirPath = Join-Path $runDir $runId
}
else {
    $runDirPath = $runDir
}

# Find machine.json — prefer run dir (has tools+states), fall back to parent/cwd
$machine = Get-MachineJson -RunDirPath $runDirPath

# Also try the parent of run dir for the case where run_dir is a subdirectory
# of the machine directory
if ($null -eq $machine -and (Split-Path $runDirPath -Parent)) {
    $machine = Get-MachineJson -RunDirPath (Split-Path $runDirPath -Parent)
}

if ($null -eq $machine) {
    Write-HookLog -RunDir $logRunDir -HookName "event-gate" -Event "postToolUse" -ToolName $toolName -Command $command -Action "pass-through" -Output @{}
    Write-Output '{}'; exit 0
}

$tools = $machine.tools
$states = $machine.states
if ($null -eq $tools -or $null -eq $states) {
    Write-HookLog -RunDir $logRunDir -HookName "event-gate" -Event "postToolUse" -ToolName $toolName -Command $command -Action "pass-through" -Output @{}
    Write-Output '{}'; exit 0
}

# Get current state
$stateKey = Get-ObjectProperty -Obj $statusData -Names @('state')
if ([string]::IsNullOrWhiteSpace($stateKey)) {
    Write-HookLog -RunDir $logRunDir -HookName "event-gate" -Event "postToolUse" -ToolName $toolName -Command $command -Action "pass-through" -Output @{}
    Write-Output '{}'; exit 0
}

$stateObj = $null
$stateProp = $states.PSObject.Properties[$stateKey]
if ($null -ne $stateProp) { $stateObj = $stateProp.Value }
if ($null -eq $stateObj) {
    Write-HookLog -RunDir $logRunDir -HookName "event-gate" -Event "postToolUse" -ToolName $toolName -Command $command -Action "pass-through" -Output @{}
    Write-Output '{}'; exit 0
}

# Get checks definitions
$checksDefs = Get-ObjectProperty -Obj $stateObj -Names @('checks')
if ($null -eq $checksDefs -or $checksDefs.Count -eq 0) {
    # No checks in state definition — nothing to cross-reference
    Write-HookLog -RunDir $logRunDir -HookName "event-gate" -Event "postToolUse" -ToolName $toolName -Command $command -Action "pass-through" -Output @{}
    Write-Output '{}'; exit 0
}

# Get check results from status output
$checkResults = Get-ObjectProperty -Obj $statusData -Names @('checks')
# checkResults may be empty/absent — we still cross-reference against checksDefs

# Build a lookup: tool_name -> { passed: bool }
$checkMap = @{}
foreach ($cr in $checkResults) {
    $name = Get-ObjectProperty -Obj $cr -Names @('tool')
    $passed = Get-ObjectProperty -Obj $cr -Names @('passed')
    if ($null -ne $name) {
        $checkMap[$name] = ($passed -eq $true)
    }
}

# Build checks string set for O(1) lookup
$checksSet = @{}
foreach ($name in $checksDefs) {
    $checksSet[$name] = $true
}

# Categorize events
$trulyEnabled = [System.Collections.ArrayList]@()
$conditionallyEnabled = [System.Collections.ArrayList]@()

foreach ($evt in $enabledEvents) {
    $eventName = Get-ObjectProperty -Obj $evt -Names @('event')
    $target = Get-ObjectProperty -Obj $evt -Names @('target')

    $checksPass = $true
    $checksMissing = $false
    $failedChecks = [System.Collections.ArrayList]@()

    foreach ($checkName in $checksDefs) {
        if ($checkMap.ContainsKey($checkName)) {
            if (-not $checkMap[$checkName]) {
                $checksPass = $false
                [void]$failedChecks.Add($checkName)
            }
        }
        else {
            $checksMissing = $true
            $checksPass = $false
            [void]$failedChecks.Add($checkName)
        }
    }

    if ($checksPass) {
        [void]$trulyEnabled.Add(@{ event = $eventName; target = $target })
    }
    else {
        [void]$conditionallyEnabled.Add(@{
            event = $eventName
            target = $target
            reason = if ($checksMissing) { "checks_pending" } else { "checks_failed" }
            failed_checks = @($failedChecks)
        })
    }
}

# If all events are truly enabled, no modification needed
if ($conditionallyEnabled.Count -eq 0) {
    Write-HookLog -RunDir $logRunDir -HookName "event-gate" -Event "postToolUse" -ToolName $toolName -Command $command -Action "pass-through" -Output @{}
    Write-Output '{}'; exit 0
}

# Build modified enabled_events
$modifiedEvents = @($trulyEnabled) + @($conditionallyEnabled)

# Update status data
$statusData.enabled_events = $modifiedEvents

# If data was wrapped, restore wrapper
if ($null -ne $status.data) {
    $status.data = $statusData
}
else {
    $status = $statusData
}

# Return modifiedResult
$modifiedJson = $status | ConvertTo-Json -Compress -Depth 20
$output = @{ modifiedResult = @{ resultType = 'success'; textResultForLlm = $modifiedJson } } | ConvertTo-Json -Compress -Depth 10
Write-HookLog -RunDir $logRunDir -HookName "event-gate" -Event "postToolUse" -ToolName $toolName -Command $command -Action "modifiedResult" -Output $output
Write-Output $output

exit 0

