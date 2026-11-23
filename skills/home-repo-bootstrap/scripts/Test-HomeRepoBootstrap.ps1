<#
.SYNOPSIS
  Verify that a folder is a working home repo (the bootstrap's acceptance check).
.DESCRIPTION
  Checks, in order:
    1. layout   - AGENTS.md, docs/coding-standards.md, docs/glossary.md,
                  scripts/local-ci.ps1, .githooks/pre-commit, .gitignore exist
    2. git      - the folder is a repository and core.hooksPath is .githooks
    3. manifest - reports/daily/daily-report.manifest.json parses as schema 1
                  with a valid mode; multi mode lists at least one absolute path
    4. pointers - every "## Other Repos" bullet carries an absolute path and a
                  well-formed clone URL (mirrors scripts/local-ci.ps1)
    5. gate     - scripts/local-ci.ps1 exits 0 against the checkout
    6. skills   - the shared skills the tower depends on resolve on this machine
                  (WARN only: a fresh machine installs them after bootstrapping)

  Anti-drift: the seeded files that must stay byte-identical (scripts/local-ci.ps1,
  .githooks/pre-commit) are compared against a published assets/ folder when
  -SeedSource points at one, so the reference machine never gates differently
  from the copy a teammate bootstraps.

  Emits one JSON object on stdout: {path, passed, checks:[{name,status,detail}],
  warnings}. Exit 0 when no check fails; exit 1 otherwise. -SkipGate omits the
  local-CI run, for machines without pwsh.
.PARAMETER Path
  Home-repo root to verify.
.PARAMETER SkipGate
  Do not run scripts/local-ci.ps1.
.PARAMETER SeedSource
  Path to a home-repo-bootstrap skill's assets/ folder. When supplied, the
  seeded files that must stay byte-identical (scripts/local-ci.ps1,
  .githooks/pre-commit) are compared against it and a mismatch is reported as
  drift. Omit it and the drift check is skipped.
.EXAMPLE
  ./Test-HomeRepoBootstrap.ps1 -Path C:\Work\home-repo
.EXAMPLE
  ./Test-HomeRepoBootstrap.ps1 -Path C:\Work\home-repo -SeedSource ~/.agents/skills/home-repo-bootstrap/assets
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [switch]$SkipGate,

    [string]$SeedSource
)

$ErrorActionPreference = 'Stop'

$root = $Path
if (-not [System.IO.Path]::IsPathRooted($root)) {
    Write-Error "home-repo-bootstrap: Path '$Path' must be an absolute path."
    exit 1
}
$root = $root.TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    Write-Error "home-repo-bootstrap: '$root' does not exist."
    exit 1
}

$checks = [System.Collections.Generic.List[object]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

function Add-Check {
    param([string]$Name, [string]$Status, [string]$Detail)
    $checks.Add([ordered]@{ name = $Name; status = $Status; detail = $Detail })
}

# --- 1. layout ------------------------------------------------------------
$required = @(
    'AGENTS.md',
    'docs/coding-standards.md',
    'docs/glossary.md',
    'scripts/local-ci.ps1',
    '.githooks/pre-commit',
    '.gitignore'
)
$missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $root ($_ -replace '/', [System.IO.Path]::DirectorySeparatorChar))) })
if ($missing.Count -eq 0) {
    Add-Check 'layout' 'pass' "$($required.Count) seeded file(s) present"
}
else {
    Add-Check 'layout' 'fail' "missing: $($missing -join ', ')"
}

# --- 2. git ---------------------------------------------------------------
$top = (& git -C $root rev-parse --show-toplevel 2>$null)
if (-not $top) {
    Add-Check 'git' 'fail' 'not a git repository'
}
else {
    $hooksPath = (& git -C $root config --get core.hooksPath 2>$null)
    $hooksPath = if ($hooksPath) { "$hooksPath".Trim() } else { '' }
    if ($hooksPath -eq '.githooks') {
        Add-Check 'git' 'pass' 'repository with core.hooksPath=.githooks'
    }
    else {
        Add-Check 'git' 'fail' "core.hooksPath is '$hooksPath'; run: git config core.hooksPath .githooks"
    }
}

# --- 3. manifest ----------------------------------------------------------
$manifestRel = 'reports/daily/daily-report.manifest.json'
$manifestPath = Join-Path $root 'reports\daily\daily-report.manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    Add-Check 'manifest' 'fail' "missing $manifestRel (re-run the initializer with -WatchedRepo or manually)"
}
else {
    try {
        $m = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $problems = @()
        if ($null -eq $m.schema -or "$($m.schema)" -ne '1') { $problems += "schema must be 1" }
        $mode = "$($m.mode)"
        if ($mode -notin @('single', 'multi')) {
            $problems += "mode must be single or multi, got '$mode'"
        }
        elseif ($mode -eq 'multi') {
            $repos = @($m.repos)
            if ($repos.Count -eq 0) { $problems += 'multi mode needs at least one repos path' }
            foreach ($r in $repos) {
                if ($r -isnot [string] -or -not [System.IO.Path]::IsPathRooted($r)) {
                    $problems += "repos entry '$r' is not an absolute path"
                }
            }
        }
        if ($problems.Count -eq 0) {
            Add-Check 'manifest' 'pass' "schema 1, mode $mode"
        }
        else {
            Add-Check 'manifest' 'fail' ($problems -join '; ')
        }
    }
    catch {
        Add-Check 'manifest' 'fail' "invalid JSON: $($_.Exception.Message)"
    }
}

# --- 4. pointers ----------------------------------------------------------
$agentsPath = Join-Path $root 'AGENTS.md'
$bulletCount = 0
if (-not (Test-Path -LiteralPath $agentsPath)) {
    Add-Check 'pointers' 'fail' 'AGENTS.md missing'
}
else {
    $inSection = $false
    $bullet = ''
    $bullets = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @(Get-Content -LiteralPath $agentsPath)) {
        if ($line -match '^##\s') {
            if ($inSection -and $bullet) { $bullets.Add($bullet); $bullet = '' }
            $inSection = $line -match '^##\s+Other Repos\s*$'
            continue
        }
        if (-not $inSection) { continue }
        if ($line -match '^\s*-\s+') {
            if ($bullet) { $bullets.Add($bullet) }
            $bullet = $line
        }
        elseif ($bullet -and $line -match '^\s+\S') { $bullet += ' ' + $line.Trim() }
        elseif ($bullet) { $bullets.Add($bullet); $bullet = '' }
    }
    if ($inSection -and $bullet) { $bullets.Add($bullet) }

    $bulletCount = $bullets.Count
    $problems = @()
    if ($bulletCount -eq 0) { $problems += 'no pointer bullets under "## Other Repos"' }
    $missingPaths = 0
    foreach ($b in $bullets) {
        $paths = @([regex]::Matches($b, '(?<![:/A-Za-z0-9_])((?:[A-Za-z]:[\\/]|/)[^\s]+)') |
            ForEach-Object { $_.Groups[1].Value.TrimEnd('.', ',', ';', ')') })
        $urls = @([regex]::Matches($b, 'Clone from\s+(\S+)') |
            ForEach-Object { $_.Groups[1].Value.TrimEnd('.', ',', ';', ')') })
        if ($paths.Count -eq 0) { $problems += "bullet without a local path: $($b.Substring(0, [Math]::Min(60, $b.Length)))" }
        if ($urls.Count -eq 0) { $problems += "bullet without a clone URL: $($b.Substring(0, [Math]::Min(60, $b.Length)))" }
        foreach ($u in $urls) {
            if ($u -notmatch '^(https?://|git@|ssh://|git://)') { $problems += "malformed clone URL: $u" }
        }
        foreach ($p in $paths) {
            if (-not (Test-Path -LiteralPath $p)) { $missingPaths++ }
        }
    }
    if ($missingPaths -gt 0) { $warnings.Add("$missingPaths pointer path(s) absent on this machine (clone if missing)") }
    if ($problems.Count -eq 0) {
        Add-Check 'pointers' 'pass' "$bulletCount bullet(s) carry a path and a clone URL"
    }
    else {
        Add-Check 'pointers' 'fail' ($problems -join '; ')
    }
}

# --- 5. gate --------------------------------------------------------------
if ($SkipGate) {
    Add-Check 'gate' 'skip' 'the local CI run was skipped on request'
}
elseif (-not (Test-Path -LiteralPath (Join-Path $root 'scripts\local-ci.ps1'))) {
    Add-Check 'gate' 'fail' 'scripts/local-ci.ps1 missing'
}
else {
    $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)
    if (-not $pwsh) {
        Add-Check 'gate' 'fail' 'pwsh not found on PATH; the pre-commit hook would skip validation'
    }
    else {
        $out = & pwsh -NoProfile -File (Join-Path $root 'scripts\local-ci.ps1') 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            $summary = @($out -split "`n" | Where-Object { $_ -match 'local-ci: (PASS|WARN)' } | Select-Object -First 2) -join ' | '
            Add-Check 'gate' 'pass' ($summary.Trim() -replace '\s+', ' ')
        }
        else {
            Add-Check 'gate' 'fail' (($out.Trim() -split "`n" | Select-Object -Last 3) -join ' | ')
        }
    }
}

# --- 6. shared skills -----------------------------------------------------
# $env:USERPROFILE is unset on Linux and macOS; fall back to the OS home so the
# check reports honestly on every platform the factory gate runs on.
$homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$skillStore = Join-Path (Join-Path (Join-Path $homeDir '.agents') 'skills') '.'
$needed = @('daily-report')
$absent = @($needed | Where-Object { -not (Test-Path -LiteralPath (Join-Path $skillStore "$_\SKILL.md")) })
if ($absent.Count -eq 0) {
    Add-Check 'skills' 'pass' "shared skills resolve in $skillStore"
}
else {
    Add-Check 'skills' 'warn' "not installed yet in ${skillStore}: $($absent -join ', ') - run: npx skills add arisng/github-copilot-fc -s $($absent[0]) -g -y"
}

# --- 7. seed drift --------------------------------------------------------
# A home repo that fixes a seeded file without the factory's asset learning the
# same fix diverges silently: the reference machine gates worse than the copy
# every teammate receives. Compare the files that must stay identical.
if ($SeedSource) {
    $pinned = [ordered]@{
        'scripts/local-ci.ps1' = 'local-ci.ps1'
        '.githooks/pre-commit' = 'pre-commit.template'
    }
    if (-not (Test-Path -LiteralPath $SeedSource -PathType Container)) {
        Add-Check 'drift' 'fail' "SeedSource '$SeedSource' does not exist"
    }
    else {
        $drifted = [System.Collections.Generic.List[string]]::new()
        $compared = 0
        foreach ($localRel in $pinned.Keys) {
            $assetPath = Join-Path $SeedSource $pinned[$localRel]
            $localPath = Join-Path $root ($localRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path -LiteralPath $assetPath) -or -not (Test-Path -LiteralPath $localPath)) { continue }
            $compared++
            $a = (Get-Content -LiteralPath $localPath -Raw) -replace "`r`n", "`n"
            $b = (Get-Content -LiteralPath $assetPath -Raw) -replace "`r`n", "`n"
            if ($a.TrimEnd() -ne $b.TrimEnd()) { $drifted.Add($localRel) }
        }
        if ($compared -eq 0) {
            Add-Check 'drift' 'skip' 'no comparable seeded file found on both sides'
        }
        elseif ($drifted.Count -eq 0) {
            Add-Check 'drift' 'pass' "$compared seeded file(s) match the published assets"
        }
        else {
            Add-Check 'drift' 'fail' "drifted from the published seed: $($drifted -join ', ') - port the fix to skills/home-repo-bootstrap/assets/ and re-sync, so every bootstrapped machine gets it too"
        }
    }
}

$failed = @($checks | Where-Object { $_.status -eq 'fail' })
[ordered]@{
    path     = $root
    passed   = ($failed.Count -eq 0)
    checks   = @($checks)
    warnings = @($warnings)
} | ConvertTo-Json -Depth 6

if ($failed.Count -gt 0) { exit 1 }
exit 0
