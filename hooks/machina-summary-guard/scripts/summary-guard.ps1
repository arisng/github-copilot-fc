<#
.SYNOPSIS
    Validates the agent's summary against report.json facts before session ends.

.DESCRIPTION
    agentStop hook that fires when the agent session ends. Parses the hook
    payload, finds the last assistant message from the transcript, locates
    report.json, and checks the summary for contradictions against report facts.

    Returns:
    - {} if no contradictions (allow the summary)
    - {"decision":"block","reason":"..."} if contradictions are found
    - {} for any error condition (graceful degradation)

    Exit code 0 always — this is a blocking hook that communicates via stdout JSON.
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
        # Malformed JSON — silently pass
        return $null
    }
}

function Get-Property {
    param(
        [psobject]$Object,
        [string[]]$Names
    )
    foreach ($name in $Names) {
        $prop = $Object.PSObject.Properties[$name]
        if ($null -ne $prop -and $null -ne $prop.Value) {
            return $prop.Value
        }
    }
    return $null
}

function Get-BoolProperty {
    param(
        [psobject]$Object,
        [string[]]$Names
    )
    $val = Get-Property -Object $Object -Names $Names
    if ($null -eq $val) { return $false }
    if ($val -is [bool]) { return $val }
    if ($val -is [string]) { return ($val -eq 'true') }
    return [bool]$val
}

function Read-Transcript {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) {
        return $null
    }
    try {
        $raw = Get-Content -Raw -Path $Path
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Get-LastAssistantMessage {
    param([array]$Messages)
    if ($null -eq $Messages -or $Messages.Count -eq 0) { return $null }
    for ($i = $Messages.Count - 1; $i -ge 0; $i--) {
        $msg = $Messages[$i]
        $role = Get-Property -Object $msg -Names @('role', 'Role')
        if ($role -eq 'assistant') {
            $content = Get-Property -Object $msg -Names @('content', 'Content', 'message', 'text')
            if ($content -is [string]) { return $content }
            # Handle content arrays [{type:"text",text:"..."}]
            if ($content -is [array]) {
                $parts = @()
                foreach ($part in $content) {
                    $t = Get-Property -Object $part -Names @('text', 'content')
                    if ($t -is [string]) { $parts += $t }
                }
                if ($parts.Count -gt 0) { return ($parts -join ' ') }
            }
            return $null
        }
    }
    return $null
}

function Find-ReportJson {
    param([string]$Cwd)
    if ([string]::IsNullOrWhiteSpace($Cwd) -or -not (Test-Path $Cwd)) {
        return $null
    }
    
    # Search in multiple locations:
    # 1. .machina/runs/ (standard machina run directory)
    # 2. Directly in cwd (for test scenarios)
    $searchPaths = @(
        (Join-Path $Cwd '.machina\runs'),
        $Cwd
    )
    
    foreach ($searchPath in $searchPaths) {
        if (-not (Test-Path $searchPath)) { continue }
        
        $reports = Get-ChildItem -Path $searchPath -Filter 'report.json' -Recurse -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
        if ($reports.Count -gt 0) {
            return $reports[0].FullName
        }
    }
    return $null
}

function Read-ReportJson {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) {
        return $null
    }
    try {
        $raw = Get-Content -Raw -Path $Path
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
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

# --- Contradiction detection ---

function Find-Contradictions {
    param(
        [string]$Summary,
        [psobject]$Report
    )

    $contradictions = @()
    $reportResult = Get-Property -Object $Report -Names @('result')
    $reportFinalState = Get-Property -Object $Report -Names @('final_state')
    $reportEvidence = Get-Property -Object $Report -Names @('evidence')

    $reportEvidencePassed = $null
    $reportEvidenceFailed = $null
    if ($null -ne $reportEvidence) {
        $reportEvidencePassed = Get-Property -Object $reportEvidence -Names @('passed')
        $reportEvidenceFailed = Get-Property -Object $reportEvidence -Names @('failed')
    }

    # --- Check 1: Result mismatch ---
    # Extract the result claim from the summary
    $summaryUpper = $Summary.ToUpper()
    $resultClaim = $null
    if ($summaryUpper -match '(?:result|status|outcome|completed|finished)\s*(?:is|was|:)?\s*(SUCCESS|STUCK|ABORTED|ESCALATED|IN_PROGRESS)') {
        $resultClaim = $Matches[1]
    }
    elseif ($summaryUpper -match '\b(SUCCESS)\b') {
        $resultClaim = 'SUCCESS'
    }
    elseif ($summaryUpper -match '\b(STUCK)\b') {
        $resultClaim = 'STUCK'
    }
    elseif ($summaryUpper -match '\b(ABORTED)\b') {
        $resultClaim = 'ABORTED'
    }
    elseif ($summaryUpper -match '\b(ESCALATED)\b') {
        $resultClaim = 'ESCALATED'
    }
    elseif ($summaryUpper -match '\b(IN_PROGRESS)\b') {
        $resultClaim = 'IN_PROGRESS'
    }

    if ($null -ne $resultClaim -and $null -ne $reportResult -and $resultClaim -ne $reportResult) {
        $contradictions += "Summary claims result is $resultClaim but report.json says $reportResult"
    }

    # --- Check 2: Evidence count mismatch ---
    # Look for "passed N" or "failed M" patterns
    $evidencePassedClaim = $null
    $evidenceFailedClaim = $null

    if ($Summary -match '(?:all\s+)?evidence\s+(?:checks?\s+)?passed') {
        # "all evidence passed" — implies zero failures
        if ($null -ne $reportEvidenceFailed -and $reportEvidenceFailed -gt 0) {
            $contradictions += "Summary claims all evidence passed but report.json shows $reportEvidenceFailed failure(s)"
        }
    }

    if ($Summary -match 'passed\s+(\d+)') {
        $evidencePassedClaim = [int]$Matches[1]
        if ($null -ne $reportEvidencePassed -and $evidencePassedClaim -ne $reportEvidencePassed) {
            $contradictions += "Summary claims $evidencePassedClaim evidence check(s) passed but report.json shows $reportEvidencePassed"
        }
    }

    if ($Summary -match 'failed\s+(\d+)') {
        $evidenceFailedClaim = [int]$Matches[1]
        if ($null -ne $reportEvidenceFailed -and $evidenceFailedClaim -ne $reportEvidenceFailed) {
            $contradictions += "Summary claims $evidenceFailedClaim evidence check(s) failed but report.json shows $reportEvidenceFailed"
        }
    }

    # --- Check 3: Final state mismatch ---
    if ($null -ne $reportFinalState) {
        # Only check if the summary explicitly names a different state
        $statePattern = '(?:final\s+state|reached|ended\s+in|at\s+state|in\s+state)\s*[:=]?\s*["''`]?(\w+)["''`]?'
        if ($Summary -match $statePattern) {
            $stateClaim = $Matches[1].Trim()
            if ($stateClaim -ne $reportFinalState -and
                $stateClaim -notin @('success', 'stuck', 'aborted', 'escalated', 'in_progress')) {
                $contradictions += "Summary claims final state is '$stateClaim' but report.json shows '$reportFinalState'"
            }
        }
    }

    return $contradictions
}

# --- Main ---

$event = Get-JsonInput
if ($null -eq $event) { Write-Output '{}'; exit 0 }

# Runaway guard: check stop_hook_active
$stopHookActive = Get-BoolProperty -Object $event -Names @('stop_hook_active', 'stopHookActive')
if ($stopHookActive) {
    Write-Output '{}'
    exit 0
}

# Extract transcript path
$transcriptPath = Get-Property -Object $event -Names @('transcript_path', 'transcriptPath')

# Extract cwd
$cwd = Get-Property -Object $event -Names @('cwd', 'workingDirectory', 'working_directory')

# Parse transcript and find last assistant message
$messages = Read-Transcript -Path $transcriptPath
$summary = Get-LastAssistantMessage -Messages $messages

if ([string]::IsNullOrWhiteSpace($summary)) {
    # Can't find summary — pass through
    Write-Output '{}'
    exit 0
}

# Find and parse report.json
$reportPath = Find-ReportJson -Cwd $cwd
if ([string]::IsNullOrWhiteSpace($reportPath)) {
    # No report.json found — can't validate, pass through
    Write-Output '{}'
    exit 0
}

# Derive run ID from report.json location and use session-state path
$sessionId = Get-SessionId -Event $event
$reportDir = Split-Path -Path $reportPath -Parent
$runId = Split-Path -Path $reportDir -Leaf
$logRunDir = Get-MachinaRunDir -SessionId $sessionId -RunId $runId

$report = Read-ReportJson -Path $reportPath
if ($null -eq $report) {
    # Can't parse report — pass through
    Write-HookLog -RunDir $logRunDir -HookName "summary-guard" -Event "agentStop" -ToolName "" -Command "" -Action "pass-through" -Output @{}
    Write-Output '{}'
    exit 0
}

# Check for contradictions
$contradictions = Find-Contradictions -Summary $summary -Report $report

if ($contradictions.Count -eq 0) {
    Write-HookLog -RunDir $logRunDir -HookName "summary-guard" -Event "agentStop" -ToolName "" -Command "" -Action "pass-through" -Output @{}
    Write-Output '{}'
    exit 0
}

# Build block response
$reason = "Report summary contradicts report.json: " + ($contradictions -join '; ') + ". Please revise your summary to match the report facts exactly."
$output = @{
    decision = 'block'
    reason = $reason
} | ConvertTo-Json -Compress

Write-HookLog -RunDir $logRunDir -HookName "summary-guard" -Event "agentStop" -ToolName "" -Command "" -Action "block" -Output $output
Write-Output $output
exit 0

