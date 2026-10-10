#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Collect triage signals from a GitHub issue tracker.

.DESCRIPTION
    Fetches every issue (open and closed) in ONE `gh` call and derives all triage
    signals locally, so the agent never has to make per-issue round trips:

      - the needs-triage queue, with form-proposed priority/area parsed from bodies
      - dependency state resolution (open vs closed) for every `#N` reference
      - label/body consistency (blocked label vs "Depends on"/"Blocked by" text)
      - stale dependency references (body cites an issue that is now closed)
      - blocked chains (which single issue unblocks the most work)
      - overdue items (parsed from `**Due:** YYYY-MM-DD` in bodies)
      - dedup candidates (title-token overlap)
      - roadmap (R#) and north-star goal (G1-G5) references

    Emits JSON with -Json (the machine contract consumed by triage-report.ps1 and by
    the agent), or a compact human summary by default.

    Read-only: never mutates issues.

.PARAMETER Repo
    Target repository in owner/name form. Defaults to the config's repo, then the
    origin remote of the current checkout.

.PARAMETER Json
    Emit the full signals payload as JSON instead of a summary.

.PARAMETER OutFile
    Write output to this path instead of the pipeline.

.PARAMETER Now
    Reference time for age/overdue math. Defaults to UtcNow; exposed for tests.

.EXAMPLE
    pwsh .github/skills/triage/scripts/triage-signals.ps1
    pwsh .github/skills/triage/scripts/triage-signals.ps1 -Json -OutFile cache/triage-signals.json
#>
[CmdletBinding()]
param(
    [string]$Repo = "",
    [switch]$Json,
    [string]$OutFile,
    [datetime]$Now = [datetime]::UtcNow,
    [string]$Config,
    [switch]$NoLabelCheck
)

$ErrorActionPreference = "Stop"

# NOTE: plain PowerShell arrays are used throughout rather than
# System.Collections.Generic.List[T]. `@()` around a List[object] throws
# "Argument types do not match" in PowerShell, and List[int] rejects the Int64
# that ConvertFrom-Json produces for issue numbers.

# ─── pure helpers (shared with the tests via triage-helpers.ps1) ──────────────

. (Join-Path $PSScriptRoot 'triage-helpers.ps1')

# ─── taxonomy (per-repo label model) ─────────────────────────────────────────

# Config discovery: an explicit -Config wins; otherwise repo-local config in the
# checkout root (triage.json, .triage.json, .github/triage.json); otherwise a
# triage.json co-located with the skill (portable - copy the skill folder and the
# config travels with it). A missing auto-discovered config is fine (defaults
# apply); a missing explicit -Config is not.
$cfgPath = Resolve-TriageConfigPath -Explicit $Config -RepoRoot (Get-Location).Path -SkillRoot (Split-Path -Parent $PSScriptRoot)
$cfg = $null
if ($cfgPath) {
    try { $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json }
    catch { throw "Could not parse triage config '$cfgPath': $($_.Exception.Message). Fix the JSON or point -Config at a valid file." }
}

# -Repo (when passed) is authoritative; otherwise the config's repo, then the
# origin remote of the current checkout. No silent default repo: a wrong guess
# would quietly query an unrelated repository.
$Repo = Resolve-TriageRepo -Repo $Repo -Config $cfg -RemoteUrl (Get-TriageOriginRemoteUrl)

# ─── fetch (issues + the repo's label set) ───────────────────────────────────

$raw = @(gh issue list --repo $Repo --state all --limit 1000 `
            --json number,title,state,createdAt,labels,body | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) { throw "gh issue list failed for $Repo (exit $LASTEXITCODE)" }

# Taxonomy gate: the resolved labels must exist in the repo before any signal is
# derived. -NoLabelCheck skips the gate (offline/tests - output may be wrong) and
# stamps label_check='skipped' into the payload so consumers (triage-report.ps1)
# can refuse it.
if ($NoLabelCheck) {
    Write-Warning 'Taxonomy gate skipped via -NoLabelCheck; signals may be wrong or empty.'
    $tax = Resolve-Taxonomy -Config $cfg
}
else {
    $existingLabels = @(Get-TriageRepoLabels -Repo $Repo)
    $tax = Resolve-Taxonomy -Config $cfg -ExistingLabels $existingLabels
    if (@($tax.missing_labels).Count -gt 0) {
        throw (Format-TriageGateError -Repo $Repo -ConfigPath $cfgPath -MissingLabels @($tax.missing_labels) -Taxonomy $tax)
    }
}

# Local lookup so dependency resolution costs nothing extra.
# Keys are normalised to [int]: ConvertFrom-Json yields Int64, and a hashtable
# lookup with a different numeric type silently returns $null.
$byNumber = @{}
foreach ($i in $raw) { $byNumber[[int]$i.number] = $i }

# ─── derive signals ──────────────────────────────────────────────────────────

$open = @($raw | Where-Object { $_.state -eq 'OPEN' })

$queue = @()
$staleDeps = @()
$missingBlocked = @()
$overdue = @()
$unblocks = @{}

foreach ($i in $open) {
    $names = @($i.labels | ForEach-Object { $_.name })
    $refs = Get-IssueRefs $i.body
    $deps = Get-DependencyRefs $i.body
    $openDeps = @($deps | Where-Object { $byNumber.ContainsKey($_) -and $byNumber[$_].state -eq 'OPEN' })
    # When the repo has no blocked concept, there is no label to be missing.
    $hasBlocked = if ($tax.blocked) { Test-HasLabel $names $tax.blocked } else { $true }

    if ($openDeps.Count -gt 0 -and -not $hasBlocked) {
        $missingBlocked += [pscustomobject]@{
            number = [int]$i.number; title = $i.title; open_deps = $openDeps
        }
    }
    if ($deps.Count -gt 0 -and $openDeps.Count -eq 0) {
        $staleDeps += [pscustomobject]@{
            number = [int]$i.number; title = $i.title; refs = $deps; all_closed = $true
        }
    }
    foreach ($d in $openDeps) {
        if (-not $unblocks.ContainsKey($d)) { $unblocks[$d] = @() }
        $unblocks[$d] += [int]$i.number
    }

    $due = Get-DueInfo -Body $i.body -Reference $Now -Pattern $tax.due_pattern
    if ($due -and $due.is_overdue) {
        $overdue += [pscustomobject]@{
            number = [int]$i.number; title = $i.title; due = $due.due; days_overdue = $due.days_overdue
        }
    }

    if (Test-HasLabel $names $tax.needs_triage) {
        $flat = (($i.body -replace '\s+', ' ').Trim())
        $priLevel = Get-PriorityLevel $names $tax
        $flags = @()
        if (Test-HasLabel $names $tax.needs_triage)   { $flags += $tax.needs_triage }
        if (Test-HasLabel $names $tax.blocked)        { $flags += $tax.blocked }
        if (Test-HasLabel $names $tax.owner_decision) { $flags += $tax.owner_decision }
        $queue += [pscustomobject]@{
            number                 = [int]$i.number
            title                  = $i.title
            age_days               = Get-AgeDays -CreatedAt $i.createdAt -Reference $Now
            labels                 = $names
            type                   = (Get-LabelsByPrefix $names $tax.type_prefix | Select-Object -First 1)
            priority               = if ($priLevel) { $priLevel.code } else { $null }
            priority_label         = if ($priLevel) { $priLevel.label } else { $null }
            areas                  = @(Get-LabelsByPrefix $names $tax.area_prefix)
            flags                  = $flags
            form_proposed_priority = Get-ProposedPriority -Body $i.body -Heading $tax.form_priority_heading -Codes $tax.priority_codes
            form_proposed_area     = Get-ProposedArea -Body $i.body -Heading $tax.form_area_heading
            roadmap_refs           = if ($tax.roadmap_pattern) { @(Get-RoadmapRefs -Body $i.body -Pattern $tax.roadmap_pattern) } else { @() }
            goal_refs              = if ($tax.goal_pattern)    { @(Get-GoalRefs -Body $i.body -Pattern $tax.goal_pattern) }       else { @() }
            issue_refs             = $refs
            open_deps              = $openDeps
            dedup_candidates       = @()
            body_excerpt           = $flat.Substring(0, [Math]::Min(600, $flat.Length))
        }
    }
}

# Attach dedup candidates to queue entries.
$dedup = @(Get-DedupCandidates -Issues $raw)
foreach ($q in $queue) {
    $q.dedup_candidates = @($dedup |
        Where-Object { $_.a -eq $q.number -or $_.b -eq $q.number } |
        ForEach-Object {
            $other = if ($_.a -eq $q.number) { $_.b } else { $_.a }
            [pscustomobject]@{ number = $other; shared_terms = $_.shared_terms }
        })
}

$blockedChains = @($unblocks.GetEnumerator() | ForEach-Object {
    [pscustomobject]@{
        blocker  = [int]$_.Key
        unblocks = @($_.Value | Sort-Object)
        title    = $byNumber[[int]$_.Key].title
    }
} | Sort-Object { $_.unblocks.Count } -Descending)

# Lowest-tier accumulation: issues sitting at the bottom of the priority axis (the
# "nice to have" tier) - candidates for wontfix during grooming.
$lowPriority = @(Get-LowPriorityIssues $open $tax)

# A top-priority item (per stale_priority_codes) older than stale_age_days is probably
# misprioritized or silently blocked.
$stalePriority = @(Get-StalePriorityIssues $open $tax $Now)

function Get-PriorityCount {
    param([string]$Label)
    return @($open | Where-Object { (@($_.labels | ForEach-Object { $_.name }) -contains $Label) }).Count
}

# Per-tier open counts, keyed by the portable priority code (P0/P1/... or critical/...).
$priorityCounts = [ordered]@{}
foreach ($lvl in $tax.priority_levels) { $priorityCounts[$lvl.code] = Get-PriorityCount $lvl.label }

# Self-describing taxonomy block so the report (and any consumer) renders from the
# resolved model rather than hard-coded label names. Includes the parsing inputs
# (headings, patterns) so queue derivation is reconstructible from the payload alone.
$taxonomyOut = [pscustomobject]@{
    repo                  = $Repo
    source                = $tax.source
    config_path           = $cfgPath
    needs_triage          = $tax.needs_triage
    blocked               = $tax.blocked
    owner_decision        = $tax.owner_decision
    priority_prefix       = $tax.priority_prefix
    priority_codes        = @($tax.priority_codes)
    priority_levels       = @($tax.priority_levels | ForEach-Object {
        [pscustomobject]@{ code = $_.code; label = $_.label; meaning = $_.meaning }
    })
    area_prefix           = $tax.area_prefix
    type_prefix           = $tax.type_prefix
    form_priority_heading = $tax.form_priority_heading
    form_area_heading     = $tax.form_area_heading
    roadmap_pattern       = $tax.roadmap_pattern
    goal_pattern          = $tax.goal_pattern
    due_pattern           = $tax.due_pattern
    stale_priority_codes  = @($tax.stale_priority_codes)
    stale_age_days        = $tax.stale_age_days
    missing_labels        = @($tax.missing_labels)
    label_check           = if ($NoLabelCheck) { 'skipped' } else { 'passed' }
}

# Schema v3: schema v2 plus taxonomy.label_check ('passed' | 'skipped'), so a cache
# built with -NoLabelCheck is identifiable instead of looking gate-verified.
# v2: summary.priority_counts (was p0/p1/p2/p3), grooming.low_priority_accumulation
# (was p3_accumulation), grooming.stale_priority (was stale_p1), plus the taxonomy block.
$signals = [pscustomobject]@{
    schema_version = 3
    generated_at   = $Now.ToString('yyyy-MM-ddTHH:mm:ssZ')
    repo           = $Repo
    summary = [pscustomobject]@{
        open_total            = $open.Count
        closed_total          = ($raw.Count - $open.Count)
        needs_triage          = $queue.Count
        stale_dependency_refs = $staleDeps.Count
        missing_blocked_label = $missingBlocked.Count
        overdue               = $overdue.Count
        unlabeled             = @($open | Where-Object { @($_.labels | ForEach-Object { $_.name }).Count -eq 0 }).Count
        priority_counts       = $priorityCounts
    }
    taxonomy = $taxonomyOut
    queue    = @($queue | Sort-Object { $_.age_days } -Descending)
    grooming = [pscustomobject]@{
        stale_dependency_refs     = $staleDeps
        missing_blocked_label     = $missingBlocked
        blocked_chains            = $blockedChains
        overdue                   = $overdue
        low_priority_accumulation = $lowPriority
        stale_priority            = $stalePriority
    }
    dedup_candidates = $dedup
}

# ─── emit ────────────────────────────────────────────────────────────────────

if ($Json) {
    # NOTE: do not name this `$json` - PowerShell variables are case-insensitive, so it
    # would collide with the [switch]$Json parameter and fail to bind.
    $payload = $signals | ConvertTo-Json -Depth 8
    if ($OutFile) {
        $dir = Split-Path -Parent $OutFile
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $full = if ([System.IO.Path]::IsPathRooted($OutFile)) { $OutFile } else { (Join-Path (Get-Location).Path $OutFile) }
        [System.IO.File]::WriteAllText($full, $payload, (New-Object System.Text.UTF8Encoding($false)))
    }
    else { $payload }
}
else {
    $s = $signals.summary
    Write-Host "TRIAGE SIGNALS - $($s.open_total) open / $($s.closed_total) closed  [$Repo]"
    Write-Host "  needs triage ............. $($s.needs_triage)"
    Write-Host "  stale dependency refs .... $($s.stale_dependency_refs)"
    Write-Host "  missing blocked label .... $($s.missing_blocked_label)"
    Write-Host "  overdue .................. $($s.overdue)"
    Write-Host "  unlabeled ................ $($s.unlabeled)"
    $priLine = (@($tax.priority_levels | ForEach-Object { "$($_.code)=$($priorityCounts[$_.code])" }) -join '  ')
    Write-Host "  priority ................. $priLine"
    if ($signals.grooming.blocked_chains.Count -gt 0) {
        Write-Host ""
        Write-Host "  top blocked chains:"
        $signals.grooming.blocked_chains |
            Select-Object -First 3 |
            ForEach-Object { Write-Host "    #$($_.blocker) unblocks $($_.unblocks.Count) -> $($_.unblocks -join ', ')" }
    }
    Write-Host ""
    Write-Host "Full payload: add -Json (optionally -OutFile cache/triage-signals.json)"
}
