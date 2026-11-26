<#
.SYNOPSIS
  Export every session a daily report cites to sessions/<yymmdd>/<full-uuid>.html.
.DESCRIPTION
  Reads the report for session citations and writes a self-contained turns-only
  HTML transcript beside the report under sessions/<yymmdd>/, one file per
  cited session. The slug is ALWAYS the full session UUID — never the short
  form the prose uses — so one session owns exactly one file and a link written
  today still resolves after a rerun. The transcripts are committed; only the
  coverage receipt beside them is git-ignored.

  Two citation forms are read, and both feed the same single parser:
    1. a transcript link, `[<8-char id>](sessions/<yymmdd>/<full-uuid>.html)`
       (the template form: display text stays short and copy-friendly, the
       link target carries the full id);
    2. a legacy prose citation, ``session `<8-char or full>` `` (a full UUID
       also matches, `grill session` never does).
  When a session is cited in both forms the link form wins, so the slug never
  depends on which form appeared first.

  Resolution per citation, against this machine's Copilot state ($CopilotHome
  or $env:COPILOT_HOME, else ~/.copilot): events.jsonl folder first, then
  session-store.db turns. An 8-char prefix that resolves to more than one
  session fails loudly before any file is written — cite the full id instead.
  A link whose target is a short id while the session resolves here also fails
  loudly: the link must name the full UUID.

  A session this machine cannot resolve gets an explicit notice page carrying
  the `daily-report-session-notice` marker, so a missing transcript is always an
  honest artifact and never a silent skip; its only possible slug is the cited
  id, because the full UUID is exactly what this machine does not hold.
  Existing files are never downgraded: a real transcript is kept as-is (pass
  -Refresh to re-export it), a notice is upgraded to the real transcript the
  moment the data becomes resolvable here. A leftover short-form file for a
  session that now exports under its full UUID is pruned, so one session never
  leaves two artifacts. The JSON receipt reports
  {total, exported, notice, kept, pruned}.

  -ListOnly prints the cited ids (one per line) and stops before any store or
  Python access; Test-DailyReport.ps1 uses it to enforce the exports.
  -CoverageJson <receipt> additionally exports every in-scope session of the
  day from Get-SessionCoverage.ps1, cited or not, so each grounded session
  leaves an artifact under its full UUID.
.EXAMPLE
  .\Export-SessionTranscripts.ps1 -ReportPath ..\..\..\reports\daily\alice\261117.md
.EXAMPLE
  .\Export-SessionTranscripts.ps1 -ReportPath <path> -CoverageJson sessions\261117\coverage.json
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
$uuidRx = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

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

# Transcripts and the coverage receipt group under the report's date folder:
# sessions/<yymmdd>/<full-uuid>.html, so days never mix in one flat directory.
$dayCode = [IO.Path]::GetFileNameWithoutExtension($ReportPath)
if ($dayCode -notmatch '^\d{6}$') {
    Write-Error "report must be named yymmdd.md for date-grouped exports, got '$([IO.Path]::GetFileName($ReportPath))'."
    exit 1
}
$sessionsDir = Join-Path (Join-Path (Split-Path $ReportPath -Parent) 'sessions') $dayCode

# ---- session citations: single source of truth for exporter and validator ----
# Two forms are read, and both yield the same target id:
#   link  [<8-char id>](sessions/<yymmdd>/<full-uuid>.html)  — the template form
#   prose session `<8-char id or full uuid>`                  — legacy reports
# The transcript HTML is committed, so a link resolves for every reader; its
# target must still name the full UUID, which is the slug on disk.
function Get-CitedSessions([string]$Text) {
    $cited = @()
    $linkRx = [regex]::new('\[[^\]]*\]\(\s*<?([^)>\s]*)>?\s*\)', 'IgnoreCase')
    foreach ($m in $linkRx.Matches($Text)) {
        $href = $m.Groups[1].Value
        $stemMatch = [regex]::Match($href, '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|[0-9a-fA-F]{8})\.html$')
        if (-not $stemMatch.Success) { continue }
        $cited += [pscustomobject]@{ id = $stemMatch.Groups[1].Value.ToLowerInvariant(); target = $href; form = 'link' }
    }
    $proseRx = [regex]::new('(?<![\w-])(?<!grill )sessions?\s+`([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[0-9a-f]{8})`', 'IgnoreCase')
    foreach ($m in $proseRx.Matches($Text)) {
        $cited += [pscustomobject]@{ id = $m.Groups[1].Value.ToLowerInvariant(); target = $null; form = 'prose' }
    }
    # Dedupe by id, preferring the link form, then drop every 8-char form a full
    # UUID absorbs. Two distinct full UUIDs stay distinct even when they share
    # an 8-char prefix.
    $byId = [ordered]@{}
    foreach ($c in $cited) {
        if (-not $byId.Contains($c.id)) { $byId[$c.id] = $c }
        elseif ($c.form -eq 'link' -and $byId[$c.id].form -eq 'prose') { $byId[$c.id] = $c }
    }
    $list = @($byId.Values)
    $out = @()
    foreach ($c in $list) {
        if ($c.id.Length -eq 8 -and @($list | Where-Object { $_.id.Length -gt 8 -and $_.id.StartsWith($c.id) }).Count -gt 0) { continue }
        $out += $c
    }
    return $out
}

$cited = @(Get-CitedSessions ([IO.File]::ReadAllText($ReportPath)))

# A link is what a reader clicks, so its stem must be the full UUID and must
# sit in this report's date folder. Both are contract violations, not
# ambiguity: fail before anything is written.
foreach ($c in $cited) {
    if ($c.form -ne 'link') { continue }
    if ($c.id -notmatch $uuidRx) {
        Write-Error "transcript link target '$($c.target)' must name the full session UUID — write [$($c.id)](sessions/$dayCode/<full-uuid>.html)."
        exit 1
    }
    $targetDir = ((Split-Path (($c.target -replace '\\', '/') -replace '/+', '/') -Parent) -replace '\\', '/')
    if ($targetDir -and $targetDir -ne "sessions/$dayCode") {
        Write-Error "transcript link '$($c.target)' must live in sessions/$dayCode/ beside its report."
        exit 1
    }
}

$mentioned = @($cited | ForEach-Object { $_.id })
if ($ListOnly) { $mentioned; exit 0 }

# Coverage union: every in-scope session of the day gets an export, cited or
# not. Applied after -ListOnly so the validator's citation list stays exact.
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
        if (-not $dup) { $cited += [pscustomobject]@{ id = $id; target = $null; form = 'coverage' } }
    }
}

# ---- phase 5 helper: orphan short-form sweep ----
# A short-form file left by an older run is pruned only when exactly one
# full-UUID file under the same 8-char prefix exists, so an ambiguous prefix
# never destroys another session's artifact. Runs even when nothing is cited,
# which is what makes a rerun converge on one file per session.
function Invoke-OrphanSweep([object[]]$AlreadyPruned) {
    $found = @()
    if (-not (Test-Path -LiteralPath $sessionsDir)) { return $found }
    $byBase = @(Get-ChildItem -LiteralPath $sessionsDir -Filter '*.html' -File)
    foreach ($f in $byBase) {
        if ($f.BaseName -notmatch '^[0-9a-f]{8}$') { continue }
        $fullPeers = @($byBase | Where-Object { $_.BaseName -match "^$([regex]::Escape($f.BaseName))-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$" })
        if ($fullPeers.Count -ne 1) { continue }
        if (@($AlreadyPruned | Where-Object { $_['path'] -eq $f.FullName }).Count -gt 0) { continue }
        Remove-Item -LiteralPath $f.FullName -Force
        $found += [ordered]@{ id = $f.BaseName; slug = $fullPeers[0].BaseName; status = 'pruned'; path = $f.FullName }
    }
    return $found
}

if ($cited.Count -eq 0) {
    $orphans = @(Invoke-OrphanSweep @())
    [ordered]@{ report = $ReportPath; sessionsDir = $sessionsDir; total = 0; exported = @(); notice = @(); kept = @(); pruned = $orphans } | ConvertTo-Json -Depth 6
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
        # Bare `sqlite3`: PATHEXT resolves it on Windows, plain name on Linux/macOS.
        $raw = ((sqlite3 -json $storeDb "SELECT DISTINCT session_id FROM turns WHERE session_id LIKE '$Id%';" 2>$null) -join "`n").Trim()
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

# ---- phase 1: resolve every citation; ambiguity fails before anything is written ----
$plan = @()
foreach ($c in $cited) {
    $r = Resolve-Session $c.id
    if ($r.ids.Count -gt 1) {
        Write-Error "ambiguous session id $($c.id): matches $($r.ids -join ', ') — cite the full session id in the report."
        exit 1
    }
    $full = if ($r.ids.Count -eq 1) { $r.ids[0] } else { $null }
    $source = $null
    if ($full) {
        if (Test-Path -LiteralPath (Join-Path (Join-Path $stateDir $full) 'events.jsonl')) { $source = 'events' }
        elseif ($r.dbIds -contains $full) { $source = 'db' }
    }
    # Slug is the full UUID whenever one is known: resolved here, else the id the
    # report already carries. Only an unresolvable short citation stays short —
    # that session's full UUID is exactly what this machine does not hold.
    $slug = if ($full) { $full } else { $c.id }
    $plan += [pscustomobject]@{ id = $c.id; slug = $slug; full = $full; source = $source }
}

# ---- phase 2: decide each action; existing real transcripts are never downgraded ----
function Test-ExistingNotice([string]$Slug) {
    $p = Join-Path $sessionsDir "$Slug.html"
    if (-not (Test-Path -LiteralPath $p)) { return $null }   # nothing on disk
    return (Test-NoticeFile $p)                              # $true = notice, $false = real transcript
}
$actions = @()
foreach ($p in $plan) {
    $existing = Test-ExistingNotice $p.slug
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
$pruned = @()
$savedCopilotHome = $env:COPILOT_HOME
$env:COPILOT_HOME = $CopilotHome
try {
    foreach ($a in $actions) {
        $slug = $a.plan.slug
        $path = Join-Path $sessionsDir "$slug.html"
        switch ($a.action) {
            'keep' {
                $entries += [ordered]@{ id = $a.plan.id; slug = $slug; status = 'kept'; path = $path }
            }
            'notice' {
                Write-UnavailableNotice -Path $path -SessionId $slug -Report $ReportPath
                $entries += [ordered]@{ id = $a.plan.id; slug = $slug; status = 'notice'; path = $path }
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
                $entries += [ordered]@{ id = $a.plan.id; slug = $slug; status = 'exported'; source = $a.plan.source; turns = $turns; path = $path }
            }
        }
        # One session, one artifact: a short-form file left by an older run is
        # dropped once the same session exports under its full UUID.
        if ($a.plan.slug -ne $a.plan.id -and $a.action -ne 'keep') {
            $stale = Join-Path $sessionsDir "$($a.plan.id).html"
            if (Test-Path -LiteralPath $stale) {
                Remove-Item -LiteralPath $stale -Force
                $pruned += [ordered]@{ id = $a.plan.id; slug = $slug; status = 'pruned'; path = $stale }
            }
        }
    }
}
finally {
    if ($null -eq $savedCopilotHome) { Remove-Item Env:COPILOT_HOME -ErrorAction SilentlyContinue }
    else { $env:COPILOT_HOME = $savedCopilotHome }
}

# ---- phase 5: orphan short-form sweep ----
$pruned += @(Invoke-OrphanSweep $pruned)

# ---- receipt ----
[ordered]@{
    report      = $ReportPath
    sessionsDir = $sessionsDir
    total       = $cited.Count
    exported    = @($entries | Where-Object { $_['status'] -eq 'exported' })
    notice      = @($entries | Where-Object { $_['status'] -eq 'notice' })
    kept        = @($entries | Where-Object { $_['status'] -eq 'kept' })
    pruned      = @($pruned)
} | ConvertTo-Json -Depth 6
exit 0
