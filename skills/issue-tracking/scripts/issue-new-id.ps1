<#
.SYNOPSIS
    Collision-free issue-id allocator for the local-markdown issue tracker -
    reserves the next NNNN id atomically, manages outstanding reservations.

.DESCRIPTION
    Scope: ONLY the local-markdown tracker. Requires .github/issue-tracker.json
    with tracker=local-markdown (skill step 0 bootstraps it) and an existing
    issuesDir; refuses anything else.

    How ids stay unique across parallel sessions:
      - ids come from max(active + archived NNNN-*.md) + 1, skipping every
        outstanding lease, then are reserved with an exclusive file create in a
        machine-shared store keyed by the repo's normalized remote URL
        (<temp>/issue-id-leases/<sha1>) - every worktree AND every clone of this
        repo on this machine draws from one pool, so two racing sessions can
        never be handed the same id (the loser just takes the next one). No
        remote configured -> the git common dir (all worktrees of this clone);
        no git -> a per-repo-root temp bucket.
      - leases expire after -TtlHours (default 24) so a crashed session's
        reservation is reclaimed; expired leases are pruned on every run.
      - isolated machines cannot see each other's uncommitted issues; there the
        always-on duplicate-id lint (the repo's issue lint, pre-commit) refuses to
        let a collision land, and SKILL.md step 5's resolution protocol
        re-allocates the losing id before pushing.
      - refuses a store that already contains duplicate ids (consistency), and
        refuses ids beyond 9999 (the NNNN file grammar).

    Output (pipe rows): ID|NNNN + LEASE|<path> on success.

    Modes:
      default   allocate and reserve the next free id -> prints ID|NNNN
      -List     print outstanding leases: LEASES|n then LEASE|id|created|host|worktree
      -Release <id>  drop a reservation you decided not to use

.EXAMPLE
    pwsh ~/.agents/skills/issue-tracking/scripts/issue-new-id.ps1
.EXAMPLE
    pwsh ~/.agents/skills/issue-tracking/scripts/issue-new-id.ps1 -List
.EXAMPLE
    pwsh ~/.agents/skills/issue-tracking/scripts/issue-new-id.ps1 -Release 0062
#>
param(
    [switch]$List,
    [string]$Release,
    [int]$TtlHours = 24
)

$ErrorActionPreference = 'Stop'
. (Join-Path -Path $PSScriptRoot -ChildPath 'issue-id-lib.ps1')

$manifestPath = Join-Path -Path '.github' -ChildPath 'issue-tracker.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    "issue-id: no .github/issue-tracker.json - bootstrap the manifest first (issue-tracking skill, step 0)"
    exit 1
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$names = @($manifest.PSObject.Properties.Name)
$tracker = ''
if ($names -contains 'tracker') { $tracker = [string]$manifest.tracker }
if ($tracker -ne 'local-markdown') {
    "issue-id: tracker '$tracker' is not local-markdown - id allocation only covers the local file store"
    exit 1
}
$issuesDir = '.issues'
if ($names -contains 'issuesDir' -and -not [string]::IsNullOrWhiteSpace([string]$manifest.issuesDir)) {
    $issuesDir = [string]$manifest.issuesDir
}
$archiveDir = "$issuesDir/archived"
if ($names -contains 'archiveDir' -and -not [string]::IsNullOrWhiteSpace([string]$manifest.archiveDir)) {
    $archiveDir = [string]$manifest.archiveDir
}
if (-not (Test-Path -LiteralPath $issuesDir)) {
    "issue-id: issue store '$issuesDir' not found - create it (or set issuesDir in the manifest)"
    exit 1
}

$usage = Get-IssueIdUsage -IssuesDir $issuesDir -ArchiveDir $archiveDir
if ($usage.Duplicates.Count -gt 0) {
    foreach ($d in $usage.Duplicates) { "issue-id: DUPLICATE $d" }
    "issue-id: refusing to allocate from a store with duplicate ids - fix the store first (run the repo's issue lint)"
    exit 1
}

$leaseDir = Get-IssueIdLeaseDir
$leases = Get-IssueIdLeases -LeaseDir $leaseDir -TtlHours $TtlHours
foreach ($stale in $leases.Expired.Values) {
    Remove-Item -LiteralPath $stale.Path -Force -ErrorAction SilentlyContinue
    "issue-id: pruned expired lease $($stale.Id) (held since $($stale.CreatedUtc.ToString('u')))"
}

# --- -List --------------------------------------------------------------------
if ($List) {
    $active = @($leases.Active.Values | Sort-Object Id)
    "LEASES|$($active.Count)"
    foreach ($l in $active) {
        "LEASE|$($l.Id)|$($l.CreatedUtc.ToString('u'))|$($l.Host)|$($l.Worktree)"
    }
    exit 0
}

# --- -Release -----------------------------------------------------------------
if (-not [string]::IsNullOrWhiteSpace($Release)) {
    if ($Release -notmatch '^\d{4}$') {
        "issue-id: -Release expects a 4-digit id (got '$Release')"
        exit 1
    }
    $path = Join-Path -Path $leaseDir -ChildPath "$Release.lease"
    if (-not (Test-Path -LiteralPath $path)) {
        "issue-id: no lease held for $Release"
        exit 1
    }
    Remove-Item -LiteralPath $path -Force
    "RELEASED|$Release"
    exit 0
}

# --- allocate -----------------------------------------------------------------
$candidate = $usage.MaxId + 1
while ($candidate -le 9999) {
    $id = '{0:D4}' -f $candidate
    if (-not $usage.Used.ContainsKey($id) -and -not $leases.Active.ContainsKey($id)) {
        if (New-IssueIdLease -LeaseDir $leaseDir -Id $id) {
            "ID|$id"
            "LEASE|$(Join-Path -Path $leaseDir -ChildPath "$id.lease")"
            "STORE|$issuesDir"
            exit 0
        }
        # lost the atomic race - another session took it between our scan and
        # the create; take the next one.
    }
    $candidate++
}
"issue-id: id space exhausted (nothing free below 9999) - archive or renumber before filing more issues"
exit 1
