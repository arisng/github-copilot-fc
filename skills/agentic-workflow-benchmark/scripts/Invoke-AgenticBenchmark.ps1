<#
.SYNOPSIS
    Benchmark an agentic skill-execution episode from a Copilot session's events.jsonl.

.DESCRIPTION
    Orchestrator for compute_metrics.py: resolves the session events file, runs the
    pre-flight + metric computation, and places durable artifacts (dated report,
    latest.json, baseline.json) in the target skill's benchmarks folder.

    Report location (per skill type):
      - repo-level skill  -> <repo>/skills/<skill>/benchmarks/
      - user-level skill  -> <repo>/benchmarks/<skill>/

.EXAMPLE
    pwsh -NoProfile -File Invoke-AgenticBenchmark.ps1 -SessionDir $env:USERPROFILE\.copilot\session-state\<uuid> -SkillName my-skill
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SkillName,

    [string]$SessionDir,

    [string]$EventsPath,

    [string]$OutDir,

    [string]$RepoRoot = (Get-Location).Path,

    [int]$Episode = -1,

    [switch]$SetBaseline
)

$ErrorActionPreference = 'Stop'

if (-not $EventsPath) {
    if (-not $SessionDir) {
        # Default: most recently modified session dir in the current Copilot home
        $copilotHome = if ($env:COPILOT_HOME) { $env:COPILOT_HOME } else { Join-Path $env:USERPROFILE '.copilot' }
        $stateRoot = Join-Path $copilotHome 'session-state'
        if (-not (Test-Path $stateRoot)) {
            throw "SessionDir not provided and no session-state found at $stateRoot"
        }
        $SessionDir = Get-ChildItem $stateRoot -Directory |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1 -ExpandProperty FullName
        Write-Verbose "Auto-selected most recent session dir: $SessionDir"
    }
    if (-not $SessionDir -or -not (Test-Path $SessionDir)) {
        throw "SessionDir '$SessionDir' does not exist. Pass -SessionDir or -EventsPath explicitly."
    }
    $EventsPath = Join-Path $SessionDir 'events.jsonl'
}

# Pre-flight telemetry check: fail loudly, never silently degrade
if (-not (Test-Path $EventsPath)) {
    Write-Error ("Pre-flight failed: events file not found at '$EventsPath'. " +
        "This session has no local telemetry; cannot benchmark. " +
        "Pass -EventsPath explicitly or pick a session with events.jsonl.")
    exit 2
}

# Resolve report location scoped to the target skill
if (-not $OutDir) {
    $repoSkillDir = Join-Path $RepoRoot "skills\$SkillName"
    if (Test-Path $repoSkillDir) {
        $OutDir = Join-Path $repoSkillDir 'benchmarks'
    }
    else {
        $OutDir = Join-Path $RepoRoot "benchmarks\$SkillName"
    }
}

$scriptDir = $PSScriptRoot
$computeScript = Join-Path $scriptDir 'compute_metrics.py'

# Locate a working Python
$python = $null
foreach ($candidate in @('py', 'python3', 'python')) {
    $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($cmd) { $python = $candidate; break }
}
if (-not $python) { throw 'No Python interpreter found (tried py, python3, python).' }

$pyArgs = @()
if ($python -eq 'py') { $pyArgs += '-3' }
$pyArgs += @(
    $computeScript,
    '--events', $EventsPath,
    '--skill', $SkillName,
    '--out-dir', $OutDir,
    '--episode', "$Episode"
)
if ($SessionDir) { $pyArgs += @('--session-dir', $SessionDir) }
if ($SetBaseline) { $pyArgs += '--set-baseline' }

Write-Verbose "Running: $python $($pyArgs -join ' ')"
& $python @pyArgs
exit $LASTEXITCODE
