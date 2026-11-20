<#
.SYNOPSIS
  Per-day session-grounding coverage: no local session may be silently missed.
.DESCRIPTION
  Classifies every session with a turn inside the calendar day against the
  repositories this report watches (the manifest in multi mode, the invoking
  checkout in single mode). Membership uses the exact rules
  Get-SessionEvidence.ps1 queries with — keep them in sync:
    key = origin parsed to owner/name (GitHub) or org/project/repo (Azure)
    cwd = the session cwd equals or sits under a watched checkout path
  Classes: inScope, outOfScope (a different checkout), unattributed (no
  repository and no cwd). Nothing is dropped — outOfScope and unattributed
  ride the receipt so the report-back must name them.

  With -EvidenceJson (every per-repo evidence file that day's grounding
  produced) the receipt also diffs the store's in-scope ids against what
  evidence returned: a non-empty missed list and verified/complete flags are
  what Test-DailyReport.ps1 -CoverageJson enforces. Write the receipt to the
  report's sessions/<yymmdd>/coverage.json.
.EXAMPLE
  .\Get-SessionCoverage.ps1 -Date 2026-11-19 -RepoRoot ..\home-repo -EvidenceJson ev\kit.json,ev\fc.json -OutJson sessions\261119\coverage.json
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Date,

    [string]$Start = "",

    [string]$End = "",

    [string]$RepoRoot = "",

    [string]$SessionDbPath = "$env:USERPROFILE\.copilot\session-store.db",

    [string[]]$EvidenceJson = @(),

    [string]$OutJson = "",

    [int]$UtcOffsetHours = [int][DateTimeOffset]::Now.Offset.TotalHours
)

$ErrorActionPreference = 'Stop'

# Day-scope guardrail: exactly one calendar day.
$parsedDay = [DateTime]::MinValue
if (-not [DateTime]::TryParseExact($Date, 'yyyy-MM-dd', [CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsedDay)) {
    Write-Error "Invalid -Date '$Date'. Use 'yyyy-MM-dd'."
    exit 1
}
$parsedStart = $parsedDay
$parsedEnd = $parsedDay.AddDays(1)
if ($Start -or $End) {
    $fmt = [string[]]@('yyyy-MM-dd HH:mm', 'yyyy-MM-dd HH:mm:ss')
    $s = [DateTime]::MinValue; $e = [DateTime]::MinValue
    $sOk = $Start -and [DateTime]::TryParseExact($Start, $fmt, [CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$s)
    $eOk = $End -and [DateTime]::TryParseExact($End, $fmt, [CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$e)
    if (-not $sOk -or -not $eOk) {
        Write-Error "Invalid -Start/-End. Use 'yyyy-MM-dd HH:mm'."
        exit 1
    }
    if ($s.Date -ne $parsedDay -or ($e.Date -ne $parsedDay -and $e -ne $parsedDay.AddDays(1))) {
        Write-Error "day scope: -Start/-End must stay inside $Date."
        exit 1
    }
    $parsedStart = $s; $parsedEnd = $e
}

if (-not $RepoRoot) {
    $RepoRoot = (& git rev-parse --show-toplevel 2>$null)
}
if (-not $RepoRoot) {
    Write-Error 'repo scope: not inside a git repository and no -RepoRoot given.'
    exit 1
}
if (-not (Test-Path $SessionDbPath)) {
    Write-Error "Session store not found at: $SessionDbPath — state this grounding gap in the report."
    exit 1
}

# Watched set: the manifest decides in multi mode, single mode the checkout.
$manifestScript = Join-Path $PSScriptRoot 'Get-ReportManifest.ps1'
if (-not (Test-Path $manifestScript)) { Write-Error "missing script: $manifestScript"; exit 1 }
$manifest = (& $manifestScript -RepoRoot $RepoRoot -Optional | Out-String | ConvertFrom-Json)
$watched = @()
if ($manifest.mode -eq 'multi') {
    $watched = @(@($manifest.repos) | Where-Object { $_.exists } | ForEach-Object { $_.path })
    if ($watched.Count -eq 0) {
        Write-Error 'manifest: multi mode has no reachable repository on this machine (every repos path is missing).'
        exit 1
    }
}
else {
    $watched = @($RepoRoot)
}

# Origin parse — keep in sync with Get-SessionEvidence.ps1.
function Get-RepoKey([string]$Root) {
    $u = (& git -C $Root remote get-url origin 2>$null)
    if ($u -and $u -match '(?:github\.com[/:])([^/]+)/([^/]+?)(?:\.git)?$') { return "$($matches[1])/$($matches[2])" }
    if ($u -and $u -match '(?:dev\.azure\.com[/:])v3/([^/]+)/([^/]+)/([^/]+?)(?:\.git)?$') { return "$($matches[1])/$($matches[2])/$($matches[3])" }
    if ($u -and $u -match '(?:dev\.azure\.com[/:])([^/]+)/([^/]+)/_git/([^/]+?)(?:\.git)?$') { return "$($matches[1])/$($matches[2])/$($matches[3])" }
    return ''
}
$watchInfo = @()
foreach ($w in $watched) {
    $norm = ($w -replace '/', '\').TrimEnd('\').ToLowerInvariant()
    $watchInfo += [pscustomobject]@{ path = $norm; key = (Get-RepoKey $w) }
}

$utcStart = $parsedStart.AddHours(-$UtcOffsetHours)
$utcEnd = $parsedEnd.AddHours(-$UtcOffsetHours)
$utcStartStr = $utcStart.ToString('yyyy-MM-ddTHH:mm:ss')
$utcEndStr = $utcEnd.ToString('yyyy-MM-ddTHH:mm:ss')

$query = @"
SELECT DISTINCT s.id, COALESCE(s.repository, '') AS repository, COALESCE(s.cwd, '') AS cwd
FROM sessions s
INNER JOIN turns t ON t.session_id = s.id
WHERE t.timestamp >= '$utcStartStr' AND t.timestamp < '$utcEndStr'
ORDER BY s.id
"@
$raw = ((sqlite3.exe -json $SessionDbPath $query 2>$null) -join "`n").Trim()
$rows = @()
if ($raw) { $rows = @($raw | ConvertFrom-Json) }

# Classify every store session — the same membership rules evidence queries with.
$inScopeIds = @(); $outOfScope = @(); $unattributed = @()
foreach ($r in $rows) {
    $id = ([string]$r.id).ToLowerInvariant()
    $repoKey = ([string]$r.repository).Trim()
    $cwdN = if ($r.cwd) { ($r.cwd -replace '/', '\').TrimEnd('\').ToLowerInvariant() } else { '' }
    $hit = $false
    foreach ($w in $watchInfo) {
        if ($repoKey -and $w.key -and ($repoKey -ceq $w.key)) { $hit = $true; break }
        if ($cwdN -and ($cwdN -eq $w.path -or $cwdN.StartsWith($w.path + '\'))) { $hit = $true; break }
    }
    if ($hit) { $inScopeIds += $id }
    elseif (-not $repoKey -and -not $cwdN) {
        $unattributed += [ordered]@{ id = $id; repository = ''; cwd = '' }
    }
    else {
        $outOfScope += [ordered]@{ id = $id; repository = $repoKey; cwd = $r.cwd }
    }
}
$inScopeIds = @($inScopeIds | Sort-Object)

# Evidence diff: the receipt is only verified when every evidence file is read.
$evidenceIds = @{}
$evidenceFiles = 0
foreach ($f in $EvidenceJson) {
    if (-not (Test-Path -LiteralPath $f)) {
        Write-Error "evidence file not found: $f — coverage stays unverified."
        exit 1
    }
    $evidenceFiles++
    $ev = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
    foreach ($s in @($ev.sessions)) {
        if ($s.id) { $evidenceIds[([string]$s.id).ToLowerInvariant()] = $true }
    }
}
$verified = ($evidenceFiles -gt 0)
$missed = @()
if ($verified) { $missed = @($inScopeIds | Where-Object { -not $evidenceIds.ContainsKey($_) }) }
$complete = $verified -and ($missed.Count -eq 0)

$receipt = [ordered]@{
    schema         = 1
    date           = $Date
    utcStart       = $utcStartStr
    utcEnd         = $utcEndStr
    mode           = $manifest.mode
    watched        = $watched.Count
    storeSessions  = $rows.Count
    inScope        = $inScopeIds.Count
    inScopeIds     = $inScopeIds
    outOfScope     = $outOfScope
    unattributed   = $unattributed
    evidenceFiles  = $evidenceFiles
    verified       = $verified
    missed         = $missed
    complete       = $complete
}
$json = $receipt | ConvertTo-Json -Depth 6
if ($OutJson) {
    $dir = Split-Path $OutJson -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($OutJson, $json)
}
$json
exit 0
