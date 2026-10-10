#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Create the required triage taxonomy labels in a GitHub repo.

.DESCRIPTION
    Reads the resolved taxonomy (same discovery as the queue/signals scripts)
    and creates every required label that does not yet exist, via
    `gh label create`. Idempotent: existing labels are skipped, never updated.
    After this succeeds, the taxonomy gate in triage-queue.ps1 and
    triage-signals.ps1 passes.

    Optionally writes an example triage.json mapping for repos that prefer
    their own label names over the canonical ones.

.PARAMETER Repo
    Target repository in owner/name form. Defaults to the config's repo, then the
    origin remote of the current checkout.

.PARAMETER Config
    Explicit triage config path (same discovery as the other scripts).

.PARAMETER WriteExampleConfig
    Write the resolved taxonomy to this path as an example triage.json the repo
    can own and adapt (maps each concept to a label name).

.PARAMETER DryRun
    Print the gh commands without running them.

.EXAMPLE
    .\scripts\triage-bootstrap.ps1 -Repo owner/name
    .\scripts\triage-bootstrap.ps1 -Repo owner/name -DryRun
    .\scripts\triage-bootstrap.ps1 -Repo owner/name -WriteExampleConfig .github/triage.json
#>
[CmdletBinding()]
param(
    [string]$Repo = "",
    [string]$Config,
    [string]$WriteExampleConfig,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'triage-helpers.ps1')

$cfgPath = Resolve-TriageConfigPath -Explicit $Config -RepoRoot (Get-Location).Path -SkillRoot (Split-Path -Parent $PSScriptRoot)
$cfg = $null
if ($cfgPath) {
    try { $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json }
    catch { throw "Could not parse triage config '$cfgPath': $($_.Exception.Message). Fix the JSON or point -Config at a valid file." }
}

$Repo = Resolve-TriageRepo -Repo $Repo -Config $cfg -RemoteUrl (Get-TriageOriginRemoteUrl)
$tax = Resolve-Taxonomy -Config $cfg

# Never create labels from a guessed label set: Get-TriageRepoLabels throws when
# `gh label list` fails, so "existing labels are skipped, never updated" holds.
$existingLabels = @(Get-TriageRepoLabels -Repo $Repo)

$required = @(Get-TriageRequiredLabels -Taxonomy $tax)
$missing = @($required | Where-Object { $existingLabels -notcontains $_.name })

if ($WriteExampleConfig) {
    $example = [ordered]@{
        repo                  = $Repo
        needs_triage          = $tax.needs_triage
        blocked               = $tax.blocked
        owner_decision        = $tax.owner_decision
        priority_prefix       = $tax.priority_prefix
        priority_levels       = @($tax.priority_levels | ForEach-Object { [ordered]@{ code = $_.code; label = $_.label; meaning = $_.meaning } })
        area_prefix           = $tax.area_prefix
        type_prefix           = $tax.type_prefix
        form_priority_heading = $tax.form_priority_heading
        form_area_heading     = $tax.form_area_heading
        roadmap_pattern       = $tax.roadmap_pattern
        goal_pattern          = $tax.goal_pattern
        due_pattern           = $tax.due_pattern
        stale_priority_codes  = @($tax.stale_priority_codes)
        stale_age_days        = $tax.stale_age_days
    }
    $payload = $example | ConvertTo-Json -Depth 5
    if ($DryRun) {
        Write-Host "[dry-run] would write $WriteExampleConfig`:"
        Write-Host $payload
    }
    else {
        $dir = Split-Path -Parent $WriteExampleConfig
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $payload | Set-Content -Path $WriteExampleConfig -Encoding utf8
        Write-Host "Example config written to $WriteExampleConfig - adapt the label names to your repo and keep it under version control."
    }
}

if ($missing.Count -eq 0) {
    Write-Host "Taxonomy gate already passes for $Repo - all $($required.Count) required labels exist."
    return
}

Write-Host "Creating $($missing.Count) missing label(s) in ${Repo}:"
foreach ($spec in $missing) {
    $cmd = "gh label create '$($spec.name)' --repo $Repo --color $($spec.color) --description '$($spec.description)'"
    if ($DryRun) {
        Write-Host "  [dry-run] $cmd"
        continue
    }
    Write-Host "  + $($spec.name)"
    gh label create $spec.name --repo $Repo --color $spec.color --description $spec.description
    if ($LASTEXITCODE -ne 0) { throw "gh label create failed for '$($spec.name)' (exit $LASTEXITCODE)" }
}

if (-not $DryRun) {
    Write-Host "Done. Re-run the queue or signals script - the taxonomy gate should now pass."
}

