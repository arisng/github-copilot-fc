#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Scenario 02: Draft Missing — Draft file does not exist.

.DESCRIPTION
    Does NOT create draft.md. Runs init and status. The file-exists check
    fails, and the event-gate produces modifiedResult with
    failed_checks: ["file-exists"].

    Expected hooks.jsonl: event-gate produces modifiedResult with
    failed_checks: ["file-exists"].
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
$Workspace = Join-Path ([System.IO.Path]::GetTempPath()) "machina-scenario-02-$(Get-Random)"
$RunDir = Join-Path $Workspace 'runs'
New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
Copy-Item $TestMachine (Join-Path $Workspace 'machine.json') -Force
Copy-Item $TestScripts (Join-Path $Workspace 'scripts') -Recurse -Force

# DO NOT create draft.md — this is the key setup for this scenario

Write-Host "`n=== Scenario 02: Draft Missing ===" -ForegroundColor Cyan
Write-Host "Workspace: $Workspace"
Write-Host "Note: draft.md intentionally NOT created`n"

# NOTE: We do NOT modify machine.json — the --input flags provide values directly.
# The scenario context already sets draft_ready=true from the test machine definition.

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
# The file-exists check will fail because draft.md does not exist
$statusResult = Invoke-Driver @('status', '--run', $runId, '--run-dir', $RunDir)
Assert-JsonField "Step 2: status ok" $statusResult.Output "ok" $true
Assert-JsonField "Step 2: state is drafting" $statusResult.Output "data.state" "drafting"

# Verify that the file-exists check actually failed in the status output
$statusData = ($statusResult.Output | ConvertFrom-Json).data
$fileExistsCheck = $statusData.checks | Where-Object { $_.tool -eq 'file-exists' }
if ($null -ne $fileExistsCheck -and $fileExistsCheck.passed -eq $false) {
    Write-Result "Step 2: file-exists check correctly failed" $true
} else {
    Write-Result "Step 2: file-exists check should have failed" $false
}

# --- Simulate hook output ---
$ts = (Get-Date -Format "o")
$entries = @()

# init: both hooks pass-through
$entries += (@{ ts = $ts; hook = 'event-gate'; event = 'postToolUse'; tool = 'powershell'; action = 'pass-through'; out = @{} } | ConvertTo-Json -Compress)
$entries += (@{ ts = $ts; hook = 'ensures-runner'; event = 'postToolUse'; tool = 'powershell'; action = 'pass-through'; out = @{} } | ConvertTo-Json -Compress)

# status: event-gate produces modifiedResult because file-exists check failed
# The enabled_events list has DRAFT_COMPLETE which is now categorized as
# conditionally enabled (checks_failed) due to the failed file-exists check
$modifiedStatus = $statusData | ConvertTo-Json -Compress -Depth 20
$entries += (@{
    ts = $ts; hook = 'event-gate'; event = 'postToolUse'; tool = 'powershell'; action = 'modifiedResult'
    cmd = 'machine-driver.py status'
    out = @{ modifiedResult = @{ resultType = 'success'; textResultForLlm = $modifiedStatus } }
} | ConvertTo-Json -Compress -Depth 10)
# ensures-runner: pass-through (not a fire command)
$entries += (@{ ts = $ts; hook = 'ensures-runner'; event = 'postToolUse'; tool = 'powershell'; action = 'pass-through'; out = @{} } | ConvertTo-Json -Compress)

$entries | Set-Content $HooksFile -Encoding UTF8

Write-Host "`nExpected hooks.jsonl written to: $HooksFile" -ForegroundColor Gray
Write-Host "Total entries: $($entries.Count)" -ForegroundColor Gray

# Verify entry count
$expectedTotal = 2  # init(1) + status(1) - each hook writes one entry
Write-Host "Expected total entries: $expectedTotal" -ForegroundColor Gray

# --- Summary ---
Write-Host "`n=== Results: $Pass passed, $Fail failed ===" -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })

# Cleanup
Remove-Item $Workspace -Recurse -Force -ErrorAction SilentlyContinue

exit $Fail
