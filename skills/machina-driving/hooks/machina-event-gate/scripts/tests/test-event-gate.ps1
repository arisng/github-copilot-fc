<#
.SYNOPSIS
    Smoke tests for the machina-event-gate hook script.

.DESCRIPTION
    Feeds mock postToolUse payloads and asserts correct output:
    - modifiedResult with accurate categorization for unsatisfied checks
    - Empty {} for satisfied/absent checks
    - Empty {} for non-status commands
    - Empty {} for malformed JSON
    - Both VS Code and CLI payload formats
#>

$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '..\event-gate.ps1'

$pass = 0
$fail = 0

function Assert-Output {
    param(
        [string]$TestName,
        [string]$PayloadJson,
        [bool]$ExpectModified,
        [string]$ExpectCategory = $null
    )

    $tmpFile = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($tmpFile, $PayloadJson)
        $result = Get-Content -Raw -Path $tmpFile | pwsh -NoProfile -File $scriptPath 2>$null
    }
    finally {
        Remove-Item -Path $tmpFile -Force -ErrorAction SilentlyContinue
    }

    $isModified = $result -notmatch '^\s*\{\s*\}\s*$'

    $testPassed = $false
    if ($ExpectModified -and $isModified) {
        $testPassed = $true
        if ($ExpectCategory) {
            $parsed = $null
            try {
                $parsed = $result | ConvertFrom-Json
                $events = $parsed.modifiedResult.textResultForLlm | ConvertFrom-Json
                $events = $events.data.enabled_events
                $hasCategory = $false
                foreach ($e in $events) {
                    $p = $e.PSObject.Properties['reason']
                    if ($null -ne $p -and $p.Value -eq $ExpectCategory) {
                        $hasCategory = $true
                        break
                    }
                }
                if (-not $hasCategory) { $testPassed = $false }
            }
            catch {
                $testPassed = $false
            }
        }
    }
    elseif (-not $ExpectModified -and -not $isModified) {
        $testPassed = $true
    }

    if ($testPassed) {
        Write-Host "  PASS: $TestName" -ForegroundColor Green
        $script:pass++
    }
    else {
        Write-Host "  FAIL: $TestName" -ForegroundColor Red
        Write-Host "    Expected modified: $ExpectModified, Got: $isModified" -ForegroundColor Red
        if ($ExpectCategory) {
            Write-Host "    Expected category: $ExpectCategory" -ForegroundColor Red
        }
        Write-Host "    Output: $result" -ForegroundColor Red
        $script:fail++
    }
}

Write-Host "`n=== machina-event-gate smoke tests ===" -ForegroundColor Cyan

# --- Machine definition used across tests ---
$machineJson = @{
    id = 'test-machine'
    tools = @{
        'file-exists' = @{ cmd = 'test -f draft.md'; expect_exit = 0; timeout_seconds = 30 }
        'lint-pass' = @{ cmd = 'echo ok'; expect_exit = 0; timeout_seconds = 30 }
    }
    states = @{
        'reviewing-draft' = @{
            checks = @('file-exists', 'lint-pass')
            on = @{
                'DRAFT_REVIEWED' = @{ target = 'publishing' }
            }
        }
    }
}
$machineJsonStr = $machineJson | ConvertTo-Json -Compress -Depth 10

# --- VS Code format tests ---

Write-Host "`nVS Code format (snake_case):" -ForegroundColor Yellow

# Test 1: Status with unsatisfied checks → modifiedResult with checks_failed
$statusPayload1 = @{
    ok = $true
    data = @{
        run_id = 'run_abc'
        machine_id = 'test-machine'
        state = 'reviewing-draft'
        enabled_events = @(
            @{ event = 'DRAFT_REVIEWED'; target = 'publishing' }
        )
        blocked_events = @()
        checks = @(
            @{ tool = 'file-exists'; passed = $true; exit_code = 0; output = ''; error = $null }
            @{ tool = 'lint-pass'; passed = $false; exit_code = 1; output = 'lint errors'; error = $null }
        )
        context = @{}
    }
} | ConvertTo-Json -Compress -Depth 10

$payload1 = @{
    tool_name = 'powershell'
    tool_input = @{
        command = "python3 skills/machina-driving/scripts/machine-driver.py status --run-dir .machina/runs --run run_abc"
    }
    tool_response = @{
        resultType = 'success'
        textResultForLlm = $statusPayload1
    }
} | ConvertTo-Json -Compress -Depth 10

# We need machine.json to be readable from the run dir
# The hook looks for it in: <run-dir>/machine.json, then parent, then cwd
# For testing, create a temp structure
$tempRunDir = Join-Path ([System.IO.Path]::GetTempPath()) ('machina-test-' + [System.IO.Path]::GetRandomFileName())
$tempRunPath = Join-Path $tempRunDir 'run_abc'
New-Item -ItemType Directory -Path $tempRunPath -Force | Out-Null
$machineJson | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $tempRunPath 'machine.json') -Encoding UTF8

# Update payload with temp run dir
$payload1Obj = $payload1 | ConvertFrom-Json
$payload1Obj.tool_input.command = "python3 skills/machina-driving/scripts/machine-driver.py status --run-dir $tempRunDir --run run_abc"
$payload1 = $payload1Obj | ConvertTo-Json -Compress -Depth 10

Assert-Output "Unsatisfied checks => checks_failed category" -PayloadJson $payload1 -ExpectModified $true -ExpectCategory 'checks_failed'

# Cleanup temp dir
Remove-Item -Path $tempRunDir -Recurse -Force -ErrorAction SilentlyContinue

# Test 2: Status with all checks passed → no modification
$statusPayload2 = @{
    ok = $true
    data = @{
        run_id = 'run_def'
        machine_id = 'test-machine'
        state = 'reviewing-draft'
        enabled_events = @(
            @{ event = 'DRAFT_REVIEWED'; target = 'publishing' }
        )
        blocked_events = @()
        checks = @(
            @{ tool = 'file-exists'; passed = $true; exit_code = 0; output = ''; error = $null }
            @{ tool = 'lint-pass'; passed = $true; exit_code = 0; output = 'ok'; error = $null }
        )
        context = @{}
    }
} | ConvertTo-Json -Compress -Depth 10

$tempRunDir2 = Join-Path ([System.IO.Path]::GetTempPath()) ('machina-test-' + [System.IO.Path]::GetRandomFileName())
$tempRunPath2 = Join-Path $tempRunDir2 'run_def'
New-Item -ItemType Directory -Path $tempRunPath2 -Force | Out-Null
$machineJson | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $tempRunPath2 'machine.json') -Encoding UTF8

$payload2 = @{
    tool_name = 'powershell'
    tool_input = @{
        command = "python3 skills/machina-driving/scripts/machine-driver.py status --run-dir $tempRunDir2 --run run_def"
    }
    tool_response = @{
        resultType = 'success'
        textResultForLlm = $statusPayload2
    }
} | ConvertTo-Json -Compress -Depth 10

Assert-Output "All checks passed => no modification" -PayloadJson $payload2 -ExpectModified $false

Remove-Item -Path $tempRunDir2 -Recurse -Force -ErrorAction SilentlyContinue

# Test 3: Status with no checks in state definition → no modification
$machineJsonNoChecks = @{
    id = 'test-machine-nochecks'
    tools = @{}
    states = @{
        'idle' = @{
            on = @{
                'START' = @{ target = 'active' }
            }
        }
    }
} | ConvertTo-Json -Compress -Depth 10

$statusPayload3 = @{
    ok = $true
    data = @{
        run_id = 'run_nochecks'
        machine_id = 'test-machine-nochecks'
        state = 'idle'
        enabled_events = @(
            @{ event = 'START'; target = 'active' }
        )
        blocked_events = @()
        checks = @()
        context = @{}
    }
} | ConvertTo-Json -Compress -Depth 10

$tempRunDir3 = Join-Path ([System.IO.Path]::GetTempPath()) ('machina-test-' + [System.IO.Path]::GetRandomFileName())
$tempRunPath3 = Join-Path $tempRunDir3 'run_nochecks'
New-Item -ItemType Directory -Path $tempRunPath3 -Force | Out-Null
Set-Content -Path (Join-Path $tempRunPath3 'machine.json') -Value $machineJsonNoChecks -Encoding UTF8

$payload3 = @{
    tool_name = 'powershell'
    tool_input = @{
        command = "python3 skills/machina-driving/scripts/machine-driver.py status --run-dir $tempRunDir3 --run run_nochecks"
    }
    tool_response = @{
        resultType = 'success'
        textResultForLlm = $statusPayload3
    }
} | ConvertTo-Json -Compress -Depth 10

Assert-Output "No checks in state => no modification" -PayloadJson $payload3 -ExpectModified $false

Remove-Item -Path $tempRunDir3 -Recurse -Force -ErrorAction SilentlyContinue

# --- CLI format tests ---

Write-Host "`nCLI format (camelCase):" -ForegroundColor Yellow

# Test 4: CLI non-status command → no-op
$payload4 = @{
    toolName = 'bash'
    toolArgs = @{
        command = "python3 skills/machina-driving/scripts/machine-driver.py fire DRAFT_REVIEWED --run-dir .machina/runs"
    }
    toolResult = @{
        resultType = 'success'
        textResultForLlm = '{"ok":true,"data":{"status":"transitioned"}}'
    }
} | ConvertTo-Json -Compress -Depth 10

Assert-Output "Non-status command => no-op" -PayloadJson $payload4 -ExpectModified $false

# Test 5: Malformed JSON on stdin → no crash, no modification
$payload5 = "this is not json {{{"
$tmpFile5 = [System.IO.Path]::GetTempFileName()
try {
    [System.IO.File]::WriteAllText($tmpFile5, $payload5)
    $result5 = Get-Content -Raw -Path $tmpFile5 | pwsh -NoProfile -File $scriptPath 2>$null
    $isModified5 = $result5 -notmatch '^\s*\{\s*\}\s*$'
    if (-not $isModified5) {
        Write-Host "  PASS: Malformed JSON => no crash, no modification" -ForegroundColor Green
        $script:pass++
    }
    else {
        Write-Host "  FAIL: Malformed JSON => should not modify" -ForegroundColor Red
        Write-Host "    Output: $result5" -ForegroundColor Red
        $script:fail++
    }
}
finally {
    Remove-Item -Path $tmpFile5 -Force -ErrorAction SilentlyContinue
}

# --- CLI format additional test ---

Write-Host "`nCLI format additional tests:" -ForegroundColor Yellow

# Test 6: CLI status with unsatisfied checks => checks_failed
$tempRunDir6 = Join-Path ([System.IO.Path]::GetTempPath()) ('machina-test-' + [System.IO.Path]::GetRandomFileName())
$tempRunPath6 = Join-Path $tempRunDir6 'run_cli1'
New-Item -ItemType Directory -Path $tempRunPath6 -Force | Out-Null
$machineJson | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $tempRunPath6 'machine.json') -Encoding UTF8

$statusPayload6 = @{
    ok = $true
    data = @{
        run_id = 'run_cli1'
        machine_id = 'test-machine'
        state = 'reviewing-draft'
        enabled_events = @(
            @{ event = 'DRAFT_REVIEWED'; target = 'publishing' }
        )
        blocked_events = @()
        checks = @(
            @{ tool = 'file-exists'; passed = $false; exit_code = 1; output = 'not found'; error = $null }
            @{ tool = 'lint-pass'; passed = $false; exit_code = 1; output = 'errors'; error = $null }
        )
        context = @{}
    }
} | ConvertTo-Json -Compress -Depth 10

$payload6 = @{
    toolName = 'powershell'
    toolArgs = @{
        command = "python3 skills/machina-driving/scripts/machine-driver.py status --run-dir $tempRunDir6 --run run_cli1"
    }
    toolResult = @{
        resultType = 'success'
        textResultForLlm = $statusPayload6
    }
} | ConvertTo-Json -Compress -Depth 10

Assert-Output "CLI: unsatisfied checks => checks_failed" -PayloadJson $payload6 -ExpectModified $true -ExpectCategory 'checks_failed'

Remove-Item -Path $tempRunDir6 -Recurse -Force -ErrorAction SilentlyContinue

# Test 7: CLI status with checks missing from checkMap => checks_pending
$tempRunDir7 = Join-Path ([System.IO.Path]::GetTempPath()) ('machina-test-' + [System.IO.Path]::GetRandomFileName())
$tempRunPath7 = Join-Path $tempRunDir7 'run_cli2'
New-Item -ItemType Directory -Path $tempRunPath7 -Force | Out-Null
$machineJson | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $tempRunPath7 'machine.json') -Encoding UTF8

# Status output has no check results at all for the required checks
$statusPayload7 = @{
    ok = $true
    data = @{
        run_id = 'run_cli2'
        machine_id = 'test-machine'
        state = 'reviewing-draft'
        enabled_events = @(
            @{ event = 'DRAFT_REVIEWED'; target = 'publishing' }
        )
        blocked_events = @()
        checks = @()
        context = @{}
    }
} | ConvertTo-Json -Compress -Depth 10

$payload7 = @{
    toolName = 'powershell'
    toolArgs = @{
        command = "python3 skills/machina-driving/scripts/machine-driver.py status --run-dir $tempRunDir7 --run run_cli2"
    }
    toolResult = @{
        resultType = 'success'
        textResultForLlm = $statusPayload7
    }
} | ConvertTo-Json -Compress -Depth 10

Assert-Output "CLI: checks missing from results => checks_pending" -PayloadJson $payload7 -ExpectModified $true -ExpectCategory 'checks_pending'

Remove-Item -Path $tempRunDir7 -Recurse -Force -ErrorAction SilentlyContinue

# --- Summary ---

Write-Host "`n=== Results: $pass passed, $fail failed ===" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
