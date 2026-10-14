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

    # --- Skill-chain + subagent attribution (orch-skill scenario) ---
    $orchDir = Join-Path $outDir 'orch'
    & $python[0] @($pyPrefix + @(
        $compute, '--events', $fixture, '--skill', 'orch-skill', '--out-dir', $orchDir,
        '--session-dir', 'fixture-session', '--set-baseline'
    )) | Out-Null
    Assert-Equal $LASTEXITCODE 0 'orch-skill run exit code'
    $orch = Get-Content (Join-Path $orchDir 'latest.json') -Raw | ConvertFrom-Json

    # Episode spans past machina-driving (declarative chain), dotnet-inspect
    # (subagent-internal) and helper-skill (120s+naming heuristic); ends at
    # the benchmark's own activation: 12:10:00 -> 12:11:10 = 70000 ms
    Assert-Equal $orch.episode.wall_clock_ms 70000 'orch episode wall_clock_ms'
    # 6 steps: task (det), git status (query_read), python -c (semantic),
    # grep (query_read), dotnet build (det), view (query_read)
    Assert-Equal $orch.steps.deterministic 2 'orch steps.deterministic'
    Assert-Equal $orch.steps.semantic 1 'orch steps.semantic'
    Assert-Equal $orch.steps.query_read 3 'orch steps.query_read'
    Assert-Equal $orch.steps.total 6 'orch steps.total'
    # tokens: 1160 + 550 + 770 sub-agent = 2480; sub-agent broken out
    Assert-Equal $orch.tokens.total 2480 'orch tokens.total'
    Assert-Equal $orch.sub_agent_tokens.total 770 'orch sub_agent_tokens.total'
    # Three merged boundaries: chain, subagent, chain-heuristic
    Assert-Equal $orch.episode.boundaries.Count 3 'orch boundary count'
    Assert-Equal $orch.episode.boundaries[0].skill 'machina-driving' 'boundary 1 skill'
    Assert-Equal $orch.episode.boundaries[0].subagent $false 'boundary 1 not subagent'
    Assert-Equal $orch.episode.boundaries[0].tokens 550 'boundary 1 tokens'
    Assert-Equal $orch.episode.boundaries[1].skill 'dotnet-inspect' 'boundary 2 skill'
    Assert-Equal $orch.episode.boundaries[1].subagent $true 'boundary 2 subagent'
    Assert-Equal $orch.episode.boundaries[1].tokens 770 'boundary 2 tokens'
    Assert-Equal $orch.episode.boundaries[2].skill 'helper-skill' 'boundary 3 skill'
    Assert-Equal $orch.degenerate.is_degenerate $false 'orch not degenerate'

    # --- Degenerate-episode guard (degen-skill: 1 tool step) ---
    $degenDir = Join-Path $outDir 'degen'
    & $python[0] @($pyPrefix + @(
        $compute, '--events', $fixture, '--skill', 'degen-skill', '--out-dir', $degenDir,
        '--session-dir', 'fixture-session'
    )) | Out-Null
    Assert-Equal $LASTEXITCODE 0 'degen run exit code'
    $degenLatest = Get-Content (Join-Path $degenDir 'latest.json') -Raw | ConvertFrom-Json
    Assert-Equal $degenLatest.degenerate.is_degenerate $true 'degen flagged'
    Assert-Equal (Test-Path (Join-Path $degenDir 'baseline.json')) $false 'degen baseline refused'
    $degenReport = Get-Content (Get-ChildItem $degenDir -Filter '*-report.md' | Select-Object -First 1) -Raw
    if ($degenReport -notmatch 'DEGENERATE EPISODE') { $failures += 'degenerate caveat missing from report' }
    # Explicit --set-baseline forces the write
    & $python[0] @($pyPrefix + @(
        $compute, '--events', $fixture, '--skill', 'degen-skill', '--out-dir', $degenDir,
        '--session-dir', 'fixture-session', '--set-baseline'
    )) | Out-Null
    Assert-Equal (Test-Path (Join-Path $degenDir 'baseline.json')) $true 'degen baseline written when forced'

    # --- Session-aggregate mode ---
    $sessDir = Join-Path $outDir 'session'
    & $python[0] @($pyPrefix + @(
        $compute, '--events', $fixture, '--skill', 'demo-skill', '--out-dir', $sessDir,
        '--session-dir', 'fixture-session', '--mode', 'session', '--set-baseline'
    )) | Out-Null
    Assert-Equal $LASTEXITCODE 0 'session mode exit code'
    $sess = Get-Content (Join-Path $sessDir 'latest.session.json') -Raw | ConvertFrom-Json
    # Whole-session window (12:00:00 -> 12:30:00 benchmark activation):
    # tokens 7010 + 10998 + 1160 + 550 + 770 = 20488
    Assert-Equal $sess.tokens.total 20488 'session tokens.total'
    Assert-Equal $sess.steps.total 13 'session steps.total'
    # deterministic: pwsh script + task + dotnet build = 3; ratio 3/13
    Assert-Equal $sess.steps.deterministic 3 'session steps.deterministic'
    if ([math]::Abs($sess.ratios.deterministic_ratio - 0.2308) -gt 0.0001) {
        $failures += "session deterministic_ratio : expected ~0.2308, got $($sess.ratios.deterministic_ratio)"
    }
    # 6 mechanical breakdown rows (demo, orch, machina-driving, dotnet-inspect, helper, degen)
    Assert-Equal $sess.episode_breakdown.Count 6 'session breakdown rows'
    # Mode-separated baselines: session run must not touch episode baseline files
    Assert-Equal (Test-Path (Join-Path $sessDir 'baseline.session.json')) $true 'baseline.session.json written'
    Assert-Equal (Test-Path (Join-Path $sessDir 'baseline.json')) $false 'episode baseline untouched in session mode'
    Assert-Equal $sess.mode 'session' 'session mode field'

    # --- Wrapper classification fixture ---
    # Repo helper invocations must classify deterministic (provenance), while the
    # ad-hoc shapes they replace stay uncertain — guarding both the wrapper-only
    # rule and the anti-gaming intent of the taxonomy.
    $classifySrc = @'
import importlib.util, sys

spec = importlib.util.spec_from_file_location("cm", sys.argv[1])
cm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cm)

cases = [
    # repo helper invocations -> deterministic (pre-authored .ps1 / task / gh)
    ("./scripts/git/Get-WorktreeContent.ps1 -Action Search -Pattern 'SessionInlineFileViewer' -Path src", "deterministic"),
    ("pwsh scripts/testing/Invoke-BrowserQaProbe.ps1 -Url https://localhost:62021/sessions -Steps @('wait:4000','shot:a.png')", "deterministic"),
    ("./scripts/workflow/Get-SessionRunState.ps1 -Action RunState -RunId 4cbfda30812d", "deterministic"),
    ("./scripts/dev/Inspect-PackageAsset.ps1 -Package blazorblueprint.components -Action Match -Pattern '\\.fixed\\{'", "deterministic"),
    ("Set-Location 'C:\\wt'; task ax:build:fast", "deterministic"),
    ("gh issue comment 953 --repo owner/repo --body-file body.md", "deterministic"),
    # the ad-hoc shapes these replace -> still uncertain (direct calls stay honest)
    ("playwright-cli goto \"https://localhost:62021/sessions\"", "uncertain"),
    ("playwright-cli click \"[data-testid=session-file-fullscreen-open]\"", "uncertain"),
    ("$wt = 'C:\\wt'; Get-ChildItem $wt -Recurse", "uncertain"),
    ("$dir = 'C:\\sess\\files\\x\\evidence\\qa\\media'; New-Item -ItemType Directory -Path $dir -Force", "uncertain"),
    ("curl.exe -s \"https://example.com/asset.css\"", "uncertain"),
    # structured read-only git query -> decision point, not deterministic
    ("git status --short", "query_read"),
    # known taxonomy gap (out of scope): a -C path between `git` and the
    # subcommand defeats the read-only-git pattern, so this lands uncertain today
    ("git -C C:\\repo status --short", "uncertain"),
]

failures = 0
for command, expected in cases:
    got = cm.classify_step("powershell", {"command": command})
    ok = got == expected
    if not ok:
        failures += 1
    print(("ok       " if ok else "MISMATCH ") + f"expected={expected:14} got={got:14} :: {command[:90]}")
sys.exit(1 if failures else 0)
'@
    $classifySrc | & $python[0] @($pyPrefix + @('-', $compute))
    Assert-Equal $LASTEXITCODE 0 'wrapper classification fixture'
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
