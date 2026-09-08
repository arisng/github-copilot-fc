<#
.SYNOPSIS
    Local test suite for machina-run-path-guard hook.
.DESCRIPTION
    Tests the run-path-guard.ps1 script with mock payloads.
    Run: pwsh -NoProfile -File hooks/machina-run-path-guard/scripts/tests/test-run-path-guard.ps1
#>

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSScriptRoot
$hookScript = Join-Path $scriptDir 'run-path-guard.ps1'

$passed = 0
$failed = 0
$total = 0

function Invoke-Hook {
    param([string]$JsonPayload)
    $result = $JsonPayload | pwsh -NoProfile -File $hookScript 2>&1
    return ($result -join "`n").Trim()
}

function Assert-Equal {
    param(
        [string]$TestName,
        [string]$Actual,
        [string]$Expected
    )
    $script:total++
    if ($Actual -eq $Expected) {
        $script:passed++
        Write-Host "  PASS: $TestName" -ForegroundColor Green
    }
    else {
        $script:failed++
        Write-Host "  FAIL: $TestName" -ForegroundColor Red
        Write-Host "    Expected: $Expected" -ForegroundColor Yellow
        Write-Host "    Actual:   $Actual" -ForegroundColor Yellow
    }
}

function Assert-Contains {
    param(
        [string]$TestName,
        [string]$Actual,
        [string]$Substring
    )
    $script:total++
    if ($Actual -match [regex]::Escape($Substring)) {
        $script:passed++
        Write-Host "  PASS: $TestName" -ForegroundColor Green
    }
    else {
        $script:failed++
        Write-Host "  FAIL: $TestName" -ForegroundColor Red
        Write-Host "    Expected to contain: $Substring" -ForegroundColor Yellow
        Write-Host "    Actual: $Actual" -ForegroundColor Yellow
    }
}

# --- Test fixtures ---

$sessionId = "test-session-abc123"
$coprilotHome = $env:USERPROFILE
$correctPath = "$coprilotHome\.copilot\session-state\$sessionId\machina-runs"

Write-Host "`n=== machina-run-path-guard Tests ===" -ForegroundColor Cyan

# --- Test 1: Correct path → pass-through ---
Write-Host "`nTest 1: Correct path → pass-through" -ForegroundColor White
$payload1 = @{
    tool_name = "powershell"
    tool_input = @{
        command = "python3 scripts/machine-driver.py init --machine test.json --run-dir $correctPath"
    }
    sessionId = $sessionId
    cwd = "C:\test"
} | ConvertTo-Json -Depth 5
$result1 = Invoke-Hook -JsonPayload $payload1
Assert-Equal -TestName "Correct path returns empty" -Actual $result1 -Expected "{}"

# --- Test 2: Wrong path → warning ---
Write-Host "`nTest 2: Wrong path → warning" -ForegroundColor White
$payload2 = @{
    tool_name = "powershell"
    tool_input = @{
        command = "python3 scripts/machine-driver.py init --machine test.json --run-dir /tmp/machina-runs"
    }
    sessionId = $sessionId
    cwd = "C:\test"
} | ConvertTo-Json -Depth 5
$result2 = Invoke-Hook -JsonPayload $payload2
Assert-Contains -TestName "Wrong path returns modifiedResult" -Actual $result2 -Substring "modifiedResult"
Assert-Contains -TestName "Warning mentions actual path" -Actual $result2 -Substring "/tmp/machina-runs"
Assert-Contains -TestName "Warning mentions expected path" -Actual $result2 -Substring "session-state"

# --- Test 3: Old convention → warning ---
Write-Host "`nTest 3: Old convention .machina/runs → warning" -ForegroundColor White
$payload3 = @{
    tool_name = "powershell"
    tool_input = @{
        command = "python3 scripts/machine-driver.py status --run-dir .machina/runs --run run_abc"
    }
    sessionId = $sessionId
    cwd = "C:\test"
} | ConvertTo-Json -Depth 5
$result3 = Invoke-Hook -JsonPayload $payload3
Assert-Contains -TestName "Old convention returns modifiedResult" -Actual $result3 -Substring "modifiedResult"
Assert-Contains -TestName "Warning mentions old path" -Actual $result3 -Substring ".machina/runs"

# --- Test 4: No --run-dir → pass-through (info only) ---
Write-Host "`nTest 4: No --run-dir → pass-through" -ForegroundColor White
$payload4 = @{
    tool_name = "powershell"
    tool_input = @{
        command = "python3 scripts/machine-driver.py status --run run_abc"
    }
    sessionId = $sessionId
    cwd = "C:\test"
} | ConvertTo-Json -Depth 5
$result4 = Invoke-Hook -JsonPayload $payload4
Assert-Equal -TestName "No --run-dir returns empty" -Actual $result4 -Expected "{}"

# --- Test 5: Non-machina command → skip ---
Write-Host "`nTest 5: Non-machina command → skip" -ForegroundColor White
$payload5 = @{
    tool_name = "powershell"
    tool_input = @{
        command = "python3 other-script.py --run-dir /tmp/machina-runs"
    }
    sessionId = $sessionId
    cwd = "C:\test"
} | ConvertTo-Json -Depth 5
$result5 = Invoke-Hook -JsonPayload $payload5
Assert-Equal -TestName "Non-machina command returns empty" -Actual $result5 -Expected "{}"

# --- Test 6: No sessionId → pass-through ---
Write-Host "`nTest 6: No sessionId → pass-through" -ForegroundColor White
$payload6 = @{
    tool_name = "powershell"
    tool_input = @{
        command = "python3 scripts/machine-driver.py init --machine test.json --run-dir /tmp/machina-runs"
    }
    cwd = "C:\test"
} | ConvertTo-Json -Depth 5
$result6 = Invoke-Hook -JsonPayload $payload6
Assert-Equal -TestName "No sessionId returns empty" -Actual $result6 -Expected "{}"

# --- Test 7: Non-powershell tool → skip ---
Write-Host "`nTest 7: Non-powershell tool → skip" -ForegroundColor White
$payload7 = @{
    tool_name = "ide_getDiagnostics"
    tool_input = @{
        command = "python3 scripts/machine-driver.py init --machine test.json --run-dir /tmp/machina-runs"
    }
    sessionId = $sessionId
    cwd = "C:\test"
} | ConvertTo-Json -Depth 5
$result7 = Invoke-Hook -JsonPayload $payload7
Assert-Equal -TestName "Non-powershell tool returns empty" -Actual $result7 -Expected "{}"

# --- Test 8: Custom COPILOT_HOME → expected path adjusts ---
Write-Host "`nTest 8: Custom COPILOT_HOME → expected path adjusts" -ForegroundColor White
$oldHome = $env:COPILOT_HOME
$env:COPILOT_HOME = "C:\custom\copilot"
$payload8 = @{
    tool_name = "powershell"
    tool_input = @{
        command = "python3 scripts/machine-driver.py init --machine test.json --run-dir C:\custom\copilot\session-state\$sessionId\machina-runs"
    }
    sessionId = $sessionId
    cwd = "C:\test"
} | ConvertTo-Json -Depth 5
$result8 = Invoke-Hook -JsonPayload $payload8
Assert-Equal -TestName "Custom COPILOT_HOME correct path returns empty" -Actual $result8 -Expected "{}"
$env:COPILOT_HOME = $oldHome

# --- Summary ---
Write-Host "`n=== Results: $passed/$total passed, $failed failed ===" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
