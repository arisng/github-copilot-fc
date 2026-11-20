<#
.SYNOPSIS
  Export every session a daily report mentions to sessions/<session-slug>.html.
.DESCRIPTION
  Parses the report for session mentions (`session `xxxxxxxx``; a full UUID also
  matches, `grill session` never does) and writes a self-contained turns-only
  HTML transcript beside the report under sessions/, one file per mentioned
  session. The slug is the id exactly as the report cites it (lowercased), so
  Test-DailyReport.ps1 re-checks the same paths through -ListOnly without
  touching the session stores.

  Resolution per mention, against this machine's Copilot state ($CopilotHome or
  $env:COPILOT_HOME, else ~/.copilot): events.jsonl folder first, then
  session-store.db turns. An 8-char prefix that resolves to more than one
  session fails loudly before any file is written — cite the full id instead.

  A session this machine cannot resolve gets an explicit notice page carrying
  the `daily-report-session-notice` marker, so a missing transcript is always an
  honest artifact and never a silent skip. Existing files are never downgraded:
  a real transcript is kept as-is (pass -Refresh to re-export it), a notice is
  upgraded to the real transcript the moment the data becomes resolvable here.
  The JSON receipt reports {total, exported, notice, kept}.

  -ListOnly prints the mentioned ids (one per line) and stops before any store
  or Python access; Test-DailyReport.ps1 uses it to enforce the exports.
  -CoverageJson <receipt> additionally exports every in-scope session of the
  day from Get-SessionCoverage.ps1, cited or not, so each grounded session
  leaves an artifact. The report's mention form wins the slug (validator
  checks those paths); coverage-only sessions get the full-id slug.
.EXAMPLE
  .\Export-SessionTranscripts.ps1 -ReportPath ..\..\..\reports\daily\alice\261117.md
.EXAMPLE
  .\Export-SessionTranscripts.ps1 -ReportPath <path> -CoverageJson sessions\261117.coverage.json
#>
param(
    [string]$ReportPath = "",
    [string]$RepoRoot = "",
    [string]$GitUser = "",
    [string]$Date = "",
    [string]$CopilotHome = "",
    [string]$Python = "",
    [string]$CoverageJson = "",
    [switch]$Refresh,
    [switch]$ListOnly
)

$ErrorActionPreference = 'Stop'
$exporterScript = Join-Path $PSScriptRoot 'export-copilot-transcript.py'
$NoticeMarker = 'daily-report-session-notice'

# ---- report path (same derivation rules as Test-DailyReport.ps1) ----
if (-not $ReportPath) {
    if (-not $RepoRoot -or -not $GitUser -or -not $Date) { Write-Error 'pass -ReportPath or -RepoRoot/-GitUser/-Date.'; exit 1 }
    $parsedDay = [DateTime]::MinValue
    if (-not [DateTime]::TryParseExact($Date, 'yyyy-MM-dd', [CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsedDay)) {
        Write-Error "Invalid -Date '$Date'. Use 'yyyy-MM-dd'."
        exit 1
    }
    $ReportPath = Join-Path $RepoRoot "reports/daily/$GitUser/$($parsedDay.ToString('yyMMdd')).md"
}
if (-not (Test-Path -LiteralPath $ReportPath)) { Write-Error "report not found: $ReportPath"; exit 1 }
$ReportPath = [IO.Path]::GetFullPath($ReportPath)

# ---- session mentions: single source of truth for exporter and validator ----
function Get-MentionedSessions([string]$Text) {
    $rx = [regex]::new('(?<![\w-])(?<!grill )sessions?\s+`([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[0-9a-f]{8})`', 'IgnoreCase')
    $all = @()
    foreach ($m in $rx.Matches($Text)) { $all += $m.Groups[1].Value.ToLowerInvariant() }
    # Collapse a session cited both as short id and full UUID to one entry
    # (first-cited form). Two distinct full UUIDs stay distinct even when they
    # share an 8-char prefix — only short-vs-full of the same session dedupes.
    $ids = @()
    foreach ($id in $all) {
        if ($ids -contains $id) { continue }
        if ($id.Length -gt 8) {
            if (@($ids | Where-Object { $_.Length -eq 8 -and $id.StartsWith($_) }).Count -gt 0) { continue }
        }
        else {
            if (@($ids | Where-Object { $_.Length -gt 8 -and $_.StartsWith($id) }).Count -gt 0) { continue }
        }
        $ids += $id
    }
    return $ids
}

$mentioned = @(Get-MentionedSessions ([IO.File]::ReadAllText($ReportPath)))
if ($ListOnly) { $mentioned; exit 0 }

# Coverage union: every in-scope session of the day gets an export, cited or
# not. Applied after -ListOnly so the validator's mention list stays exact;
# the mention form wins the slug it already checks.
if ($CoverageJson) {
    if (-not (Test-Path -LiteralPath $CoverageJson)) { Write-Error "coverage receipt not found: $CoverageJson"; exit 1 }
    $cov = Get-Content -LiteralPath $CoverageJson -Raw | ConvertFrom-Json
    foreach ($raw in @($cov.inScopeIds)) {
        if (-not $raw) { continue }
        $id = ([string]$raw).ToLowerInvariant()
        $dup = $false
        foreach ($existing in $mentioned) {
            if ($existing -eq $id) { $dup = $true; break }
            if ($id.Length -gt 8 -and $id.StartsWith($existing)) { $dup = $true; break }
            if ($existing.Length -gt 8 -and $existing.StartsWith($id)) { $dup = $true; break }
        }
        if (-not $dup) { $mentioned += $id }
    }
}

$sessionsDir = Join-Path (Split-Path $ReportPath -Parent) 'sessions'
if ($mentioned.Count -eq 0) {
    [ordered]@{ report = $ReportPath; sessionsDir = $sessionsDir; total = 0; exported = @(); notice = @(); kept = @() } | ConvertTo-Json -Depth 6
    exit 0
}

# ---- resolve this machine's session store ----
if (-not $CopilotHome) { $CopilotHome = if ($env:COPILOT_HOME) { $env:COPILOT_HOME } else { Join-Path $HOME '.copilot' } }
$stateDir = Join-Path $CopilotHome 'session-state'
$storeDb = Join-Path $CopilotHome 'session-store.db'

function Resolve-Session([string]$Id) {
    $candidates = @{}
    if (Test-Path -LiteralPath $stateDir) {
        foreach ($d in @(Get-ChildItem -LiteralPath $stateDir -Directory -Filter "$Id*" -ErrorAction SilentlyContinue)) {
            $candidates[$d.Name.ToLowerInvariant()] = $true
        }
    }
    $dbIds = @()
    if (Test-Path -LiteralPath $storeDb) {
        $raw = ((sqlite3.exe -json $storeDb "SELECT DISTINCT session_id FROM turns WHERE session_id LIKE '$Id%';" 2>$null) -join "`n").Trim()
        if ($raw) { foreach ($row in @($raw | ConvertFrom-Json)) { $dbIds += ([string]$row.session_id).ToLowerInvariant() } }
    }
    foreach ($x in $dbIds) { $candidates[$x] = $true }
    return [pscustomobject]@{ ids = @($candidates.Keys); dbIds = @($dbIds | Select-Object -Unique) }
}

function Test-NoticeFile([string]$Path) {
    try { return [bool](Select-String -LiteralPath $Path -Pattern $NoticeMarker -Quiet -ErrorAction Stop) }
    catch { return $false }
}

function Write-UnavailableNotice {
    param([string]$Path, [string]$SessionId, [string]$Report)
    $encReport = [System.Net.WebUtility]::HtmlEncode($Report)
    $encId = [System.Net.WebUtility]::HtmlEncode($SessionId)
    $checkedState = [System.Net.WebUtility]::HtmlEncode((Join-Path $stateDir "$SessionId\events.jsonl"))
    $checkedDb = [System.Net.WebUtility]::HtmlEncode($storeDb)
    $stamp = [System.Net.WebUtility]::HtmlEncode((Get-Date).ToString('yyyy-MM-dd HH:mm zzz'))
    $html = @"
<!-- $NoticeMarker -->
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Session transcript not available on this machine — $encId</title>
<style>
  body { font: 16px/1.55 system-ui, sans-serif; max-width: 46rem; margin: 3rem auto; padding: 0 1.25rem; color: #16181c; background: #fff; }
  h1 { font-size: 1.35rem; }
  code { background: #f1f3f5; padding: .1em .35em; border-radius: 4px; }
  .meta { color: #5c6370; font-size: .9rem; }
</style>
</head>
<body>
<h1>Session transcript not available on this machine</h1>
<p>Session <code>$encId</code> is cited by the daily report <code>$encReport</code>, but this machine holds no
event stream and no store turns for it — the session ran on another machine or its data was pruned.</p>
<p>Checked at ${stamp}:</p>
<ul>
<li><code>$checkedState</code></li>
<li><code>$checkedDb</code></li>
</ul>
<p class="meta">Run <code>Export-SessionTranscripts.ps1</code> on the machine that holds the session, then copy
the generated file here to replace this notice.</p>
</body>
</html>
"@
    [IO.File]::WriteAllText($Path, $html)
}

# ---- phase 1: resolve every mention; ambiguity fails before anything is written ----
$plan = @()
foreach ($id in $mentioned) {
    $r = Resolve-Session $id
    if ($r.ids.Count -gt 1) {
        Write-Error "ambiguous session id ${id}: matches $($r.ids -join ', ') — cite the full session id in the report."
        exit 1
    }
    $full = if ($r.ids.Count -eq 1) { $r.ids[0] } else { $null }
    $source = $null
    if ($full) {
        if (Test-Path -LiteralPath (Join-Path (Join-Path $stateDir $full) 'events.jsonl')) { $source = 'events' }
        elseif ($r.dbIds -contains $full) { $source = 'db' }
    }
    $plan += [pscustomobject]@{ id = $id; full = $full; source = $source }
}

# ---- phase 2: decide each action; existing real transcripts are never downgraded ----
function Test-ExistingNotice([string]$Slug) {
    $p = Join-Path $sessionsDir "$Slug.html"
    if (-not (Test-Path -LiteralPath $p)) { return $null }   # nothing on disk
    return (Test-NoticeFile $p)                              # $true = notice, $false = real transcript
}
$actions = @()
foreach ($p in $plan) {
    $existing = Test-ExistingNotice $p.id
    if ($p.source) {
        if ($null -eq $existing) { $actions += [pscustomobject]@{ plan = $p; action = 'export' } }
        elseif ($existing) { $actions += [pscustomobject]@{ plan = $p; action = 'export' } }  # upgrade notice
        elseif ($Refresh) { $actions += [pscustomobject]@{ plan = $p; action = 'export' } }
        else { $actions += [pscustomobject]@{ plan = $p; action = 'keep' } }
    }
    else {
        if ($null -eq $existing) { $actions += [pscustomobject]@{ plan = $p; action = 'notice' } }
        else { $actions += [pscustomobject]@{ plan = $p; action = 'keep' } }
    }
}

# ---- phase 3: python is required only when at least one real export will run ----
function Resolve-Python([string]$Cmd) {
    $candidates = if ($Cmd) { @($Cmd) } else { @('python', 'py', 'python3') }
    foreach ($c in $candidates) {
        if (-not (Get-Command $c -ErrorAction SilentlyContinue)) { continue }
        try {
            $v = ((& $c --version 2>&1) | Out-String).Trim()
            if ($LASTEXITCODE -eq 0 -and $v -match 'Python 3\.') { return $c }
        }
        catch { }
    }
    return $null
}
$willExport = @($actions | Where-Object { $_.action -eq 'export' })
$pyExe = $null
if ($willExport.Count -gt 0) {
    $pyExe = Resolve-Python $Python
    if (-not $pyExe) {
        Write-Error "python 3 not found (install Python 3 or pass -Python) — cannot export: $($willExport.plan.id -join ', ')"
        exit 1
    }
}

if (-not (Test-Path -LiteralPath $sessionsDir)) { New-Item -ItemType Directory -Force -Path $sessionsDir | Out-Null }

# ---- phase 4: write ----
$entries = @()
$savedCopilotHome = $env:COPILOT_HOME
$env:COPILOT_HOME = $CopilotHome
try {
    foreach ($a in $actions) {
        $slug = $a.plan.id
        $path = Join-Path $sessionsDir "$slug.html"
        switch ($a.action) {
            'keep' {
                $entries += [ordered]@{ id = $slug; slug = $slug; status = 'kept'; path = $path }
            }
            'notice' {
                Write-UnavailableNotice -Path $path -SessionId $slug -Report $ReportPath
                $entries += [ordered]@{ id = $slug; slug = $slug; status = 'notice'; path = $path }
            }
            'export' {
                $sessArg = if ($a.plan.source -eq 'events') { Join-Path $stateDir $a.plan.full } else { $a.plan.full }
                $pyArgs = @($exporterScript, '--session', $sessArg, '--source', $a.plan.source, '--out', $path)
                $prevEAP = $ErrorActionPreference
                $ErrorActionPreference = 'Continue'
                try {
                    $pyOut = (& $pyExe @pyArgs 2>&1 | ForEach-Object { "$_" }) -join "`n"
                    $pyExit = $LASTEXITCODE
                }
                finally { $ErrorActionPreference = $prevEAP }
                if ($pyExit -ne 0) {
                    Write-Error "export failed for session $slug via '$pyExe': $pyOut"
                    exit 1
                }
                $turns = $null
                if ([regex]::IsMatch($pyOut, '(\d+)\s+turns')) { $turns = [int][regex]::Match($pyOut, '(\d+)\s+turns').Groups[1].Value }
                $entries += [ordered]@{ id = $slug; slug = $slug; status = 'exported'; source = $a.plan.source; turns = $turns; path = $path }
            }
        }
    }
}
finally {
    if ($null -eq $savedCopilotHome) { Remove-Item Env:COPILOT_HOME -ErrorAction SilentlyContinue }
    else { $env:COPILOT_HOME = $savedCopilotHome }
}

# ---- receipt ----
[ordered]@{
    report      = $ReportPath
    sessionsDir = $sessionsDir
    total       = $mentioned.Count
    exported    = @($entries | Where-Object { $_['status'] -eq 'exported' })
    notice      = @($entries | Where-Object { $_['status'] -eq 'notice' })
    kept        = @($entries | Where-Object { $_['status'] -eq 'kept' })
} | ConvertTo-Json -Depth 6
exit 0
