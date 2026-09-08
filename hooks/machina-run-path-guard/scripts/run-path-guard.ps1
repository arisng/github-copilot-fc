<#
.SYNOPSIS
    Validates --run-dir path convention for machina-driving commands.

.DESCRIPTION
    PostToolUse hook that fires after powershell/bash tool invocations. Detects
    machine-driver.py commands, parses the --run-dir argument, and validates it
    matches the canonical session-scoped path:

        $COPILOT_HOME/session-state/<sessionId>/machina-runs/

    where COPILOT_HOME defaults to ~/.copilot/.

    Returns modifiedResult with a warning when the path doesn't match, so the
    agent can self-correct. Pass-through (empty) when the path is correct or
    the command is not a machina invocation.

    Exit code 0 always — this is a soft-block augmenting hook.
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
        return $null
    }
}

function Get-ToolName {
    param([psobject]$Event)
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
    foreach ($name in @('command', 'commandLine')) {
        $prop = $InputObj.PSObject.Properties[$name]
        if ($null -ne $prop -and $null -ne $prop.Value -and $prop.Value -is [string]) {
            return $prop.Value
        }
    }
    return $null
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

function Parse-CommandLine {
    param([string]$Command)
    $tokens = [System.Collections.Generic.List[string]]::new()
    $current = [System.Text.StringBuilder]::new()
    $inSingle = $false
    $inDouble = $false

    for ($i = 0; $i -lt $Command.Length; $i++) {
        $ch = $Command[$i]
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

function Resolve-ExpectedRunDir {
    <#
    .SYNOPSIS
        Returns the canonical run directory path.
        Always: $COPILOT_HOME/session-state/<sessionId>/machina-runs/
        COPILOT_HOME defaults to ~/.copilot/
    #>
    param(
        [string]$SessionId,
        [string]$Cwd
    )
    if ([string]::IsNullOrWhiteSpace($SessionId)) { return $null }

    $copiHome = $env:COPILOT_HOME
    if ([string]::IsNullOrWhiteSpace($copiHome)) {
        $copiHome = Join-Path $env:USERPROFILE ".copilot"
    }

    return Join-Path $copiHome "session-state\$SessionId\machina-runs"
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
            ts     = (Get-Date -Format "o")
            hook   = $HookName
            event  = $Event
            tool   = $ToolName
            cmd    = if ($Command.Length -gt 200) { $Command.Substring(0, 200) + "..." } else { $Command }
            action = $Action
            out    = $Output
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
if ($toolName -notin @('powershell', 'bash')) {
    Write-Output '{}'
    exit 0
}

$inputObj = Get-ToolInput -Event $event
if ($null -eq $inputObj) { Write-Output '{}'; exit 0 }

$cmd = Get-ToolCommand -InputObj $inputObj
if ([string]::IsNullOrWhiteSpace($cmd)) { Write-Output '{}'; exit 0 }

# Only fire for machine-driver.py commands
if ($cmd -notmatch 'machine-driver\.py') {
    Write-Output '{}'
    exit 0
}

# Extract session ID
$sessionId = Get-SessionId -Event $event
if ([string]::IsNullOrWhiteSpace($sessionId)) {
    Write-Output '{}'
    exit 0
}

# Parse --run-dir from command
$actualRunDir = $null
if ($cmd -match '--run-dir\s+"?([^"\s]+)"?') {
    $actualRunDir = $Matches[1].Trim('"', "'")
}

# If no --run-dir flag, the driver uses its default — info only, no warning
if ([string]::IsNullOrWhiteSpace($actualRunDir)) {
    Write-Output '{}'
    exit 0
}

# Resolve expected path
$cwd = $event.cwd
if ([string]::IsNullOrWhiteSpace($cwd)) { $cwd = (Get-Location).Path }
$expectedRunDir = Resolve-ExpectedRunDir -SessionId $sessionId -Cwd $cwd

if ([string]::IsNullOrWhiteSpace($expectedRunDir)) {
    Write-Output '{}'
    exit 0
}

# Normalize paths for comparison
$expectedNormalized = $expectedRunDir.Replace('/', '\').TrimEnd('\')
$actualNormalized = $actualRunDir.Replace('/', '\').TrimEnd('\')

# Resolve relative paths against cwd
if (-not [System.IO.Path]::IsPathRooted($actualNormalized)) {
    $actualNormalized = Join-Path $cwd $actualNormalized
    $actualNormalized = $actualNormalized.Replace('/', '\').TrimEnd('\')
}

# Compare
if ($actualNormalized -eq $expectedNormalized) {
    # Path matches — pass-through
    Write-Output '{}'
    exit 0
}

# Mismatch — return modifiedResult with warning
$warning = @"
[run-path-guard] WARNING: --run-dir does not match the session-scoped convention.
  Actual:    $actualRunDir
  Expected:  $expectedNormalized
  Convention: `$COPILOT_HOME/session-state/<sessionId>/machina-runs/
Please use the expected path for consistent run history traceability.
"@

$output = @{ modifiedResult = $warning } | ConvertTo-Json -Compress
Write-Output $output

exit 0
