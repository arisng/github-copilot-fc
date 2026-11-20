<#
.SYNOPSIS
    Smoke tests for the machina-ensures-runner hook script.

.DESCRIPTION
    Feeds mock postToolUse payloads and asserts correct output:
    - additionalContext with ensures results for fire events with ensures
    - Empty {} for fire events without ensures
    - Empty {} for non-fire commands
    - Empty {} for malformed JSON on stdin
    - Empty {} for blocked fire events
#>

$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '..\ensures-runner.ps1'

$pass = 0
$fail = 0

function Assert-Empty {
    param(
        [string]$TestName,
        [string]$Result,
        [string]$MachineDir
    )
    $env:FG_MACHINE_DIR = $MachineDir
    try {
        $actual = Get-Content -Raw -Path $tmpFile | pwsh -NoProfile -File $scriptPath 2>$null
        if ($actual -match '^\s*\{\s*\}\s*$') {
            Write-Host "  PASS: $TestName" -ForegroundColor Green
            $script:pass++
        }
        else {
            Write-Host "  FAIL: $TestName" -ForegroundColor Red
            Write-Host "    Expected: {}" -ForegroundColor Red
            Write-Host "    Got: $actual" -ForegroundColor Red
            $script:fail++
        }
    }
    finally {
        $env:FG_MACHINE_DIR = $null
    }
}

function Assert-HasAdditionalContext {
    param(
        [string]$TestName,
        [string]$MachineDir,
        [string]$Pattern
    )
    $env:FG_MACHINE_DIR = $MachineDir
    try {
        $actual = Get-Content -Raw -Path $tmpFile | pwsh -NoProfile -File $scriptPath 2>$null
        $parsed = $actual | ConvertFrom-Json
        if ($parsed.additionalContext -and ($parsed.additionalContext -match $Pattern)) {
            Write-Host "  PASS: $TestName" -ForegroundColor Green
            $script:pass++
        }
        else {
            Write-Host "  FAIL: $TestName" -ForegroundColor Red
            Write-Host "    Expected pattern: $Pattern" -ForegroundColor Red
            Write-Host "    Got: $actual" -ForegroundColor Red
            $script:fail++
        }
    }
    finally {
        $env:FG_MACHINE_DIR = $null
    }
}

function New-TempMachineDir {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) "fg-test-$(Get-Random)"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    New-Item -ItemType Directory -Path "$dir\run-001" -Force | Out-Null
    return $dir
}

# --- Setup ---

$script:tmpFile = [System.IO.Path]::GetTempFileName()
try {

Write-Host "`n=== machina-ensures-runner smoke tests ===" -ForegroundColor Cyan

# ============================================================
# Test 1: Fire event with ensures: ["link-check"] — should return additionalContext
# ============================================================

Write-Host "`nFire event with ensures:" -ForegroundColor Yellow

$tempDir1 = New-TempMachineDir
$machineJson1 = @{
    id = 'test-machine'
    name = 'Test Machine'
    initial = 'drafting'
    tools = @{
        'link-check' = @{
            cmd = "pwsh -NoProfile -File $tempDir1\run-001\mock-link-check.ps1"
            expect_exit = 0
            timeout_seconds = 10
        }
    }
    states = @{
        drafting = @{
            on = @{
                SUBMIT = @{
                    target = 'reviewing'
                    ensures = @('link-check')
                }
            }
        }
        reviewing = @{ on = @{} }
    }
} | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText("$tempDir1\run-001\machine.json", $machineJson1)

# Mock tool script that returns exit 0
$mockScript = @'
exit 0
'@
[System.IO.File]::WriteAllText("$tempDir1\run-001\mock-link-check.ps1", $mockScript)

$payload1 = @{
    tool_name = 'powershell'
    tool_input = @{
        command = "python machine-driver.py fire SUBMIT --run-dir `"$tempDir1`" --run run-001"
    }
    tool_response = @{
        resultType = 'text'
        textResultForLlm = '{"ok":true,"data":{"status":"transitioned","event":"SUBMIT","from":"drafting","to":"reviewing","state":"reviewing","context":{"file":"draft.md"}}}'
    }
    cwd = $tempDir1
} | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($script:tmpFile, $payload1)

Assert-HasAdditionalContext "Fire with ensures: link-check PASSED" -MachineDir $tempDir1 -Pattern "link-check PASSED"

Remove-Item -Path $tempDir1 -Recurse -Force -ErrorAction SilentlyContinue

# ============================================================
# Test 1b: Ledger-based machine dir resolution — tools resolve
#          against the ORIGINAL machine directory, not the run dir
# ============================================================

Write-Host "`nLedger-based machine dir resolution:" -ForegroundColor Yellow

# Create separate directories: original machine dir and run dir
$origMachineDir = Join-Path ([System.IO.Path]::GetTempPath()) "fg-orig-$(Get-Random)"
$runBase = Join-Path ([System.IO.Path]::GetTempPath()) "fg-runs-$(Get-Random)"
New-Item -ItemType Directory -Path $origMachineDir -Force | Out-Null
New-Item -ItemType Directory -Path "$runBase\run-001" -Force | Out-Null

# Mock tool script lives ONLY in the original machine dir
$mockScript2 = @'
exit 0
'@
[System.IO.File]::WriteAllText("$origMachineDir\check.ps1", $mockScript2)

# Machine.json in the run dir — tool cmd is relative (check.ps1 style)
$machineJson1b = @{
    id = 'ledger-test'
    name = 'Ledger Test'
    initial = 'drafting'
    tools = @{
        'check' = @{
            cmd = "pwsh -NoProfile -File check.ps1"
            expect_exit = 0
            timeout_seconds = 10
        }
    }
    states = @{
        drafting = @{
            on = @{
                SUBMIT = @{
                    target = 'reviewing'
                    ensures = @('check')
                }
            }
        }
        reviewing = @{ on = @{} }
    }
} | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText("$runBase\run-001\machine.json", $machineJson1b)

# Write a minimal ledger.jsonl with an init record pointing to the original machine dir
$initPayload = @{
    type = 'init'
    machine_id = 'ledger-test'
    state = 'drafting'
    context = @{}
    machine_dir = $origMachineDir
    timestamp = '2026-01-01T00:00:00Z'
} | ConvertTo-Json -Compress
$hashBytes = [System.Text.Encoding]::UTF8.GetBytes($initPayload)
$hashStream = [System.IO.MemoryStream]::new($hashBytes)
$sha = [System.Security.Cryptography.SHA256]::Create()
$hash = ($sha.ComputeHash($hashStream) | ForEach-Object { $_.ToString('x2') }) -join ''
$ledgerRec = @{ prev_hash = $null; payload = ($initPayload | ConvertFrom-Json); hash = $hash } | ConvertTo-Json -Compress -Depth 10
[System.IO.File]::WriteAllText("$runBase\run-001\ledger.jsonl", $ledgerRec)

$payload1b = @{
    tool_name = 'powershell'
    tool_input = @{
        command = "python machine-driver.py fire SUBMIT --run-dir `"$runBase`" --run run-001"
    }
    tool_response = @{
        resultType = 'text'
        textResultForLlm = '{"ok":true,"data":{"status":"transitioned","event":"SUBMIT","from":"drafting","to":"reviewing","state":"reviewing","context":{}}}'
    }
    cwd = $runBase
} | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($script:tmpFile, $payload1b)

Assert-HasAdditionalContext "Ledger-based: tool resolves from original machine dir" -MachineDir $runBase -Pattern "check PASSED"

Remove-Item -Path $origMachineDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $runBase -Recurse -Force -ErrorAction SilentlyContinue

# ============================================================
# Test 2: Fire event with no ensures — should return {}
# ============================================================

Write-Host "`nFire event without ensures:" -ForegroundColor Yellow

$tempDir2 = New-TempMachineDir
$machineJson2 = @{
    id = 'test-machine'
    name = 'Test Machine'
    initial = 'drafting'
    states = @{
        drafting = @{
            on = @{
                SUBMIT = @{
                    target = 'reviewing'
                }
            }
        }
        reviewing = @{ on = @{} }
    }
} | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText("$tempDir2\run-001\machine.json", $machineJson2)

$payload2 = @{
    tool_name = 'powershell'
    tool_input = @{
        command = "python machine-driver.py fire SUBMIT --run-dir `"$tempDir2`" --run run-001"
    }
    tool_response = @{
        resultType = 'text'
        textResultForLlm = '{"ok":true,"data":{"status":"transitioned","event":"SUBMIT","from":"drafting","to":"reviewing","state":"reviewing","context":{}}}'
    }
    cwd = $tempDir2
} | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($script:tmpFile, $payload2)

Assert-Empty "Fire without ensures => {}" -MachineDir $tempDir2

Remove-Item -Path $tempDir2 -Recurse -Force -ErrorAction SilentlyContinue

# ============================================================
# Test 3: Non-fire command (status) — should return {}
# ============================================================

Write-Host "`nNon-fire command:" -ForegroundColor Yellow

$payload3 = @{
    tool_name = 'powershell'
    tool_input = @{
        command = "python machine-driver.py status --run-dir .machina/runs"
    }
    tool_response = @{
        resultType = 'text'
        textResultForLlm = '{"ok":true,"data":{"state":"drafting","event":"SUBMIT"}}'
    }
    cwd = $tempDir2
} | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($script:tmpFile, $payload3)

Assert-Empty "Non-fire command (status) => {}" -MachineDir $tempDir2

# ============================================================
# Test 4: Malformed JSON on stdin — should return {} (no crash)
# ============================================================

Write-Host "`nMalformed JSON:" -ForegroundColor Yellow

[System.IO.File]::WriteAllText($script:tmpFile, "this is not json {{{{")

Assert-Empty "Malformed JSON => {}" -MachineDir $tempDir2

# ============================================================
# Test 5: Blocked fire event — should return {}
# ============================================================

Write-Host "`nBlocked fire event:" -ForegroundColor Yellow

$payload5 = @{
    tool_name = 'bash'
    tool_input = @{
        command = "python3 machine-driver.py fire APPROVE --run-dir .machina/runs --run run-002"
    }
    tool_response = @{
        resultType = 'text'
        textResultForLlm = '{"ok":true,"data":{"status":"blocked","event":"APPROVE","from":"drafting","reason":"guard","state":"drafting","context":{}}}'
    }
    cwd = $tempDir2
} | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($script:tmpFile, $payload5)

Assert-Empty "Blocked fire event => {}" -MachineDir $tempDir2

} finally {
    Remove-Item -Path $script:tmpFile -Force -ErrorAction SilentlyContinue
}

# --- Summary ---

Write-Host "`n=== Results: $pass passed, $fail failed ===" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
