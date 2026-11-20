<#
.SYNOPSIS
  Batch backfill driver for the daily-report skill.
.DESCRIPTION
  Enumerates an inclusive date range and loops the per-day path: one day
  per iteration, same grounding, same template, same validation. The
  manifest decides the repository set: in multi mode every existing
  watched repo gets its own evidence per day, in single mode (or with no
  manifest) only -RepoRoot does. Policy
  for days whose report already exists: skip (default, never clobbers) or
  regenerate (-Regenerate). Isolation: a failing day is reported and the
  loop continues; the script writes no report files at all (rendering is
  the agent's single-day work, validated by Test-DailyReport.ps1), so it
  can never leave a half-written file. Evidence JSON goes to stdout per
  day, or to -EvidenceDir when the operator opts in explicitly.
.EXAMPLE
  .\Invoke-DailyReportBatch.ps1 -StartDate 2026-11-01 -EndDate 2026-11-07
.EXAMPLE
  .\Invoke-DailyReportBatch.ps1 -StartDate 2026-11-01 -EndDate 2026-11-07 -Validate
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$StartDate,

    [Parameter(Mandatory = $true)]
    [string]$EndDate,

    [switch]$Regenerate,
    [switch]$Validate,
    [string]$RepoRoot = "",
    [string]$GitUser = "",
    [string]$ScriptsDir = "",
    [string]$EvidenceDir = ""
)

$ErrorActionPreference = 'Stop'

if (-not $ScriptsDir) { $ScriptsDir = $PSScriptRoot }
$gitProof = Join-Path $ScriptsDir 'Get-GitProof.ps1'
$sessionEvidence = Join-Path $ScriptsDir 'Get-SessionEvidence.ps1'
$tester = Join-Path $ScriptsDir 'Test-DailyReport.ps1'
$manifestScript = Join-Path $ScriptsDir 'Get-ReportManifest.ps1'
foreach ($s in @($gitProof, $sessionEvidence, $tester, $manifestScript)) {
    if (-not (Test-Path $s)) { Write-Error "missing script: $s"; exit 1 }
}

$s = [DateTime]::MinValue; $e = [DateTime]::MinValue
if (-not [DateTime]::TryParseExact($StartDate, 'yyyy-MM-dd', [CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$s)) {
    Write-Error "Invalid -StartDate '$StartDate'. Use 'yyyy-MM-dd'."
    exit 1
}
if (-not [DateTime]::TryParseExact($EndDate, 'yyyy-MM-dd', [CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$e)) {
    Write-Error "Invalid -EndDate '$EndDate'. Use 'yyyy-MM-dd'."
    exit 1
}
if ($e -lt $s) { Write-Error '-EndDate must be on or after -StartDate.'; exit 1 }
if (($e - $s).TotalDays -gt 31) { Write-Error 'batch scope: range wider than 31 days is refused.'; exit 1 }

if (-not $RepoRoot) {
    $RepoRoot = (& git rev-parse --show-toplevel 2>$null)
    if (-not $RepoRoot) { Write-Error 'repo scope: not inside a git repository.'; exit 1 }
}
if (-not $GitUser) {
    $GitUser = (& git -C $RepoRoot config user.name 2>$null)
    if (-not $GitUser) { Write-Error 'attribution: cannot resolve git user; pass -GitUser.'; exit 1 }
    $GitUser = ($GitUser -replace '[^A-Za-z0-9._-]', '-')
}

# The manifest dictates the mode: multi collects evidence for every
# existing watched repo; single (or no manifest) for -RepoRoot only.
# A manifest that exists but fails validation aborts the batch loudly.
$manifest = (& $manifestScript -RepoRoot $RepoRoot -Optional | Out-String | ConvertFrom-Json)
$evidenceRoots = @($RepoRoot)
if ($manifest.mode -eq 'multi') {
    $evidenceRoots = @(@($manifest.repos) | Where-Object { $_.exists } | ForEach-Object { $_.path })
    if ($evidenceRoots.Count -eq 0) {
        Write-Error 'manifest: multi mode has no reachable repository on this machine (every repos path is missing).'
        exit 1
    }
}

$results = @()
for ($day = $s; $day -le $e; $day = $day.AddDays(1)) {
    $dateStr = $day.ToString('yyyy-MM-dd')
    $yymmdd = $day.ToString('yyMMdd')
    $reportPath = Join-Path $RepoRoot "reports/daily/$GitUser/$yymmdd.md"
    $entry = [ordered]@{ date = $dateStr; report = "$reportPath"; status = ''; detail = '' }

    try {
        if ($Validate) {
            if (-not (Test-Path $reportPath)) { $entry.status = 'missing'; $results += $entry; continue }
            $out = & $tester -ReportPath $reportPath -RepoRoot $RepoRoot -GitUser $GitUser -Date $dateStr 2>&1
            if ($LASTEXITCODE -eq 0) { $entry.status = 'valid' } else { $entry.status = 'invalid'; $entry.detail = "$out" }
        }
        else {
            if ((Test-Path $reportPath) -and -not $Regenerate) {
                $entry.status = 'skipped'
                $results += $entry
                continue
            }
            foreach ($root in $evidenceRoots) {
                $proof = & $gitProof -Date $dateStr -RepoRoot $root -Author (& git -C $root config user.email 2>$null) | Out-String
                if ($LASTEXITCODE -ne 0) { throw "Get-GitProof failed ($root): $proof" }
                $sessions = & $sessionEvidence -Date $dateStr -RepoRoot $root | Out-String
                if ($LASTEXITCODE -ne 0) { throw "Get-SessionEvidence failed ($root): $sessions" }
                $suffix = ''
                $scope = ''
                if ($evidenceRoots.Count -gt 1) {
                    $suffix = '-' + ((Split-Path $root -Leaf) -replace '[^A-Za-z0-9._-]', '-')
                    $scope = " [$root]"
                }
                if ($EvidenceDir) {
                    if (-not (Test-Path $EvidenceDir)) { New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null }
                    [IO.File]::WriteAllText((Join-Path $EvidenceDir "$yymmdd$suffix.gitproof.json"), $proof)
                    [IO.File]::WriteAllText((Join-Path $EvidenceDir "$yymmdd$suffix.sessions.json"), $sessions)
                }
                else {
                    # stdout carries the summary JSON only; evidence rides the
                    # information stream so callers can parse the result cleanly.
                    Write-Information "=== evidence $dateStr (git proof$scope) ===" -InformationAction Continue
                    Write-Information $proof -InformationAction Continue
                    Write-Information "=== evidence $dateStr (sessions$scope) ===" -InformationAction Continue
                    Write-Information $sessions -InformationAction Continue
                }
            }
            $entry.status = 'evidence-ready'
        }
    }
    catch {
        # Isolation: a failing day is reported and the loop continues.
        $entry.status = 'failed'
        $entry.detail = "$_"
    }
    $results += $entry
}

[ordered]@{
    gitUser = $GitUser
    mode    = if ($Validate) { 'validate' } else { 'collect' }
    days    = $results
    failed  = @($results | Where-Object { $_.status -eq 'failed' }).Count
} | ConvertTo-Json -Depth 5

if (@($results | Where-Object { $_.status -eq 'failed' }).Count -gt 0) { exit 1 }
exit 0
