<#
.SYNOPSIS
    Audit an agentic skill-execution episode from a Copilot session's events.jsonl.

.DESCRIPTION
    Orchestrator for compute_metrics.py: resolves the session events file, runs the
    pre-flight + metric computation, and writes the durable telemetry artifact — the
    dated report — into the target skill's telemetry folder.

    Artifact location (per skill type; an existing legacy 'benchmarks' folder is
    reused when no 'telemetry' folder exists yet):
      - repo-level skill  -> <repo>/skills/<skill>/telemetry/ or <repo>/.github/skills/<skill>/telemetry/
      - user-level skill  -> <repo>/telemetry/<skill>/

.EXAMPLE
    pwsh -NoProfile -File Invoke-SessionTelemetry.ps1 -SessionDir $env:USERPROFILE\.copilot\session-state\<uuid> -SkillName my-skill
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

    [ValidateSet('episode', 'session')]
    [string]$Mode = 'episode'
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
        "This session has no local telemetry; cannot audit. " +
        "Pass -EventsPath explicitly or pick a session with events.jsonl.")
    exit 2
}

# Resolve artifact location scoped to the target skill.
# 'telemetry' is the current folder name; an existing legacy 'benchmarks'
# folder is reused (with a warning) so stored baselines keep their history.
function Resolve-ArtifactFolderName([string]$BaseDir) {
    if (Test-Path (Join-Path $BaseDir 'telemetry')) { return 'telemetry' }
    if (Test-Path (Join-Path $BaseDir 'benchmarks')) {
        Write-Warning "Using legacy 'benchmarks' folder under $BaseDir - rename it to 'telemetry' when convenient."
        return 'benchmarks'
    }
    return 'telemetry'
}

if (-not $OutDir) {
    $repoSkillDir = Join-Path $RepoRoot "skills\$SkillName"
    $ghSkillDir = Join-Path $RepoRoot ".github\skills\$SkillName"
    if (Test-Path $repoSkillDir) {
        $OutDir = Join-Path $repoSkillDir (Resolve-ArtifactFolderName $repoSkillDir)
    }
    elseif (Test-Path $ghSkillDir) {
        $OutDir = Join-Path $ghSkillDir (Resolve-ArtifactFolderName $ghSkillDir)
    }
    else {
        $OutDir = Join-Path $RepoRoot (Join-Path (Resolve-ArtifactFolderName $RepoRoot) $SkillName)
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
    '--episode', "$Episode",
    '--mode', $Mode
)
if ($SessionDir) { $pyArgs += @('--session-dir', $SessionDir) }

Write-Verbose "Running: $python $($pyArgs -join ' ')"
& $python @pyArgs
exit $LASTEXITCODE
