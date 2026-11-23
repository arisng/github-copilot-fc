<#
.SYNOPSIS
  Local CI for a home repo: the only build gate, no cloud CI.
.DESCRIPTION
  -Staged validates exactly the report and glossary content staged for commit
  and refuses when a staged file is stale against the working tree, so the
  validated bytes are the committed bytes. Default mode validates every
  tracked report for a full local run. Validation is Test-DailyReport.ps1
  from the daily-report skill, always with the report's session-coverage
  receipt (sessions/<yymmdd>/coverage.json) - a report without a complete
  receipt, or with a missed in-scope session or missing transcript, fails
  hard. A glossary change revalidates every report beside it, because
  report-to-canonical consistency binds them. A commit that touches neither
  reports nor glossary passes without a validator run, so a freshly
  bootstrapped home repo (no reports yet) never needs the skill installed.

  Every run also checks the AGENTS.md "Other Repos" pointers: each bullet
  must carry a local path and a well-formed "Clone from" URL - either half
  missing or a malformed URL fails the build, while a path absent on this
  machine only warns (paths are machine-specific; clone if missing).
.EXAMPLE
  pwsh -NoProfile -File scripts/local-ci.ps1
.EXAMPLE
  pwsh -NoProfile -File scripts/local-ci.ps1 -Staged
#>
param([switch]$Staged)

$ErrorActionPreference = 'Stop'

# Resolve the checkout from this script's own location, not the caller's
# working directory: invoking the gate from another repo must never validate
# the wrong tree.
$repoRoot = Split-Path -Parent $PSScriptRoot
$top = & git -C $repoRoot rev-parse --show-toplevel 2>$null
if (-not $top) { Write-Error "local-ci: '$repoRoot' is not inside a git repository."; exit 1 }
$repoRoot = "$top".Trim()

$reportRe = '^reports/daily/[^/]+/\d{6}\.md$'
$glossRe = '^reports/daily/[^/]+/glossary\.md$'

# --- AGENTS.md pointer check (runs on every invocation) -------------------
# Each bullet under "## Other Repos" must carry an absolute local path and a
# well-formed clone URL; a path absent on this machine only warns, because
# committed paths reflect one machine and the fallback is "clone if missing".
# Wrapped bullets are joined before parsing.
$agentsRel = 'AGENTS.md'
$agentsPath = Join-Path $repoRoot $agentsRel
$pointerProblems = @()
$pointerWarnings = @()
$bullets = [System.Collections.Generic.List[string]]::new()
if (Test-Path $agentsPath) {
    if ($Staged -and
        @(& git -C $repoRoot diff --cached --name-only -- $agentsRel).Count -gt 0 -and
        @(& git -C $repoRoot diff --name-only -- $agentsRel).Count -gt 0) {
        Write-Output "local-ci: FAIL $agentsRel - staged copy is stale against the working tree; stage it again."
        exit 1
    }

    $inSection = $false
    $bullet = ''
    foreach ($line in @(Get-Content $agentsPath)) {
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

    if ($bullets.Count -eq 0) {
        $pointerProblems += 'no pointer bullets found under "## Other Repos"'
    }
    foreach ($b in $bullets) {
        $paths = @([regex]::Matches($b, '(?<![A-Za-z0-9_])([A-Za-z]:\\[^\s]+)') |
            ForEach-Object { $_.Groups[1].Value.TrimEnd('.', ',', ';', ')') })
        $urls = @([regex]::Matches($b, 'Clone from\s+(\S+)') |
            ForEach-Object { $_.Groups[1].Value.TrimEnd('.', ',', ';', ')') })
        if ($paths.Count -eq 0) {
            $pointerProblems += "pointer bullet has no local path: $($b.Substring(0, [Math]::Min(80, $b.Length)))"
        }
        if ($urls.Count -eq 0) {
            $pointerProblems += "pointer bullet has no 'Clone from' URL: $($b.Substring(0, [Math]::Min(80, $b.Length)))"
        }
        foreach ($u in $urls) {
            if ($u -notmatch '^(https?://|git@|ssh://|git://)') {
                $pointerProblems += "malformed clone URL: $u"
            }
        }
        foreach ($p in $paths) {
            if (-not (Test-Path $p)) { $pointerWarnings += "path missing on this machine (clone if missing): $p" }
        }
    }
}
foreach ($w in $pointerWarnings) { Write-Output "local-ci: WARN $w" }
if ($pointerProblems.Count -gt 0) {
    foreach ($p in $pointerProblems) { Write-Output "local-ci: FAIL $agentsRel - $p" }
    exit 1
}
if (Test-Path $agentsPath) {
    Write-Output "local-ci: PASS $agentsRel pointers ($($bullets.Count) checked)"
}
# --- end AGENTS.md pointer check ------------------------------------------

if ($Staged) {
    $changed = @(& git -C $repoRoot diff --cached --name-only)
}
else {
    $changed = @(& git -C $repoRoot ls-files 'reports/daily')
}
$reports = @($changed | Where-Object { $_ -match $reportRe })
$glossFiles = @($changed | Where-Object { $_ -match $glossRe })

# Staged bytes must equal working-tree bytes: the validator reads the working
# tree, so a stale stage would commit content nobody validated.
if ($Staged) {
    foreach ($f in @($reports) + $glossFiles) {
        if (@(& git -C $repoRoot diff --name-only -- $f)) {
            Write-Output "local-ci: FAIL $f - staged copy is stale against the working tree; stage it again."
            exit 1
        }
    }
}

$targets = @{}
foreach ($r in $reports) { $targets[$r] = $true }
foreach ($g in $glossFiles) {
    $user = ($g -split '/')[2]
    $dir = Join-Path $repoRoot "reports/daily/$user"
    Get-ChildItem $dir -Filter '*.md' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{6}\.md$' } |
        ForEach-Object { $targets[('reports/daily/{0}/{1}' -f $user, $_.Name)] = $true }
}

if ($targets.Count -eq 0) {
    Write-Output 'local-ci: PASS (no report or glossary changes)'
    exit 0
}

# Resolve the validator only when there is something to validate: a fresh home
# repo must gate green before the daily-report skill is installed.
$skillHome = if ($env:DAILY_REPORT_SKILL_DIR) { $env:DAILY_REPORT_SKILL_DIR } else { Join-Path $env:USERPROFILE '.agents\skills\daily-report' }
$tester = Join-Path $skillHome 'scripts\Test-DailyReport.ps1'
if (-not (Test-Path $tester)) {
    Write-Error "local-ci: $($targets.Count) report target(s) but the daily-report skill is missing at '$skillHome'. Install it (npx skills add arisng/github-copilot-fc -s daily-report -g -y) or set DAILY_REPORT_SKILL_DIR."
    exit 1
}

$failed = 0
foreach ($rel in ($targets.Keys | Sort-Object)) {
    $m = [regex]::Match($rel, '^reports/daily/([^/]+)/(\d{6})\.md$')
    $user = $m.Groups[1].Value
    $code = $m.Groups[2].Value
    $date = "20$($code.Substring(0, 2))-$($code.Substring(2, 2))-$($code.Substring(4, 2))"
    $file = Join-Path $repoRoot ($rel -replace '/', '\')
    $cov = Join-Path (Split-Path $file -Parent) "sessions\$code\coverage.json"
    $out = & $tester -ReportPath $file -RepoRoot $repoRoot -GitUser $user -Date $date -CoverageJson $cov 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        Write-Output "local-ci: PASS $rel"
    }
    else {
        $failed++
        Write-Output "local-ci: FAIL $rel"
        Write-Output $out
    }
}
if ($failed -gt 0) {
    Write-Output "local-ci: $($failed) report(s) failed validation."
    exit 1
}
Write-Output "local-ci: PASS $($targets.Count) report(s)."
exit 0
