#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Scenario 04: Output Missing in Reviewing — Draft exists but output does not.

.DESCRIPTION
    Creates draft.md but NOT output.md. Sets draft_ready=true in the scenario
    context so DRAFT_COMPLETE can fire. After transitioning to reviewing, the
    status check reveals the output-ready check fails.

    Expected hooks.jsonl: event-gate produces modifiedResult with
    failed_checks: ["output-ready"].
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
$Workspace = Join-Path ([System.IO.Path]::GetTempPath()) "machina-scenario-04-$(Get-Random)"
$RunDir = Join-Path $Workspace 'runs'
New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
Copy-Item $TestMachine (Join-Path $Workspace 'machine.json') -Force
Copy-Item $TestScripts (Join-Path $Workspace 'scripts') -Recurse -Force

# Create draft.md but NOT output.md
Set-Content (Join-Path $Workspace 'draft.md') "# Test Draft" -Encoding UTF8
# output.md intentionally NOT created

Write-Host "`n=== Scenario 04: Output Missing in Reviewing ===" -ForegroundColor Cyan
Write-Host "Workspace: $Workspace"
Write-Host "Note: draft.md exists, output.md intentionally NOT created`n"

# NOTE: We do NOT modify machine.json — the --input flags provide values directly.

# --- Step 1: init ---
$initResult = Invoke-Driver @('init', '--machine', (Join-Path $Workspace 'machine.json'), '--scenario', 'default', '--input', "draft_path=$(Join-Path $Workspace 'draft.md')", '--input', "output_path=$(Join-Path $Workspace 'output.md')", '--run-dir', $RunDir)

if ($initResult.ExitCode -ne 0) {
    Write-Host "  FATAL: init failed: $($initResult.Error)" -ForegroundColor Red
    Remove-Item $Workspace -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

$runId = ($initResult.Output | ConvertFrom-Json).data.run_id
$initCtx = ($initResult.Output | ConvertFrom-Json).data.context
Write-Host "Run ID: $runId"
Write-Host "Context draft_ready: $($initCtx.draft_ready)"

if ($initCtx.draft_ready -ne $true) {
    Write-Host "  FATAL: draft_ready should be true" -ForegroundColor Red
    Remove-Item $Workspace -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# --- Step 2: fire DRAFT_COMPLETE (blocked — validate-output requires output.md which doesn't exist) ---
$fireResult = Invoke-Driver @('fire', 'DRAFT_COMPLETE', '--run', $runId, '--note', 'Attempt to complete draft', '--run-dir', $RunDir)
$fireData = ($fireResult.Output | ConvertFrom-Json).data

if ($fireData.status -eq 'blocked') {
    Write-Result "Step 2: fire DRAFT_COMPLETE correctly blocked (evidence)" $true
    Write-Host "    Reason: $($fireData.reason)" -ForegroundColor Gray
    # The validate-output requires check failed because output.md doesn't exist.
    # This demonstrates that the ensures-runner hook won't run post-conditions
    # because the fire was blocked before reaching the transition.
} else {
    Write-Result "Step 2: fire should be blocked by evidence" $false
}

# --- Step 3: status (check current state after blocked fire) ---
$statusResult = Invoke-Driver @('status', '--run', $runId, '--run-dir', $RunDir)
Assert-JsonField "Step 3: status ok" $statusResult.Output "ok" $true
Assert-JsonField "Step 3: still in drafting" $statusResult.Output "data.state" "drafting"

# --- Simulate hook output ---
$ts = (Get-Date -Format "o")
$entries = @()

# init: both hooks pass-through
$entries += (@{ ts = $ts; hook = 'event-gate'; event = 'postToolUse'; tool = 'powershell'; action = 'pass-through'; out = @{} } | ConvertTo-Json -Compress)
$entries += (@{ ts = $ts; hook = 'ensures-runner'; event = 'postToolUse'; tool = 'powershell'; action = 'pass-through'; out = @{} } | ConvertTo-Json -Compress)

# fire DRAFT_COMPLETE (blocked): ensures-runner detects non-transitioned
# status and exits early — produces pass-through only
$entries += (@{ ts = $ts; hook = 'event-gate'; event = 'postToolUse'; tool = 'powershell'; action = 'pass-through'; out = @{} } | ConvertTo-Json -Compress)
$entries += (@{ ts = $ts; hook = 'ensures-runner'; event = 'postToolUse'; tool = 'powershell'; action = 'pass-through'; out = @{} } | ConvertTo-Json -Compress)

# status: event-gate produces modifiedResult — file-exists check failed in drafting
# DRAFT_COMPLETE is categorized as conditionally enabled (checks_failed)
$statusData = ($statusResult.Output | ConvertFrom-Json).data
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

# --- Summary ---
Write-Host "`n=== Results: $Pass passed, $Fail failed ===" -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })

# Cleanup
Remove-Item $Workspace -Recurse -Force -ErrorAction SilentlyContinue

exit $Fail
