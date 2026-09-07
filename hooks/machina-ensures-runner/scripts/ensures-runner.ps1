<#
.SYNOPSIS
    Enforces ensures[] post-conditions after machine-driver.py fire commands.

.DESCRIPTION
    PostToolUse hook that fires after powershell/bash tool invocations. Detects
    machine-driver.py fire commands, parses the result, and runs any ensures[]
    tools declared on the transition. Returns additionalContext with pass/fail
    results per tool so the agent is aware of post-condition outcomes.

    Exit code 0 always — this is a non-blocking augmenting hook.
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

function Get-ToolName {
    param([psobject]$Event)
    # VS Code: tool_name, CLI: toolName
    foreach ($name in @('tool_name', 'toolName')) {
        $prop = $Event.PSObject.Properties[$name]
        if ($null -ne $prop -and $null -ne $prop.Value) {
            return $prop.Value
        }
    }
    return $null
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

function Get-ToolCommand {
    param([psobject]$InputObj)
    # powershell: "command" or "commandLine", bash: "command"
    foreach ($name in @('command', 'commandLine')) {
        $prop = $InputObj.PSObject.Properties[$name]
        if ($null -ne $prop -and $null -ne $prop.Value -and $prop.Value -is [string]) {
            return $prop.Value
        }
    }
    return $null
}

function Get-ToolResult {
    param([psobject]$Event)
    # VS Code: tool_response, CLI: toolResult
    $resultObj = $null
    $prop = $Event.PSObject.Properties['tool_response']
    if ($null -ne $prop -and $null -ne $prop.Value) {
        $resultObj = $prop.Value
    }
    else {
        $prop = $Event.PSObject.Properties['toolResult']
        if ($null -ne $prop -and $null -ne $prop.Value) {
            $resultObj = $prop.Value
        }
    }
    if ($null -eq $resultObj) { return $null }

    # Extract textResultForLlm from the result envelope
    $prop = $resultObj.PSObject.Properties['textResultForLlm']
    if ($null -ne $prop -and $null -ne $prop.Value -and $prop.Value -is [string]) {
        return $prop.Value
    }
    return $null
}

function Parse-CommandLine {
    param([string]$Command)
    $tokens = [System.Collections.Generic.List[string]]::new()
    $current = [System.Text.StringBuilder]::new()
    $inSingle = $false
    $inDouble = $false

    for ($i = 0; $i -lt $Command.Length; $i++) {
        $ch = $Command[$i]
        # Shell-level quoting: track quote state only — backslashes are literal
        if ($ch -eq "'" -and -not $inDouble) {
            $inSingle = -not $inSingle
            continue
        }
        if ($ch -eq '"' -and -not $inSingle) {
            $inDouble = -not $inDouble
            continue
        }
        if ($ch -eq ' ' -and -not $inSingle -and -not $inDouble) {
            if ($current.Length -gt 0) {
                $tokens.Add($current.ToString())
                [void]$current.Clear()
            }
            continue
        }
        [void]$current.Append($ch)
    }
    if ($current.Length -gt 0) { $tokens.Add($current.ToString()) }
    return , $tokens.ToArray()
}

function Get-ArgValue {
    param(
        [string[]]$Tokens,
        [string]$Flag
    )
    for ($i = 0; $i -lt $Tokens.Count - 1; $i++) {
        if ($Tokens[$i] -eq $Flag) { return $Tokens[$i + 1] }
    }
    return $null
}

function Find-MachineJson {
    param(
        [string]$Command,
        [string]$WorkingDir
    )
    $tokens = Parse-CommandLine -Command $Command
    $runDir = Get-ArgValue -Tokens $tokens -Flag '--run-dir'
    $runId = Get-ArgValue -Tokens $tokens -Flag '--run'

    if (-not $runDir) { $runDir = '.machina\runs' }

    # Resolve runDir: absolute paths used as-is, relative paths resolved against WorkingDir
    if ([System.IO.Path]::IsPathRooted($runDir)) {
        $base = $runDir
    }
    else {
        $base = Join-Path $WorkingDir $runDir
    }

    if (-not $runId) {
        # Most recent run directory
        if (-not (Test-Path $base)) { return $null }
        $latest = Get-ChildItem -Path $base -Directory |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($null -eq $latest) { return $null }
        $runId = $latest.Name
    }
    $machinePath = Join-Path $base $runId 'machine.json'
    if (Test-Path $machinePath) { return $machinePath }
    return $null
}

function Read-LedgerMachineDir {
    param(
        [string]$RunDir
    )
    # The ledger's init record stores the original machine_dir.
    $ledgerPath = Join-Path $RunDir 'ledger.jsonl'
    if (-not (Test-Path $ledgerPath)) { return $null }
    try {
        $firstLine = Get-Content -Path $ledgerPath -First 1 -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($firstLine)) { return $null }
        $rec = $firstLine | ConvertFrom-Json
        $payload = $rec.payload
        if ($null -ne $payload -and $payload.type -eq 'init' -and -not [string]::IsNullOrWhiteSpace($payload.machine_dir)) {
            return $payload.machine_dir
        }
    }
    catch {
        # Ledger unreadable — fall back to caller
    }
    return $null
}

function Render-Template {
    param(
        [string]$Template,
        [psobject]$Context
    )
    if ([string]::IsNullOrWhiteSpace($Template)) { return $Template }
    if ($null -eq $Context) { return $Template }

    # Replace {ctx.path} and {ctx.path|default} patterns
    $pattern = '\{ctx\.([^}]+)\}'
    $result = [regex]::Replace($Template, $pattern, {
        param($match)
        $expr = $match.Groups[1].Value
        $parts = $expr -split '\|', 2
        $path = $parts[0].Trim()
        $default = if ($parts.Count -gt 1) { $parts[1].Trim() } else { $null }

        # Resolve dotted path from context
        $value = $Context
        foreach ($key in $path.Split('.')) {
            if ($null -eq $value) { break }
            $prop = $value.PSObject.Properties[$key]
            if ($null -ne $prop) { $value = $prop.Value } else { $value = $null }
        }

        if ($null -ne $value) { return [string]$value }
        elseif ($null -ne $default) { return $default }
        else { return "" }
    })
    return $result
}

function Invoke-Tool {
    param(
        [string]$CmdString,
        [string]$MachineDir,
        [int]$TimeoutSec = 30,
        [psobject]$Context = $null
    )
    # Parse command — support both string and array formats
    if ($CmdString -match '^\[.*\]$') {
        try {
            $parts = ($CmdString | ConvertFrom-Json)
            if ($parts -is [System.Array]) { $parts = $parts | ForEach-Object { [string]$_ } }
            else { $parts = @([string]$parts) }
        }
        catch {
            $parts = $CmdString.Trim('[', ']') -split ',' | ForEach-Object { $_.Trim().Trim('"') }
        }
    }
    else {
        $parts = Parse-CommandLine -Command $CmdString
    }
    if ($parts.Count -eq 0) {
        return @{ exit_code = $null; output = ''; error = 'empty command' }
    }
    # Render {ctx.*} templates in all parts
    if ($null -ne $Context) {
        $parts = $parts | ForEach-Object { Render-Template -Template $_ -Context $Context }
    }

    # Resolve machine-relative paths
    if ($parts[0] -match '[/\\]' -and -not [System.IO.Path]::IsPathRooted($parts[0])) {
        $parts[0] = Join-Path $MachineDir $parts[0]
    }
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $parts[0]
        $startInfo.Arguments = ($parts[1..($parts.Count - 1)] -join ' ')
        $startInfo.WorkingDirectory = $MachineDir
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true

        $proc = [System.Diagnostics.Process]::Start($startInfo)
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
            $proc.Kill()
            return @{ exit_code = $null; output = ''; error = "timeout after ${TimeoutSec}s" }
        }
        return @{ exit_code = $proc.ExitCode; output = ($stdout + $stderr).Trim() }
    }
    catch {
        return @{ exit_code = $null; output = ''; error = $_.Exception.Message }
    }
}

function Get-EventName {
    param([string]$Command)
    $tokens = Parse-CommandLine -Command $Command
    $fireIdx = -1
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        if ($tokens[$i] -eq 'fire') { $fireIdx = $i; break }
    }
    if ($fireIdx -ge 0 -and $fireIdx + 1 -lt $tokens.Count) {
        return $tokens[$fireIdx + 1]
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

$toolName = Get-ToolName -Event $event

# Only fire for powershell or bash tools
if ($toolName -notin @('powershell', 'bash')) {
    Write-Output '{}'
    exit 0
}

$inputObj = Get-ToolInput -Event $event
if ($null -eq $inputObj) { Write-Output '{}'; exit 0 }

$cmd = Get-ToolCommand -InputObj $inputObj
if ([string]::IsNullOrWhiteSpace($cmd)) { Write-Output '{}'; exit 0 }

# Extract session ID and run ID for logging
$sessionId = Get-SessionId -Event $event
$logRunId = $null
if ($cmd -match '--run\s+(\S+)') {
    $logRunId = $Matches[1].Trim('"', "'")
}
$logRunDir = Get-MachinaRunDir -SessionId $sessionId -RunId $logRunId

# Only fire when the command invokes machine-driver.py fire
# Handle both quoted and unquoted paths: machine-driver.py" fire or machine-driver.py fire
if ($cmd -notmatch 'machine-driver\.py["\s]+fire') {
    Write-HookLog -RunDir $logRunDir -HookName "ensures-runner" -Event "postToolUse" -ToolName $toolName -Command $cmd -Action "pass-through" -Output @{}
    Write-Output '{}'
    exit 0
}

# Parse the tool result
$resultText = Get-ToolResult -Event $event
if ([string]::IsNullOrWhiteSpace($resultText)) {
    Write-HookLog -RunDir $logRunDir -HookName "ensures-runner" -Event "postToolUse" -ToolName $toolName -Command $cmd -Action "pass-through" -Output @{}
    Write-Output '{}'
    exit 0
}

try {
    $result = ($resultText | ConvertFrom-Json)
}
catch {
    Write-HookLog -RunDir $logRunDir -HookName "ensures-runner" -Event "postToolUse" -ToolName $toolName -Command $cmd -Action "pass-through" -Output @{}
    Write-Output '{}'
    exit 0
}

# Check if the fire was successful
if (-not $result.ok -or $result.data.status -ne 'transitioned') {
    Write-HookLog -RunDir $logRunDir -HookName "ensures-runner" -Event "postToolUse" -ToolName $toolName -Command $cmd -Action "pass-through" -Output @{}
    Write-Output '{}'
    exit 0
}

$eventName = $result.data.event
$fromState = $result.data.'from'

if ([string]::IsNullOrWhiteSpace($eventName) -or [string]::IsNullOrWhiteSpace($fromState)) {
    Write-HookLog -RunDir $logRunDir -HookName "ensures-runner" -Event "postToolUse" -ToolName $toolName -Command $cmd -Action "pass-through" -Output @{}
    Write-Output '{}'
    exit 0
}

# Find the machine.json
$cwd = $event.cwd
if ([string]::IsNullOrWhiteSpace($cwd)) { $cwd = (Get-Location).Path }
$machinePath = Find-MachineJson -Command $cmd -WorkingDir $cwd
if (-not (Test-Path $machinePath)) {
    Write-HookLog -RunDir $logRunDir -HookName "ensures-runner" -Event "postToolUse" -ToolName $toolName -Command $cmd -Action "pass-through" -Output @{}
    Write-Output '{}'; exit 0
}

try {
    $machine = (Get-Content -Raw -Path $machinePath | ConvertFrom-Json)
}
catch {
    Write-HookLog -RunDir $logRunDir -HookName "ensures-runner" -Event "postToolUse" -ToolName $toolName -Command $cmd -Action "pass-through" -Output @{}
    Write-Output '{}'
    exit 0
}

# Find the transition and its ensures
$states = $machine.states
$stateObj = $states.$fromState
if ($null -eq $stateObj) {
    Write-HookLog -RunDir $logRunDir -HookName "ensures-runner" -Event "postToolUse" -ToolName $toolName -Command $cmd -Action "pass-through" -Output @{}
    Write-Output '{}'; exit 0
}

$transition = $null
$onMap = $stateObj.on
if ($null -ne $onMap) {
    $transition = $onMap.PSObject.Properties[$eventName]
}
if ($null -eq $transition -or $null -eq $transition.Value) {
    Write-HookLog -RunDir $logRunDir -HookName "ensures-runner" -Event "postToolUse" -ToolName $toolName -Command $cmd -Action "pass-through" -Output @{}
    Write-Output '{}'; exit 0
}

$transitionValue = $transition.Value
$ensures = @()
if ($null -ne $transitionValue.ensures) {
    $ensures = @($transitionValue.ensures)
}

if ($ensures.Count -eq 0) {
    Write-HookLog -RunDir $logRunDir -HookName "ensures-runner" -Event "postToolUse" -ToolName $toolName -Command $cmd -Action "pass-through" -Output @{}
    Write-Output '{}'
    exit 0
}

# Machine directory — prefer the original machine definition dir stored in
# the ledger's init record.  The machine.json in the run directory is a COPY;
# tool commands are relative to the ORIGINAL machine directory where scripts/ lives.
$machineDir = $null
# Derive run directory from machinePath
$runDirForLedger = Split-Path -Path $machinePath -Parent
$ledgerMachineDir = Read-LedgerMachineDir -RunDir $runDirForLedger
if (-not [string]::IsNullOrWhiteSpace($ledgerMachineDir) -and (Test-Path $ledgerMachineDir)) {
    $machineDir = $ledgerMachineDir
}
else {
    # Fallback: machine.json location (legacy runs without ledger)
    $machineDir = Split-Path -Path $machinePath -Parent
}

# Run ensures tools
$tools = @{}
if ($null -ne $machine.tools) {
    foreach ($prop in $machine.tools.PSObject.Properties) {
        $tools[$prop.Name] = $prop.Value
    }
}

$results = @()
foreach ($toolName in $ensures) {
    $toolDef = $tools[$toolName]
    if ($null -eq $toolDef) {
        $results += [PSCustomObject]@{
            tool   = $toolName
            passed = $false
            detail = "unknown tool: $toolName"
        }
        continue
    }

    $cmdStr = if ($toolDef.cmd -is [System.Array]) {
        ($toolDef.cmd | ForEach-Object { [string]$_ }) -join ' '
    } else { [string]$toolDef.cmd }

    $timeout = if ($toolDef.timeout_seconds) { [int]$toolDef.timeout_seconds } else { 30 }
    $res = Invoke-Tool -CmdString $cmdStr -MachineDir $machineDir -TimeoutSec $timeout -Context $result.data.context

    $passed = $false
    $detail = ''
    if ($null -ne $res.error) {
        $detail = $res.error
    }
    elseif ($null -ne $res.exit_code) {
        $expect = if ($toolDef.expect_exit) { [int]$toolDef.expect_exit } else { 0 }
        $passed = ($res.exit_code -eq $expect)
        if (-not $passed) { $detail = "exit code $($res.exit_code)" }
    }
    $results += [PSCustomObject]@{
        tool   = $toolName
        passed = $passed
        detail = $detail
    }
}

# Format output
$parts = @()
foreach ($r in $results) {
    $status = if ($r.passed) { 'PASSED' } else { 'FAILED' }
    $suffix = if (-not $r.passed -and $r.detail) { " ($($r.detail))" } else { '' }
    $parts += "$($r.tool) $status$suffix"
}
$detailStr = $parts -join ', '
$output = @{ additionalContext = "Ensures post-conditions: $detailStr" } | ConvertTo-Json -Compress
Write-HookLog -RunDir $logRunDir -HookName "ensures-runner" -Event "postToolUse" -ToolName $toolName -Command $cmd -Action "additionalContext" -Output $output
Write-Output $output

exit 0

