#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Scenario 03: Validation Fails — Output contains 'error' words.

.DESCRIPTION
    Creates draft.md and output.md WITH "error" words. Runs init and status.
    The validate-output tool detects errors in output.md. When DRAFT_COMPLETE
    is fired, it is blocked because the validate-output requires check fails.

    Expected hooks.jsonl: ensures-runner exits early (fire blocked, no
    additionalContext produced).
#>
$ErrorActionPreference = 'Stop'

# Resolve the machina-driving skill root from the script's location
# Path: .../skills/machina-driving/tests/hook-scenarios/scenario-XX-name/run.ps1
# Go up 5 levels to repo root, then down to skills/machina-driving
$RepoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel 2>$null)
if (-not $RepoRoot) {
    # Fallback: manual path resolution
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..\..')).Path
}
$SkillRoot = Join-Path $RepoRoot 'skills\machina-driving'
$DriverScript = Join-Path $SkillRoot 'scripts\machine-driver.py'
$TestMachine = Join-Path $SkillRoot 'tests\machines\test-machine.json'
$TestScripts = Join-Path $SkillRoot 'tests\machines\scripts'
$ExpectedDir = Join-Path $PSScriptRoot 'expected'
$HooksFile = Join-Path $ExpectedDir 'hooks.jsonl'
$Pass = 0
$Fail = 0

function Write-Result {
    param([string]$Name, [bool]$Ok)
    if ($Ok) {
        Write-Host "  PASS: $Name" -ForegroundColor Green
        $script:Pass++
    } else {
        Write-Host "  FAIL: $Name" -ForegroundColor Red
        $script:Fail++
    }
}

function Invoke-Driver {
    param([string[]]$DriverArgs)
    $output = & python $DriverScript @DriverArgs 2>&1
    $stdout = ($output | Out-String).Trim()
    return @{ ExitCode = $LASTEXITCODE; Output = $stdout; Error = '' }
}

function Assert-JsonField {
    param([string]$TestName, [string]$Json, [string]$Field, $Expected)
    $parsed = $null
    try { $parsed = $Json | ConvertFrom-Json } catch { }
    if ($null -eq $parsed) {
        Write-Result $TestName $false
        return $null
    }
    $actual = $parsed
    foreach ($part in $Field.Split('.')) {
        $prop = $actual.PSObject.Properties[$part]
        if ($null -eq $prop) { Write-Result $TestName $false; return $null }
        $actual = $prop.Value
    }
    $ok = ($actual -eq $Expected)
    Write-Result $TestName $ok
    if (-not $ok) {
        Write-Host "    Expected: $Expected" -ForegroundColor Yellow
        Write-Host "    Actual:   $actual" -ForegroundColor Yellow
    }
    return $parsed
}

# --- Setup workspace ---
$Workspace = Join-Path ([System.IO.Path]::GetTempPath()) "machina-scenario-03-$(Get-Random)"
$RunDir = Join-Path $Workspace 'runs'
New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
Copy-Item $TestMachine (Join-Path $Workspace 'machine.json') -Force
Copy-Item $TestScripts (Join-Path $Workspace 'scripts') -Recurse -Force

# Create test files: draft exists, output has "error" words
Set-Content (Join-Path $Workspace 'draft.md') "# Test Draft" -Encoding UTF8
Set-Content (Join-Path $Workspace 'output.md') "This output has an error in it. Another error here." -Encoding UTF8

Write-Host "`n=== Scenario 03: Validation Fails ===" -ForegroundColor Cyan
Write-Host "Workspace: $Workspace"
Write-Host "Note: output.md contains 'error' words`n"

# NOTE: We do NOT modify machine.json — the --input flags provide values directly.

# --- Step 1: init ---
$initResult = Invoke-Driver @('init', '--machine', (Join-Path $Workspace 'machine.json'), '--scenario', 'default', '--input', "draft_path=$(Join-Path $Workspace 'draft.md')", '--input', "output_path=$(Join-Path $Workspace 'output.md')", '--run-dir', $RunDir)

if ($initResult.ExitCode -ne 0) {
    Write-Host "  FATAL: init failed: $($initResult.Error)" -ForegroundColor Red
    Remove-Item $Workspace -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

$runId = ($initResult.Output | ConvertFrom-Json).data.run_id
Write-Host "Run ID: $runId"

# --- Step 2: status ---
$statusResult = Invoke-Driver @('status', '--run', $runId, '--run-dir', $RunDir)
Assert-JsonField "Step 2: status ok" $statusResult.Output "ok" $true
Assert-JsonField "Step 2: state is drafting" $statusResult.Output "data.state" "drafting"

# --- Step 3: fire DRAFT_COMPLETE (should be blocked) ---
# The guard requires draft_ready=true, but context has draft_ready=false by default.
# Even if guard passed, validate-output requires would detect error words.
$fireResult = Invoke-Driver @('fire', 'DRAFT_COMPLETE', '--run', $runId, '--note', 'Attempt to complete draft', '--run-dir', $RunDir)
$fireData = ($fireResult.Output | ConvertFrom-Json).data

if ($fireData.status -eq 'blocked') {
    Write-Result "Step 3: fire DRAFT_COMPLETE correctly blocked" $true
    Write-Host "    Reason: $($fireData.reason)" -ForegroundColor Gray
} else {
    Write-Result "Step 3: fire DRAFT_COMPLETE should be blocked" $false
}

# --- Simulate hook output ---
$ts = (Get-Date -Format "o")
$entries = @()

# init: both hooks pass-through
$entries += (@{ ts = $ts; hook = 'event-gate'; event = 'postToolUse'; tool = 'powershell'; action = 'pass-through'; out = @{} } | ConvertTo-Json -Compress)
$entries += (@{ ts = $ts; hook = 'ensures-runner'; event = 'postToolUse'; tool = 'powershell'; action = 'pass-through'; out = @{} } | ConvertTo-Json -Compress)

# status: both hooks pass-through
# DRAFT_COMPLETE is blocked by guard (draft_ready=false), so event-gate
# categorizes it as blocked_events, not enabled_events. No modifiedResult.
$entries += (@{ ts = $ts; hook = 'event-gate'; event = 'postToolUse'; tool = 'powershell'; action = 'pass-through'; out = @{} } | ConvertTo-Json -Compress)
$entries += (@{ ts = $ts; hook = 'ensures-runner'; event = 'postToolUse'; tool = 'powershell'; action = 'pass-through'; out = @{} } | ConvertTo-Json -Compress)

# fire DRAFT_COMPLETE (blocked): ensures-runner detects non-transitioned
# status and exits early — produces pass-through only
$entries += (@{ ts = $ts; hook = 'event-gate'; event = 'postToolUse'; tool = 'powershell'; action = 'pass-through'; out = @{} } | ConvertTo-Json -Compress)
$entries += (@{ ts = $ts; hook = 'ensures-runner'; event = 'postToolUse'; tool = 'powershell'; action = 'pass-through'; out = @{} } | ConvertTo-Json -Compress)

$entries | Set-Content $HooksFile -Encoding UTF8

Write-Host "`nExpected hooks.jsonl written to: $HooksFile" -ForegroundColor Gray
Write-Host "Total entries: $($entries.Count) (all pass-through — no hooks intervention)" -ForegroundColor Gray

# --- Summary ---
Write-Host "`n=== Results: $Pass passed, $Fail failed ===" -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })

# Cleanup
Remove-Item $Workspace -Recurse -Force -ErrorAction SilentlyContinue

exit $Fail
