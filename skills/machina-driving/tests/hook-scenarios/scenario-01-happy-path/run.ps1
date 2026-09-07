#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Scenario 01: Happy Path — All files exist, no errors, successful completion.

.DESCRIPTION
    Creates draft.md and output.md (no "error" words), runs the full driving
    loop: init → status → fire DRAFT_COMPLETE → fire APPROVED → report.
    Validates driver output and simulates hook behavior to produce hooks.jsonl.

    Expected hooks.jsonl: All pass-through (no intervention needed by hooks).
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
$TestMachine = Join-Path $SkillRoot 'tests\machines\hooks-test-machine.json'
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
$Workspace = Join-Path ([System.IO.Path]::GetTempPath()) "machina-scenario-01-$(Get-Random)"
$RunDir = Join-Path $Workspace 'runs'
New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
Copy-Item $TestMachine (Join-Path $Workspace 'machine.json') -Force
Copy-Item $TestScripts (Join-Path $Workspace 'scripts') -Recurse -Force

# Create test files
Set-Content (Join-Path $Workspace 'draft.md') "# Test Draft`nThis is a test draft document." -Encoding UTF8
Set-Content (Join-Path $Workspace 'output.md') "# Test Output`nThis is clean content with no issues." -Encoding UTF8

Write-Host "`n=== Scenario 01: Happy Path ===" -ForegroundColor Cyan
Write-Host "Workspace: $Workspace`n"

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

# --- Step 3: fire DRAFT_COMPLETE ---
$fireDcResult = Invoke-Driver @('fire', 'DRAFT_COMPLETE', '--run', $runId, '--note', 'Draft complete, moving to review', '--run-dir', $RunDir)
Assert-JsonField "Step 3: fire DRAFT_COMPLETE ok" $fireDcResult.Output "ok" $true
Assert-JsonField "Step 3: transitioned to reviewing" $fireDcResult.Output "data.status" "transitioned"

# --- Step 4: fire APPROVED ---
$fireApprovedResult = Invoke-Driver @('fire', 'APPROVED', '--run', $runId, '--note', 'Review approved', '--run-dir', $RunDir)
Assert-JsonField "Step 4: fire APPROVED ok" $fireApprovedResult.Output "ok" $true
Assert-JsonField "Step 4: transitioned to published" $fireApprovedResult.Output "data.status" "transitioned"

# --- Step 5: report ---
$reportResult = Invoke-Driver @('report', '--run', $runId, '--run-dir', $RunDir)
Assert-JsonField "Step 5: report ok" $reportResult.Output "ok" $true
Assert-JsonField "Step 5: result SUCCESS" $reportResult.Output "data.result" "SUCCESS"
Assert-JsonField "Step 5: final_state published" $reportResult.Output "data.final_state" "published"

# --- Simulate hook output ---
$ts = (Get-Date -Format "o")
$entries = @()
$hookEntryTmpl = @{ ts = $ts; event = 'postToolUse'; tool = 'powershell' }

# init: both hooks pass-through
$entries += ($hookEntryTmpl | ConvertTo-Json -Compress)
$entries += ($hookEntryTmpl | ConvertTo-Json -Compress)

# status: both hooks pass-through
$entries += ($hookEntryTmpl | ConvertTo-Json -Compress)
$entries += ($hookEntryTmpl | ConvertTo-Json -Compress)

# fire DRAFT_COMPLETE: event-gate pass-through, ensures-runner runs output-ready
$entries += ($hookEntryTmpl | ConvertTo-Json -Compress)
$entries += (@{
    ts = $ts; hook = 'ensures-runner'; event = 'postToolUse'; tool = 'powershell'; action = 'additionalContext'
    cmd = 'machine-driver.py fire DRAFT_COMPLETE'
    out = @{ additionalContext = "Ensures post-conditions: output-ready PASSED" }
} | ConvertTo-Json -Compress -Depth 10)

# fire APPROVED: both hooks pass-through (no ensures on APPROVED)
$entries += ($hookEntryTmpl | ConvertTo-Json -Compress)
$entries += ($hookEntryTmpl | ConvertTo-Json -Compress)

$entries | Set-Content $HooksFile -Encoding UTF8

Write-Host "`nExpected hooks.jsonl written to: $HooksFile" -ForegroundColor Gray
Write-Host "Total entries: $($entries.Count)" -ForegroundColor Gray

# --- Summary ---
Write-Host "`n=== Results: $Pass passed, $Fail failed ===" -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })

# Cleanup
Remove-Item $Workspace -Recurse -Force -ErrorAction SilentlyContinue

exit $Fail
