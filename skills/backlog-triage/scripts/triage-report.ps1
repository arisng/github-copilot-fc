#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Render the triage signals payload as a self-contained static HTML report.

.DESCRIPTION
    Reads the JSON produced by triage-signals.ps1 (generating it first if absent) and
    renders a single self-contained HTML file: inline CSS, no JavaScript, no network
    requests. Static-rendered so the output is deterministic and testable.

    The report is grouped by the ACTION a human needs to take, not by raw data:
    overdue items, stale dependency references, the needs-triage queue, missing
    blocked labels, blocked chains, and P3 accumulation. The full backlog is behind a
    native <details> disclosure.

    Design matches the repo's finops-theme.css tokens (oklch, zero radius, mono labels).

.PARAMETER Repo
    Target repository in owner/name form. Only used when the signals file must be
    generated; otherwise the report renders from the payload's own repo/taxonomy.

.PARAMETER SignalsFile
    Path to the signals JSON. Defaults to cache/triage-signals.json; generated if missing.

.PARAMETER OutFile
    Path for the rendered HTML. Defaults to cache/triage-report.html.

.EXAMPLE
    pwsh .github/skills/triage/scripts/triage-report.ps1
#>
[CmdletBinding()]
param(
    [string]$Repo = "",
    [string]$SignalsFile = "cache/triage-signals.json",
    [string]$OutFile = "cache/triage-report.html",
    [string]$Config
)

$ErrorActionPreference = "Stop"

$signalsScript = Join-Path $PSScriptRoot 'triage-signals.ps1'

# Generate the signals if we do not have them yet, passing through repo/config so a
# fresh run targets the same repo and taxonomy.
if (-not (Test-Path $SignalsFile)) {
    Write-Host "Signals file not found - generating from GitHub..."
    $sigArgs = @{ Repo = $Repo; Json = $true; OutFile = $SignalsFile }
    if ($Config) { $sigArgs['Config'] = $Config }
    & $signalsScript @sigArgs | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "triage-signals.ps1 failed (exit $LASTEXITCODE)" }
}

$signals = Get-Content $SignalsFile -Raw | ConvertFrom-Json
if (-not $signals) { throw "Could not parse signals from $SignalsFile" }

# The payload is self-describing: adopt its repo and taxonomy so links and badges match
# the data even when -Repo was not passed here. Warn on a stale cache: when the caller
# asked for a different repo/config than the file was generated from, the taxonomy and
# links would silently mismatch.
if (-not $Repo) { $Repo = $signals.repo }
elseif ($signals.repo -and $Repo -ne $signals.repo) {
    Write-Warning "Signals file was generated for '$($signals.repo)' but -Repo '$Repo' was requested; links use -Repo."
}
$tax = $signals.taxonomy
if ($Config -and $tax.config_path -and $Config -ne $tax.config_path) {
    Write-Warning "Signals file was generated from '$($tax.config_path)' but -Config '$Config' was requested; re-run triage-signals.ps1 to refresh."
}
if ($signals.schema_version -ne 3) {
    throw "Signals file uses schema v$($signals.schema_version); this report expects v3. Delete '$SignalsFile' and re-run triage-signals.ps1."
}
if ("$($signals.taxonomy.label_check)" -ne 'passed') {
    throw "Signals file was generated with the taxonomy gate skipped (label_check='$($signals.taxonomy.label_check)'). It may be wrong or empty. Fix the taxonomy (triage-bootstrap.ps1 or triage.json), then re-run triage-signals.ps1."
}
if (@($signals.taxonomy.missing_labels).Count -gt 0) {
    $missing = @($signals.taxonomy.missing_labels) -join ', '
    throw "Signals file was generated with missing taxonomy labels: $missing. Fix the taxonomy gate first (re-run triage-signals.ps1), then regenerate this report."
}

# Taxonomy-driven label helpers (shared with the other scripts and the tests).
. (Join-Path $PSScriptRoot 'triage-helpers.ps1')

# ─── helpers ────────────────────────────────────────────────────────────────

function ConvertTo-HtmlText {
    <# Escapes the five XML-significant characters so titles cannot break the page. #>
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    return $Text.
        Replace('&', '&amp;').
        Replace('<', '&lt;').
        Replace('>', '&gt;').
        Replace('"', '&quot;').
        Replace("'", '&#39;')
}

function Get-IssueLink {
    param([int]$Number, [string]$Text)
    $label = if ($Text) { $Text } else { "#$Number" }
    $repoEsc = ConvertTo-HtmlText $Repo
    return "<a class=""issue"" href=""https://github.com/$repoEsc/issues/$Number"" target=""_blank"" rel=""noopener"">$(ConvertTo-HtmlText $label)</a>"
}

function Get-PriorityBadge {
    param([string]$Priority)
    if (-not $Priority) { return '<span class="badge p-none">unlabeled</span>' }
    $p = if ($tax.priority_prefix) { $Priority -replace [regex]::Escape($tax.priority_prefix), '' } else { $Priority }
    $pEsc = ConvertTo-HtmlText $p
    return "<span class=""badge p-$pEsc"">$pEsc</span>"
}

function Get-AreaBadges {
    param($Areas)
    if (-not $Areas -or @($Areas).Count -eq 0) { return '<span class="muted">none</span>' }
    $strip = if ($tax.area_prefix) { [regex]::Escape($tax.area_prefix) } else { '(?!x)x' }
    return (@($Areas) | ForEach-Object { "<span class=""badge area"">$(ConvertTo-HtmlText ($_ -replace $strip, ''))</span>" }) -join ' '
}

function Get-FlagBadges {
    param($Flags)
    if (-not $Flags -or @($Flags).Count -eq 0) { return '' }
    return (@($Flags) | ForEach-Object { "<span class=""badge flag"">$(ConvertTo-HtmlText $_)</span>" }) -join ' '
}

function Get-Section {
    param(
        [string]$Marker,
        [string]$Title,
        [int]$Count,
        [string]$Body,
        [string]$Note = ''
    )
    if ($Count -eq 0) {
        return @"
<section class="card empty">
  <h2><span class="marker">$Marker</span> $Title <span class="count">0</span></h2>
  <p class="muted">None — nothing to action here.</p>
</section>
"@
    }
    $noteHtml = if ($Note) { "<p class=""note"">$Note</p>" } else { '' }
    return @"
<section class="card">
  <h2><span class="marker">$Marker</span> $Title <span class="count">$Count</span></h2>
  $noteHtml
  $Body
</section>
"@
}

# ─── section bodies ─────────────────────────────────────────────────────────

$s = $signals.summary
$g = $signals.grooming

# Overdue
$overdueRows = @($g.overdue | ForEach-Object {
    $d = [int]$_.days_overdue
    "<tr><td class=""num"">$(Get-IssueLink $_.number)</td><td>$(ConvertTo-HtmlText $_.title)</td><td class=""mono"">$(ConvertTo-HtmlText $_.due)</td><td class=""warn"">${d}d overdue</td></tr>"
})
$overdueBody = if ($overdueRows.Count) {
    @"
<table>
  <thead><tr><th>Issue</th><th>Title</th><th>Due</th><th>Status</th></tr></thead>
  <tbody>$($overdueRows -join "`n")</tbody>
</table>
"@
} else { '' }

# Stale dependency references
$staleRows = @($g.stale_dependency_refs | ForEach-Object {
    $refs = (@($_.refs) | ForEach-Object { Get-IssueLink $_ "#$_" }) -join ', '
    "<tr><td class=""num"">$(Get-IssueLink $_.number)</td><td>$(ConvertTo-HtmlText $_.title)</td><td>$refs</td></tr>"
})
$staleBody = if ($staleRows.Count) {
    @"
<table>
  <thead><tr><th>Issue</th><th>Title</th><th>Cites (all closed)</th></tr></thead>
  <tbody>$($staleRows -join "`n")</tbody>
</table>
"@
} else { '' }

# Needs triage queue
$queueRows = @($signals.queue | ForEach-Object {
    $proposed = if ($_.form_proposed_priority) { $_.form_proposed_priority } else { '<span class="muted">—</span>' }
    $dedup = if (@($_.dedup_candidates).Count -gt 0) {
        '<span class="warn">possible dup of ' + ((@($_.dedup_candidates) | ForEach-Object { Get-IssueLink $_.number "#$($_.number)" }) -join ', ') + '</span>'
    } else { '' }
    "<tr><td class=""num"">$(Get-IssueLink $_.number)</td><td>$(ConvertTo-HtmlText $_.title)</td><td class=""mono"">$proposed</td><td>$(Get-AreaBadges $_.form_proposed_area)</td><td class=""mono"">$($_.age_days)d</td><td>$dedup</td></tr>"
})
$queueBody = if ($queueRows.Count) {
    @"
<table>
  <thead><tr><th>Issue</th><th>Title</th><th>Proposed</th><th>Proposed area</th><th>Age</th><th>Dedup</th></tr></thead>
  <tbody>$($queueRows -join "`n")</tbody>
</table>
"@
} else { '' }

# Missing blocked label
$missingRows = @($g.missing_blocked_label | ForEach-Object {
    $deps = (@($_.open_deps) | ForEach-Object { Get-IssueLink $_ "#$_" }) -join ', '
    "<tr><td class=""num"">$(Get-IssueLink $_.number)</td><td>$(ConvertTo-HtmlText $_.title)</td><td>$deps</td></tr>"
})
$missingBody = if ($missingRows.Count) {
    @"
<table>
  <thead><tr><th>Issue</th><th>Title</th><th>Open dependency</th></tr></thead>
  <tbody>$($missingRows -join "`n")</tbody>
</table>
"@
} else { '' }

# Blocked chains
$chainRows = @($g.blocked_chains | ForEach-Object {
    $unblocks = (@($_.unblocks) | ForEach-Object { Get-IssueLink $_ "#$_" }) -join ', '
    $bar = [Math]::Min(100, [int]$_.unblocks.Count * 12)
    "<tr><td class=""num"">$(Get-IssueLink $_.blocker)</td><td>$(ConvertTo-HtmlText $_.title)</td><td class=""mono"">$($_.unblocks.Count)</td><td>$unblocks</td></tr>"
})
$chainBody = if ($chainRows.Count) {
    @"
<table>
  <thead><tr><th>Blocker</th><th>Title</th><th>Unblocks</th><th>Which</th></tr></thead>
  <tbody>$($chainRows -join "`n")</tbody>
</table>
"@
} else { '' }

# Low-priority accumulation (lowest tier of the priority axis)
$lowBody = if (@($g.low_priority_accumulation).Count -gt 0) {
    $links = (@($g.low_priority_accumulation) | ForEach-Object { Get-IssueLink $_ "#$_" }) -join ' '
    "<p>$links</p>"
} else { '' }

# Stale top-priority items
$staleBody2 = if (@($g.stale_priority).Count -gt 0) {
    $rows = @($g.stale_priority | ForEach-Object {
        "<tr><td class=""num"">$(Get-IssueLink $_.number)</td><td>$(ConvertTo-HtmlText $_.title)</td><td class=""mono"">$($_.age_days)d</td></tr>"
    })
    @"
<table>
  <thead><tr><th>Issue</th><th>Title</th><th>Age</th></tr></thead>
  <tbody>$($rows -join "`n")</tbody>
</table>
"@
} else { '' }

# ─── full backlog (collapsible) ─────────────────────────────────────────────

$backlogScript = Join-Path $PSScriptRoot 'triage-queue.ps1'
$backlog = @()
if (Test-Path $backlogScript) {
    $allIssues = & gh issue list --repo $Repo --state open --limit 1000 --json number,title,labels,createdAt
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Could not list open issues for the backlog section (gh exit $LASTEXITCODE); the backlog below is incomplete."
    }
    elseif ($allIssues) {
        $allIssues = $allIssues | ConvertFrom-Json
        $priOrder = @{}
        $n = 0; foreach ($lvl in $tax.priority_levels) { $priOrder[$lvl.code] = $n; $n++ }
        $priOrder['unlabeled'] = 999
        $areaStrip = if ($tax.area_prefix) { [regex]::Escape($tax.area_prefix) } else { '(?!x)x' }
        foreach ($grp in ($allIssues | Group-Object {
            $lvl = Get-PriorityLevel ($_.labels | ForEach-Object { $_.name }) $tax
            if ($lvl) { $lvl.code } else { 'unlabeled' }
        } | Sort-Object { $priOrder[$_.Name] })) {
            $rows = @($grp.Group | ForEach-Object {
                $names = @($_.labels | ForEach-Object { $_.name })
                $blocked = if (Test-HasLabel $names $tax.blocked) { '<span class="badge flag">blocked</span>' } else { '' }
                $areas = (@(Get-LabelsByPrefix $names $tax.area_prefix) | ForEach-Object { "<span class=""badge area"">$(ConvertTo-HtmlText ($_ -replace $areaStrip, ''))</span>" }) -join ' '
                "<tr><td class=""num"">$(Get-IssueLink $_.number)</td><td>$(ConvertTo-HtmlText $_.title)</td><td>$areas</td><td>$blocked</td></tr>"
            })
            $backlog += @"
<h3>$(ConvertTo-HtmlText $grp.Name) <span class="count">$($grp.Count)</span></h3>
<table>
  <thead><tr><th>Issue</th><th>Title</th><th>Area</th><th>Flags</th></tr></thead>
  <tbody>$($rows -join "`n")</tbody>
</table>
"@
        }
    }
}

# ─── assemble ───────────────────────────────────────────────────────────────

$chips = (@($tax.priority_levels | ForEach-Object {
    $code = $_.code
    $cnt = $s.priority_counts.$code
    "<span class=""chip"">$code <b>$cnt</b></span>"
}) -join '')

$attention = @($s.overdue + $s.needs_triage + $s.stale_dependency_refs + $s.missing_blocked_label + $s.unlabeled)

$repoEsc = ConvertTo-HtmlText $Repo
$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Triage Report — $repoEsc</title>
<style>
  :root {
    --bg: oklch(98% 0.005 250);
    --surface: oklch(100% 0 0);
    --fg: oklch(22% 0.02 240);
    --muted: oklch(50% 0.018 240);
    --border: oklch(90% 0.008 240);
    --accent: oklch(58% 0.16 145);
    --positive: oklch(44% 0.14 145);
    --negative: oklch(47% 0.17 25);
    --font-display: -apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', system-ui, sans-serif;
    --font-mono: 'JetBrains Mono', 'IBM Plex Mono', ui-monospace, Menlo, monospace;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; padding: 2rem 1.5rem 4rem;
    background: var(--bg); color: var(--fg);
    font-family: var(--font-display); font-size: 14px; line-height: 1.5;
  }
  .wrap { max-width: 1100px; margin: 0 auto; }
  header h1 { margin: 0 0 .25rem; font-size: 1.5rem; font-weight: 650; letter-spacing: -.01em; }
  .meta { font-family: var(--font-mono); font-size: 11px; color: var(--muted); text-transform: uppercase; letter-spacing: .06em; }
  .chips { display: flex; gap: .5rem; flex-wrap: wrap; margin: 1rem 0 1.5rem; }
  .chip {
    font-family: var(--font-mono); font-size: 11px; padding: .2rem .5rem;
    border: 1px solid var(--border); background: var(--surface); border-radius: 0;
  }
  .chip b { color: var(--fg); }
  .banner {
    border: 1px solid var(--border); background: var(--surface);
    padding: .75rem 1rem; margin-bottom: 1.5rem; border-radius: 0;
    font-family: var(--font-mono); font-size: 12px;
  }
  .banner.attention { border-left: 3px solid var(--negative); }
  .banner.clear { border-left: 3px solid var(--positive); }
  .card {
    border: 1px solid var(--border); background: var(--surface);
    padding: 1rem 1.25rem 1.25rem; margin-bottom: 1rem; border-radius: 0;
  }
  .card.empty { opacity: .75; }
  .card h2 {
    margin: 0 0 .75rem; font-size: .8rem; font-weight: 600;
    text-transform: uppercase; letter-spacing: .08em; font-family: var(--font-mono);
    display: flex; align-items: center; gap: .5rem;
  }
  .card h3 {
    margin: 1rem 0 .5rem; font-size: .75rem; font-weight: 600;
    text-transform: uppercase; letter-spacing: .08em; font-family: var(--font-mono);
    color: var(--muted);
  }
  .marker { color: var(--muted); }
  .count {
    font-size: 10px; padding: .1rem .4rem; border: 1px solid var(--border);
    color: var(--muted); border-radius: 0;
  }
  .note { font-size: 12px; color: var(--muted); margin: 0 0 .75rem; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; }
  th {
    text-align: left; font-family: var(--font-mono); font-size: 10px; font-weight: 500;
    text-transform: uppercase; letter-spacing: .07em; color: var(--muted);
    padding: .4rem .6rem; border-bottom: 1px solid var(--border);
  }
  td { padding: .45rem .6rem; border-bottom: 1px solid var(--border); vertical-align: top; }
  tr:last-child td { border-bottom: 0; }
  td.num { font-family: var(--font-mono); white-space: nowrap; width: 1%; }
  td.mono, .mono { font-family: var(--font-mono); font-size: 12px; }
  a.issue { color: var(--fg); text-decoration: none; border-bottom: 1px solid var(--accent); font-family: var(--font-mono); }
  a.issue:hover { background: oklch(96% 0.03 145); }
  .badge {
    display: inline-block; font-family: var(--font-mono); font-size: 10px;
    padding: .1rem .35rem; border: 1px solid var(--border); border-radius: 0;
    text-transform: lowercase; letter-spacing: .03em;
  }
  .badge.area { color: var(--muted); }
  .badge.flag { border-color: var(--negative); color: var(--negative); }
  .badge.p-P0 { border-color: var(--negative); color: var(--negative); }
  .badge.p-P1 { border-color: oklch(55% 0.15 45); color: oklch(45% 0.15 45); }
  .badge.p-P2 { border-color: oklch(70% 0.12 85); color: oklch(55% 0.12 85); }
  .badge.p-P3 { border-color: var(--border); color: var(--muted); }
  /* Fallback for custom priority codes (e.g. critical/high/low): any p-* badge
     not matched above still reads as a priority badge. */
  .badge[class*="p-"] { border-color: oklch(55% 0.15 45); color: oklch(45% 0.15 45); }
  .badge.p-none { color: var(--muted); border-color: var(--border); }
  .warn { color: var(--negative); font-family: var(--font-mono); font-size: 11px; }
  .muted { color: var(--muted); }
  details { border: 1px solid var(--border); background: var(--surface); padding: .75rem 1.25rem 1.25rem; border-radius: 0; }
  summary {
    cursor: pointer; font-family: var(--font-mono); font-size: .75rem; font-weight: 600;
    text-transform: uppercase; letter-spacing: .08em;
  }
  footer {
    margin-top: 2rem; padding-top: 1rem; border-top: 1px solid var(--border);
    font-family: var(--font-mono); font-size: 11px; color: var(--muted);
  }
  footer code { font-size: 11px; }
</style>
</head>
<body>
<div class="wrap">

<header>
  <h1>Triage Report</h1>
  <div class="meta">$repoEsc · generated $(ConvertTo-HtmlText $signals.generated_at) · schema v$($signals.schema_version)</div>
</header>

<div class="chips">$chips</div>

$(if ($attention -gt 0) {
  "<div class=""banner attention"">$attention item(s) need attention — $($s.overdue) overdue · $($s.needs_triage) awaiting triage · $($s.stale_dependency_refs) stale dependency refs · $($s.missing_blocked_label) missing blocked label · $($s.unlabeled) unlabeled</div>"
} else {
  '<div class="banner clear">Backlog is clean — nothing awaiting triage, no stale references, no label inconsistencies.</div>'
})

$(Get-Section -Marker '⚠' -Title 'Overdue' -Count $s.overdue -Body $overdueBody -Note 'Due dates are parsed from the configured due marker in issue bodies.')

$(Get-Section -Marker '♻' -Title 'Stale dependency references' -Count $s.stale_dependency_refs -Body $staleBody -Note "Body cites a <code>Depends on</code> / <code>Blocked by</code> issue that is now closed. The <code>$($tax.blocked)</code> label is correctly absent; the body text is stale.")

$(Get-Section -Marker '◆' -Title 'Awaiting triage' -Count $s.needs_triage -Body $queueBody -Note "Open issues carrying <code>$($tax.needs_triage)</code>. <em>Proposed</em> is the answer given in the issue form — blank for CLI-created issues.")

$(Get-Section -Marker '◆' -Title 'Missing blocked label' -Count $s.missing_blocked_label -Body $missingBody -Note "Body cites an open dependency but the <code>$($tax.blocked)</code> label is not applied.")

$(Get-Section -Marker '◆' -Title 'Blocked chains' -Count @($g.blocked_chains).Count -Body $chainBody -Note 'Closing the blocker unblocks the listed issues. Sorted by how much it unblocks.')

$(Get-Section -Marker '◆' -Title 'Low-priority accumulation' -Count @($g.low_priority_accumulation).Count -Body $lowBody -Note 'Issues at the bottom of the priority axis — candidates for <code>wontfix</code> if they stop earning their place.')

$(Get-Section -Marker '◆' -Title 'Stale top-priority' -Count @($g.stale_priority).Count -Body $staleBody2 -Note "A $($tax.stale_priority_codes -join '/') item older than $($tax.stale_age_days) days is probably misprioritized or blocked.")

<details>
  <summary>Full open backlog by priority ($($s.open_total))</summary>
  $($backlog -join "`n")
</details>

<footer>
  Regenerate: <code>pwsh "$signalsScript" -Json -OutFile "$SignalsFile"</code> then
  <code>pwsh "$PSCommandPath"</code><br>
  Machine-readable payload: <code>$SignalsFile</code>
</footer>

</div>
</body>
</html>
"@

$dir = Split-Path -Parent $OutFile
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$full = if ([System.IO.Path]::IsPathRooted($OutFile)) { $OutFile } else { (Join-Path (Get-Location).Path $OutFile) }
[System.IO.File]::WriteAllText($full, $html, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Report written: $full"
Write-Host "Open with: file:///$($full -replace '\\','/')"
