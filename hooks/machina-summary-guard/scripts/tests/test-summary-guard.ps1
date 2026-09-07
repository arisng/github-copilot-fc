<#
.SYNOPSIS
    Smoke tests for the machina-summary-guard hook script.

.DESCRIPTION
    Feeds mock agentStop payloads and asserts correct output:
    - {} for matching summary/report
    - {} when report.json is missing
    - block for result contradiction
    - block for evidence contradiction
    - {} for stop_hook_active (runaway guard)
    - {} for malformed JSON on stdin
#>

$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '..\summary-guard.ps1'

$pass = 0
$fail = 0

function Assert-Output {
    param(
        [string]$TestName,
        [string]$PayloadJson,
        [string]$ExpectedBehavior  # 'allow' or 'block'
    )

    $tmpFile = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($tmpFile, $PayloadJson)
        $result = Get-Content -Raw -Path $tmpFile | pwsh -NoProfile -File $scriptPath 2>$null
    }
    finally {
        Remove-Item -Path $tmpFile -Force -ErrorAction SilentlyContinue
    }

    $isBlock = $result -match '"decision"\s*:\s*"block"'
    $isAllow = $result -match '^\s*\{\s*\}\s*$' -or $result -match '"decision"\s*:\s*"allow"'

    if ($ExpectedBehavior -eq 'block' -and $isBlock) {
        Write-Host "  PASS: $TestName" -ForegroundColor Green
        $script:pass++
    }
    elseif ($ExpectedBehavior -eq 'allow' -and -not $isBlock) {
        Write-Host "  PASS: $TestName" -ForegroundColor Green
        $script:pass++
    }
    else {
        Write-Host "  FAIL: $TestName" -ForegroundColor Red
        Write-Host "    Expected: $ExpectedBehavior, Got block=$isBlock" -ForegroundColor Red
        Write-Host "    Output: $result" -ForegroundColor Red
        $script:fail++
    }
}

function New-TranscriptFile {
    param([array]$Messages)
    $json = $Messages | ConvertTo-Json -Depth 10
    $tmpFile = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($tmpFile, $json)
    return $tmpFile
}

function New-ReportFile {
    param(
        [string]$RunId,
        [string]$Result,
        [string]$FinalState,
        [int]$EvidencePassed,
        [int]$EvidenceFailed
    )
    $report = @{
        schema = 'machina.report.v1'
        run_id = $RunId
        result = $Result
        final_state = $FinalState
        path = @('reviewing', $FinalState)
        events = @('DRAFT_REVIEWED', 'PUBLISHED')
        evidence = @{
            passed = $EvidencePassed
            failed = $EvidenceFailed
        }
        context_snapshot = @{}
    } | ConvertTo-Json -Depth 5

    # Create .machina/runs/<runId>/report.json
    $runDir = Join-Path $TestWorkDir ".machina\runs\$RunId"
    New-Item -ItemType Directory -Path $runDir -Force | Out-Null
    $reportPath = Join-Path $runDir 'report.json'
    [System.IO.File]::WriteAllText($reportPath, $report)
    return $TestWorkDir
}

function New-Payload {
    param(
        [string]$TranscriptPath,
        [string]$Cwd,
        [bool]$StopHookActive = $false
    )
    $payload = @{
        hookEventName = 'agentStop'
        sessionId = 'test-session-001'
        cwd = $Cwd
        transcriptPath = $TranscriptPath
        stopReason = 'end_turn'
        stop_hook_active = $StopHookActive
    }
    return ($payload | ConvertTo-Json -Depth 5)
}

# --- Setup temp working directory ---
$TestWorkDir = Join-Path ([System.IO.Path]::GetTempPath()) "machina-test-$(Get-Random)"
New-Item -ItemType Directory -Path $TestWorkDir -Force | Out-Null

Write-Host "`n=== machina-summary-guard smoke tests ===" -ForegroundColor Cyan

# --- Test 1: Valid summary matching report.json → allow ---
Write-Host "`nMatching cases:" -ForegroundColor Yellow

$transcript1 = New-TranscriptFile -Messages @(
    @{ role = 'user'; content = 'Run the machine' },
    @{ role = 'assistant'; content = '## Report`nResult: SUCCESS`nFinal state: published`nPassed 3, failed 0. All evidence checks passed.' }
)
$workDir1 = New-ReportFile -RunId 'run-001' -Result 'SUCCESS' -FinalState 'published' -EvidencePassed 3 -EvidenceFailed 0
$payload1 = New-Payload -TranscriptPath $transcript1 -Cwd $workDir1
Assert-Output "Valid summary matching report.json => allow" -PayloadJson $payload1 -ExpectedBehavior 'allow'

# --- Test 2: report.json missing → allow (can't validate) ---
Write-Host "`nMissing report cases:" -ForegroundColor Yellow

$transcript2 = New-TranscriptFile -Messages @(
    @{ role = 'user'; content = 'Run the machine' },
    @{ role = 'assistant'; content = '## Report`nResult: SUCCESS' }
)
$emptyWorkDir = Join-Path $TestWorkDir 'empty-run'
New-Item -ItemType Directory -Path $emptyWorkDir -Force | Out-Null
$payload2 = New-Payload -TranscriptPath $transcript2 -Cwd $emptyWorkDir
Assert-Output "report.json missing => allow (pass through)" -PayloadJson $payload2 -ExpectedBehavior 'allow'

# --- Test 3: Summary claims SUCCESS when report says STUCK → block ---
Write-Host "`nResult contradiction cases:" -ForegroundColor Yellow

$transcript3 = New-TranscriptFile -Messages @(
    @{ role = 'user'; content = 'Run the machine' },
    @{ role = 'assistant'; content = '## Report`nThe result was SUCCESS. The workflow completed all phases.' }
)
$workDir3 = New-ReportFile -RunId 'run-003' -Result 'STUCK' -FinalState 'awaiting-review' -EvidencePassed 2 -EvidenceFailed 1
$payload3 = New-Payload -TranscriptPath $transcript3 -Cwd $workDir3
Assert-Output "Summary claims SUCCESS when report says STUCK => block" -PayloadJson $payload3 -ExpectedBehavior 'block'

# --- Test 4: Summary claims "all evidence passed" when report shows failures → block ---
Write-Host "`nEvidence contradiction cases:" -ForegroundColor Yellow

$transcript4 = New-TranscriptFile -Messages @(
    @{ role = 'user'; content = 'Run the machine' },
    @{ role = 'assistant'; content = '## Report`nResult: SUCCESS.`nAll evidence passed. Completed successfully.' }
)
$workDir4 = New-ReportFile -RunId 'run-004' -Result 'SUCCESS' -FinalState 'published' -EvidencePassed 3 -EvidenceFailed 2
$payload4 = New-Payload -TranscriptPath $transcript4 -Cwd $workDir4
Assert-Output "Summary claims all evidence passed when failures exist => block" -PayloadJson $payload4 -ExpectedBehavior 'block'

# --- Test 5: stop_hook_active: true → allow (runaway guard) ---
Write-Host "`nRunaway guard cases:" -ForegroundColor Yellow

$transcript5 = New-TranscriptFile -Messages @(
    @{ role = 'assistant'; content = 'Result: SUCCESS' }
)
$workDir5 = New-ReportFile -RunId 'run-005' -Result 'STUCK' -FinalState 'blocked' -EvidencePassed 0 -EvidenceFailed 3
$payload5 = New-Payload -TranscriptPath $transcript5 -Cwd $workDir5 -StopHookActive $true
Assert-Output "stop_hook_active: true => allow (runaway guard)" -PayloadJson $payload5 -ExpectedBehavior 'allow'

# --- Test 6: Malformed JSON on stdin → allow (no crash) ---
Write-Host "`nMalformed input cases:" -ForegroundColor Yellow

$payload6 = "this is not json {{{"
$tmpFile6 = [System.IO.Path]::GetTempFileName()
try {
    [System.IO.File]::WriteAllText($tmpFile6, $payload6)
    $result6 = Get-Content -Raw -Path $tmpFile6 | pwsh -NoProfile -File $scriptPath 2>$null
    $isBlock6 = $result6 -match '"decision"\s*:\s*"block"'
    if (-not $isBlock6) {
        Write-Host "  PASS: Malformed JSON => allow (no crash)" -ForegroundColor Green
        $script:pass++
    }
    else {
        Write-Host "  FAIL: Malformed JSON => should not block" -ForegroundColor Red
        Write-Host "    Output: $result6" -ForegroundColor Red
        $script:fail++
    }
}
finally {
    Remove-Item -Path $tmpFile6 -Force -ErrorAction SilentlyContinue
}

# --- Cleanup ---
Remove-Item -Path $TestWorkDir -Recurse -Force -ErrorAction SilentlyContinue

# --- Summary ---
Write-Host "`n=== Results: $pass passed, $fail failed ===" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
