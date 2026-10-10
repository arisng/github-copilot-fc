#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Render the issue triage queue, or the full grooming view.

.DESCRIPTION
    Default mode lists open issues carrying the configured needs-triage label,
    showing the priority and area proposed in the issue form (parsed from the
    rendered body) next to the issue age. -All switches to the grooming view:
    every open issue grouped by its applied priority label (taxonomy order),
    oldest first, with blocked items flagged.

    Read-only: this script never mutates issues. Label changes go through
    `gh issue edit` per the triage skill (.github/skills/triage/SKILL.md).

.PARAMETER Repo
    Target repository in owner/name form. Defaults to the config's repo, then the
    origin remote of the current checkout.

.PARAMETER All
    Show the full open backlog grouped by priority instead of only the
    needs-triage queue.

.EXAMPLE
    pwsh .github/skills/triage/scripts/triage-queue.ps1
    pwsh .github/skills/triage/scripts/triage-queue.ps1 -All
#>
[CmdletBinding()]
param(
    [string]$Repo = "",
    [switch]$All,
    [string]$Config
)

$ErrorActionPreference = "Stop"

# gh's --limit caps the page; warn rather than silently truncate the backlog.
$PageLimit = 1000

# Shared pure helpers + the taxonomy model (single source of truth, also used by tests).
. (Join-Path $PSScriptRoot 'triage-helpers.ps1')

# Config discovery: explicit -Config wins; otherwise repo-local config in the
# checkout root (triage.json, .triage.json, .github/triage.json); otherwise a
# triage.json co-located with the skill. A missing auto-discovered config is fine
# (defaults apply); a missing explicit -Config is not.
$cfgPath = Resolve-TriageConfigPath -Explicit $Config -RepoRoot (Get-Location).Path -SkillRoot (Split-Path -Parent $PSScriptRoot)
$cfg = $null
if ($cfgPath) {
    try { $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json }
    catch { Write-Warning "Could not parse triage config '$cfgPath': $($_.Exception.Message); using defaults." }
}

# -Repo (when passed) is authoritative; otherwise the config's repo, then the
# origin remote of the current checkout. No silent default repo: a wrong guess
# would quietly query an unrelated repository.
$Repo = Resolve-TriageRepo -Repo $Repo -Config $cfg -RemoteUrl (Get-TriageOriginRemoteUrl)
$tax = Resolve-Taxonomy -Config $cfg

# Validate the configured labels against the repo's real label set. Without this,
# a stale config (e.g. the fin-ops defaults against a repo using status/triage)
# renders an empty queue as if there were nothing to triage.
try {
    $existingLabels = @((gh label list --repo $Repo --limit 1000 --json name | ConvertFrom-Json) | ForEach-Object { $_.name })
    $tax = Resolve-Taxonomy -Config $cfg -ExistingLabels $existingLabels
    if (@($tax.missing_labels).Count -gt 0) {
        Write-Warning ("Triage config references labels not present in ${Repo}: " + ($tax.missing_labels -join ', ') + " - check -Config / triage.json; the queue may be wrong or empty.")
    }
}
catch {
    Write-Warning "Could not list labels for $Repo (skipping taxonomy validation): $($_.Exception.Message)"
}

$issues = (gh issue list --repo $Repo --state open --limit $PageLimit `
              --json number,title,createdAt,labels,body) | ConvertFrom-Json

# A gh failure (network, auth) exits non-zero and prints to stderr; without this check
# the failure is indistinguishable from an empty backlog.
if ($LASTEXITCODE -ne 0) {
    throw "gh issue list failed for $Repo (exit $LASTEXITCODE)"
}

# Filter client-side: GitHub's --label search index lags a few seconds after a label
# change, so a just-triaged issue would otherwise vanish from the queue.
if (-not $All) {
    $issues = $issues | Where-Object {
        Test-HasLabel ($_.labels | ForEach-Object { $_.name }) $tax.needs_triage
    }
}

if (-not $issues) {
    if ($All) { Write-Host "No open issues." }
    else { Write-Host "Triage queue empty - no open issue carries '$($tax.needs_triage)'." }
    return
}

if ($issues.Count -ge $PageLimit) {
    Write-Warning "Fetched $PageLimit issues (the page limit) - the backlog may be larger than shown."
}

$rows = foreach ($issue in $issues) {
    $names = @($issue.labels | ForEach-Object { $_.name })
    $priLevel = Get-PriorityLevel $names $tax
    [pscustomobject]@{
        '#'      = $issue.number
        Age      = Get-AgeDays -CreatedAt $issue.createdAt
        Title    = $issue.title
        Priority = if ($priLevel) { $priLevel.code } else { 'unlabeled' }
        Proposed = Get-ProposedPriority -Body $issue.body -Heading $tax.form_priority_heading -Codes $tax.priority_codes
        Area     = ((Get-LabelsByPrefix $names $tax.area_prefix) -replace [regex]::Escape($tax.area_prefix), '') -join ','
        Blocked  = if (Test-HasLabel $names $tax.blocked) { 'BLOCKED' } else { '' }
    }
}

# Explicit widths, no -AutoSize: -AutoSize sizes Title to its full content, which pushes
# the trailing columns past the Out-String budget and silently drops them.
$queueColumns = @(
    @{ Label = '#';        Expression = { $_.'#' };      Width = 5  }
    @{ Label = 'Age';      Expression = { $_.Age };      Width = 5  }
    @{ Label = 'Title';    Expression = { $_.Title };    Width = 62 }
    @{ Label = 'Proposed'; Expression = { $_.Proposed }; Width = 10 }
    @{ Label = 'Area';     Expression = { $_.Area };     Width = 22 }
)
$groomColumns = @(
    @{ Label = '#';       Expression = { $_.'#' };     Width = 5  }
    @{ Label = 'Age';     Expression = { $_.Age };     Width = 5  }
    @{ Label = 'Title';   Expression = { $_.Title };   Width = 74 }
    @{ Label = 'Blocked'; Expression = { $_.Blocked }; Width = 10 }
)

function Show-Table {
    param($Rows, $Columns)
    # Returns the rendered table so callers (and tests) can capture it.
    $Rows |
        Sort-Object @{ Expression = 'Age'; Descending = $true } |
        Format-Table $Columns -Wrap |
        Out-String -Width 200 |
        ForEach-Object { $_.TrimEnd() }
}

if ($All) {
    Write-Host "Open backlog: $($rows.Count) issue(s), grouped by applied priority (oldest first)."
    # Order groups by the taxonomy's priority order (highest first), not alphabetically,
    # so code schemes like critical/high/low sort correctly.
    $priOrder = @{}
    $n = 0; foreach ($lvl in $tax.priority_levels) { $priOrder[$lvl.code] = $n; $n++ }
    $priOrder['unlabeled'] = 999
    foreach ($group in ($rows | Group-Object Priority | Sort-Object { $priOrder[$_.Name] })) {
        Write-Host ""
        Write-Host "== $($group.Name) ($($group.Count)) =="
        Show-Table -Rows $group.Group -Columns $groomColumns | Write-Host
    }
}
else {
    Write-Host "Triage queue: $($rows.Count) issue(s) carrying '$($tax.needs_triage)' (oldest first)."
    Write-Host "'Proposed' is the answer given in the issue form - blank for issues filed"
    Write-Host "outside the web templates (e.g. migrated or CLI-created)."
    Write-Host ""
    Show-Table -Rows $rows -Columns $queueColumns | Write-Host
}
