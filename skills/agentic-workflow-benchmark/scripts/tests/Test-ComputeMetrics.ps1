<#
.SYNOPSIS
    Smoke test for compute_metrics.py against the synthetic fixture.

.DESCRIPTION
    Runs the metrics engine over fixture-events.jsonl and asserts the expected
    four-goal metric families. Exits 0 on pass, 1 on any failed assertion.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$testsDir = $PSScriptRoot
$scriptDir = Split-Path $testsDir -Parent
$compute = Join-Path $scriptDir 'compute_metrics.py'
$fixture = Join-Path $testsDir 'fixture-events.jsonl'
$outDir = Join-Path ([System.IO.Path]::GetTempPath()) ("awb-test-" + [guid]::NewGuid().ToString('N'))

$failures = @()
function Assert-Equal($actual, $expected, $label) {
    if ($actual -ne $expected) {
        $script:failures += "$label : expected '$expected', got '$actual'"
    }
}

try {
    $python = if (Get-Command py -ErrorAction SilentlyContinue) { @('py', '-3') }
              elseif (Get-Command python3 -ErrorAction SilentlyContinue) { @('python3') }
              else { @('python') }
    $pyPrefix = @($python | Select-Object -Skip 1)

    & $python[0] @($pyPrefix + @(
        $compute, '--events', $fixture, '--skill', 'demo-skill',
        '--out-dir', $outDir, '--session-dir', 'fixture-session', '--set-baseline'
    )) | Out-Null
    Assert-Equal $LASTEXITCODE 0 'engine exit code'

    $latest = Get-Content (Join-Path $outDir 'latest.json') -Raw | ConvertFrom-Json

    # Tokens: 6000 in + 600 out + 350 cache_read + 60 cache_write = 7010
    Assert-Equal $latest.tokens.total 7010 'tokens.total'
    Assert-Equal $latest.tokens.input 6000 'tokens.input'
    # Post-boundary usage (9999+) must be excluded
    if ($latest.tokens.input -ge 9999) { $failures += 'post-boundary usage leaked into window' }

    # Sub-agent broken out
    Assert-Equal $latest.sub_agent_tokens.total 3530 'sub_agent_tokens.total'

    # Time: wall 299500 ms (12:00:00.500 -> 12:05:00.000), ask_user wait 12000
    Assert-Equal $latest.time.wall_clock_ms 299500 'time.wall_clock_ms'
    Assert-Equal $latest.time.active_ms 287500 'time.active_ms'

    # Steps: deterministic 1 (pwsh script), semantic 2 (edit, task),
    # query_read 1 (grep), workflow_control 1 (ask_user), uncertain 1 (ad-hoc shell)
    Assert-Equal $latest.steps.deterministic 1 'steps.deterministic'
    Assert-Equal $latest.steps.semantic 2 'steps.semantic'
    Assert-Equal $latest.steps.query_read 1 'steps.query_read'
    Assert-Equal $latest.steps.workflow_control 1 'steps.workflow_control'
    Assert-Equal $latest.steps.uncertain 1 'steps.uncertain'
    Assert-Equal $latest.steps.total 6 'steps.total'

    # Ratios
    Assert-Equal $latest.ratios.decision_points 3 'ratios.decision_points'
    Assert-Equal $latest.ratios.tokens_per_semantic_step 3505 'ratios.tokens_per_semantic_step'
    if ([math]::Abs($latest.ratios.deterministic_ratio - 0.1667) -gt 0.0001) {
        $failures += "ratios.deterministic_ratio : expected ~0.1667, got $($latest.ratios.deterministic_ratio)"
    }

    # Durable artifacts exist
    Assert-Equal (Test-Path (Join-Path $outDir 'baseline.json')) $true 'baseline.json exists'
    $reports = Get-ChildItem $outDir -Filter '*-report.md'
    Assert-Equal $reports.Count 1 'dated report written'

    # Second run against baseline: trend rows must exist and be non-empty
    & $python[0] @($pyPrefix + @(
        $compute, '--events', $fixture, '--skill', 'demo-skill', '--out-dir', $outDir
    )) | Out-Null
    Assert-Equal $LASTEXITCODE 0 'second run exit code'
    $report2 = Get-Content (Get-ChildItem $outDir -Filter '*-report.md' | Sort-Object Name | Select-Object -Last 1) -Raw
    if ($report2 -notmatch 'Minimize LLM token usage') { $failures += 'report missing goal scorecard' }
    if ($report2 -notmatch 'unchanged') { $failures += 'baseline delta trend missing for identical rerun' }
}
finally {
    if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
}

if ($failures.Count) {
    Write-Host "FAIL ($($failures.Count)):" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host 'PASS: all assertions held.' -ForegroundColor Green
exit 0
