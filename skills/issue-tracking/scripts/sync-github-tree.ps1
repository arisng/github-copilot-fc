<#
.SYNOPSIS
    Syncs the committed github issue tree (manifest treeFile) from GitHub Issues.

.DESCRIPTION
    Reads .github/issue-tracker.json (refuses unless tracker: github AND
    treeSource: github), composes the membership query with
    query-composition-lib.ps1 anchored to ONE asOf epoch captured at start,
    fetches issues with gh, maps them to the issue-tree.ps1 grammar and writes
    treeFile. The caller then runs render-issue-tree.ps1.

    Spec: sketch v6 sections 1.1 / 1.4 / 1.5 / 1.6; evidence: critique
    sections F (F.0.2, F.1, F.3, F.4) and G.

    Decisions (spec silent or explicitly delegated to this script):
      - Count policy: the GraphQL ISSUE_ADVANCED issueCount call runs ONLY
        when issueQuery is set (membership was explicitly configured).
        Knob-only syncs skip the network count and keep the honest fetched
        floor (total = fetched rows, banner words it as >=N). A failed count
        call falls back to the floor with a warning (flagged).
      - -FromJson <file>: offline fixture mode used by the tests - no gh, no
        network. fetch = first treeMaxIssues+1 entries of fixture.issues
        (gh --limit semantics); fixture.exactCount and fixture.viewerLogin
        stand in for the count and viewer calls. Fixture format is documented
        in tests/test_sync_github_tree.py.
      - -Check is NOT an offline validator here (nothing here is
        reproducible offline): lint runs issue-tree.ps1 -Check (structural)
        plus render-issue-tree.ps1 -Check (byte-compare), per sketch 1.3.
        The switch only points at those two commands and fails - never a
        false green.
      - Priority field: issues without a priority:P0..P3 label carry the
        literal value "none" - they sort after every labeled row, then by
        number, and are never counted into the P0..P3 SUMMARY buckets.
      - Section (THEME) header fields are derived from shown rows: priority =
        best labeled priority (none when no member is labeled), status =
        open when any member is actionable, else done/dropped; title = the
        ordinal-first member theme label / milestone title / repo bucket.
      - Sanitization: CR/LF/control chars are stripped from titles, label
        names, milestone text and the FILTER payload before anything is
        written (audit C3 - a newline silently truncates a row).
      - Issue type: GitHub's native `type` field (fetched as `issueType`) is
        classification, not grouping, and the tree row grammar has no slot for
        it. The sync therefore ENFORCES it instead of rendering it: a fetched
        issue whose type falls outside the manifest's `issueTypes` vocabulary
        produces a warning the caller must read. Unset types are silent.

.EXAMPLE
    pwsh <skill-folder>/scripts/sync-github-tree.ps1
.EXAMPLE
    pwsh <skill-folder>/scripts/sync-github-tree.ps1 -Repo owner/name
#>
param(
    [switch]$Check,
    [string]$Repo,
    [string]$FromJson
)

$ErrorActionPreference = 'Stop'

if ($Check) {
    # Sketch 1.3: the github tree has no offline regeneration, so there is
    # nothing for this script to re-validate. Fail loud with the real gates
    # rather than pretending to a check of its own.
    "sync-github-tree: -Check is offline-deferred - the github tree is validated by:"
    "sync-github-tree:   pwsh <skill-folder>/scripts/issue-tree.ps1 -Check"
    "sync-github-tree:   pwsh <skill-folder>/scripts/render-issue-tree.ps1 -Check"
    exit 1
}

. (Join-Path -Path $PSScriptRoot -ChildPath 'query-composition-lib.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'issue-template-lib.ps1')

# --- Helpers ----------------------------------------------------------------

function Get-SanitizedText {
    # Strips CR/LF/C0 controls + DEL. Titles, label names, milestone text and
    # the FILTER payload all pass through here before they reach a line.
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return '' }
    return [regex]::Replace($Value, '[\x00-\x1F\x7F]', '')
}

function Get-PriorityRank {
    param([string]$Priority)
    switch ($Priority) {
        'P0' { return 0 }
        'P1' { return 1 }
        'P2' { return 2 }
        'P3' { return 3 }
        default { return 4 }
    }
}

function Get-OrdinalFirst {
    # Ordinal-first string of the set (never first-seen order - sketch 1.5).
    param([string[]]$Values)
    $clean = @($Values | Where-Object { -not [string]::IsNullOrEmpty($_) })
    if ($clean.Count -eq 0) { return $null }
    $arr = [string[]]$clean
    [Array]::Sort($arr, [System.StringComparer]::Ordinal)
    return $arr[0]
}

function Sort-GithubRows {
    # Row order (sketch 1.5 step 5c): priority -> order -> number, where
    # order = fetch index (query sort: selection order) and unlabeled rows
    # sort after every labeled row, then by number. Number is unique, so the
    # total order is deterministic without relying on sort stability.
    param([object[]]$Rows)
    $clean = @($Rows | Where-Object { $null -ne $_ })
    if ($clean.Count -le 1) { return @($clean) }
    $keys = @(
        @{ Expression = { if ($null -eq $_.PriorityRank) { 1 } else { 0 } } }
        @{ Expression = { if ($null -eq $_.PriorityRank) { 0 } else { $_.PriorityRank } } }
        @{ Expression = { if ($null -eq $_.PriorityRank) { 0 } else { $_.FetchIndex } } }
        @{ Expression = { $_.Number } }
    )
    return @($clean | Sort-Object -Property $keys)
}

function Add-GithubSubtreeRows {
    # Parent-first, contiguous subtree emission. Children appear only under a
    # root that was reached here, so a cap taken as a prefix of this sequence
    # can never orphan a nested row. $Seen guards shared/cyclic input.
    param($Row, [int]$Depth, $ChildrenMap, $Flat, $Seen)
    if ($Seen.ContainsKey($Row.Id)) { return }
    $Seen[$Row.Id] = $true
    [void]$Flat.Add(@{ Row = $Row; Depth = $Depth })
    if ($ChildrenMap.ContainsKey($Row.Id)) {
        foreach ($kid in $ChildrenMap[$Row.Id]) {
            Add-GithubSubtreeRows -Row $kid -Depth ($Depth + 1) -ChildrenMap $ChildrenMap -Flat $Flat -Seen $Seen
        }
    }
}

# --- 1. Manifest + compound guard (sketch 1.2) ------------------------------

$manifestPath = Join-Path -Path '.github' -ChildPath 'issue-tracker.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    "sync-github-tree: .github/issue-tracker.json not found - create it with issue-tracker-init.ps1 (tracker: github)"
    exit 1
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$names = @($manifest.PSObject.Properties.Name)
$tracker = 'local-markdown'
if ($names -contains 'tracker' -and -not [string]::IsNullOrWhiteSpace([string]$manifest.tracker)) {
    $tracker = [string]$manifest.tracker
}
$treeSource = 'local-markdown'
if ($names -contains 'treeSource' -and -not [string]::IsNullOrWhiteSpace([string]$manifest.treeSource)) {
    $treeSource = [string]$manifest.treeSource
}
if ($tracker -ne 'github') {
    "sync-github-tree: tracker '$tracker' is not github - this script syncs the github issue tree (issue-tracking skill, step 0)"
    exit 1
}
if ($treeSource -ne 'github') {
    "sync-github-tree: treeSource is '$treeSource' - set treeSource: 'github' in .github/issue-tracker.json to sync the github tree"
    exit 1
}

# --- 2. Limits, query, repo --------------------------------------------------

$treeMaxIssues = 300
if ($names -contains 'treeMaxIssues' -and $null -ne $manifest.treeMaxIssues) {
    $parsedLimit = 0
    if (-not [int]::TryParse([string]$manifest.treeMaxIssues, [ref]$parsedLimit) -or $parsedLimit -lt 1) {
        "sync-github-tree: treeMaxIssues must be a positive integer (got '$($manifest.treeMaxIssues)')"
        exit 1
    }
    $treeMaxIssues = $parsedLimit
}
$treeLookbackDays = 365
if ($names -contains 'treeLookbackDays' -and $null -ne $manifest.treeLookbackDays) {
    $parsedDays = 0
    if (-not [int]::TryParse([string]$manifest.treeLookbackDays, [ref]$parsedDays) -or $parsedDays -lt 1) {
        "sync-github-tree: treeLookbackDays must be a positive integer (got '$($manifest.treeLookbackDays)')"
        exit 1
    }
    $treeLookbackDays = $parsedDays
}
$treeIncludeClosed = $true
if ($names -contains 'treeIncludeClosed' -and $null -ne $manifest.treeIncludeClosed) {
    $treeIncludeClosed = [bool]$manifest.treeIncludeClosed
}
$treeMinPriority = ''
if ($names -contains 'treeMinPriority' -and -not [string]::IsNullOrWhiteSpace([string]$manifest.treeMinPriority)) {
    $treeMinPriority = ([string]$manifest.treeMinPriority).Trim()
    if ($treeMinPriority -cnotin @('P0', 'P1', 'P2', 'P3')) {
        "sync-github-tree: treeMinPriority must be one of P0, P1, P2, P3 (got '$treeMinPriority')"
        exit 1
    }
}
$issueQuery = ''
$hasIssueQuery = $false
if ($names -contains 'issueQuery' -and -not [string]::IsNullOrWhiteSpace([string]$manifest.issueQuery)) {
    $issueQuery = [string]$manifest.issueQuery
    $hasIssueQuery = $true
}
$repoName = ''
if (-not [string]::IsNullOrWhiteSpace($Repo)) {
    $repoName = $Repo.Trim()
}
elseif ($names -contains 'repo' -and -not [string]::IsNullOrWhiteSpace([string]$manifest.repo)) {
    $repoName = ([string]$manifest.repo).Trim()
}
if ($repoName -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
    "sync-github-tree: repo '$repoName' is not an owner/name GitHub repository (set the manifest 'repo' field or pass -Repo)"
    exit 1
}

# Taxonomy (references/manifest-schema.md): the configured `issueTypes`, used to
# flag fetched issues whose native GitHub type falls outside the vocabulary.
# An absent key means the shipped defaults; a broken list fails the sync loudly
# rather than silently accepting any type.
$taxonomyTypes = @()
$taxonomyOverride = $null
if ($names -contains 'issueTypes') { $taxonomyOverride = $manifest.issueTypes }
$taxonomy = Get-IssueTypeTaxonomy -Overrides $taxonomyOverride
if ($taxonomy.Errors.Count -gt 0) {
    foreach ($err in $taxonomy.Errors) { "sync-github-tree: $err" }
    exit 1
}
$taxonomyTypes = @($taxonomy.Types)

# Realm vocabulary (references/manifest-schema.md): optional `themeRealms`
# lists the issue labels that name a realm (e.g. skillcon, sdlc). When the
# issue carries one, the theme: section id becomes T-<realm>-<slug> (duplicated
# realm stripped from the slug). Absent key, or an issue without a realm
# label, keeps the plain T-<slug> - not every issue is scoped to a realm.
$themeRealms = @()
if ($names -contains 'themeRealms') {
    $realmValues = @()
    $rawRealmSpec = $manifest.themeRealms
    if ($rawRealmSpec -is [string]) {
        foreach ($part in (ConvertTo-StringList -Value $rawRealmSpec)) { $realmValues += $part }
    }
    else {
        foreach ($entry in @($rawRealmSpec)) {
            if ($null -eq $entry) { continue }
            # A shell may hand the whole list over as one comma-separated
            # string even for an array parameter (pwsh -File does).
            foreach ($part in (ConvertTo-StringList -Value ([string]$entry))) { $realmValues += $part }
        }
    }
    $realmSeen = @{}
    foreach ($rawRealm in $realmValues) {
        $realmName = ([string]$rawRealm).Trim()
        if ($realmName -eq '') {
            "sync-github-tree: themeRealms contains an empty label name"
            exit 1
        }
        $realmKey = $realmName.ToLowerInvariant()
        if ($realmSeen.ContainsKey($realmKey)) {
            "sync-github-tree: themeRealms lists '$realmName' twice"
            exit 1
        }
        $realmSeen[$realmKey] = $true
        $themeRealms += $realmName
    }
    if ($themeRealms.Count -eq 0) {
        "sync-github-tree: themeRealms must list at least one realm label (omit the key to keep plain theme ids)"
        exit 1
    }
}

$treePath = '.issues/tree.md'
if ($names -contains 'treeFile' -and -not [string]::IsNullOrWhiteSpace([string]$manifest.treeFile)) {
    $treePath = [string]$manifest.treeFile
}
$treeLabel = $treePath -replace '\\', '/'

# --- 3. asOf anchor (the ONE wall-clock read, sketch 1.4) ---------------------

$asOf = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

# --- 4. Query composition (sketch 1.5 step 2, frozen lib contract) ------------

if ($hasIssueQuery) {
    # Defense in depth: gh exits 0 on garbage, this validator is the real
    # gate (critique a.6). The writer validates at -Apply; re-check here.
    $validation = Test-GithubIssueQuery -Query $issueQuery
    if (-not $validation.IsValid) {
        foreach ($err in @($validation.Errors)) { "sync-github-tree: issueQuery: $err" }
        exit 1
    }
}
$composed = ComposedGithubIssueQuery -Query $issueQuery -IncludeClosed $treeIncludeClosed -LookbackAnchorEpoch $asOf -LookbackDays $treeLookbackDays
$classes = Get-GithubIssueQueryClasses -Query $composed.Query

# --- 5. Offline fixture (tests) + viewer resolution (@me -> login) -----------

$fromJsonMode = -not [string]::IsNullOrWhiteSpace($FromJson)
$fixture = $null
if ($fromJsonMode) {
    if (-not (Test-Path -LiteralPath $FromJson)) {
        "sync-github-tree: fixture '$FromJson' not found"
        exit 1
    }
    try {
        $fixture = Get-Content -LiteralPath $FromJson -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        "sync-github-tree: fixture '$FromJson' is not valid JSON: $($_.Exception.Message)"
        exit 1
    }
}

$warnings = [System.Collections.Generic.List[string]]::new()
$resolvedLogin = ''
if ($classes.HasViewer) {
    # The marker discloses whose view the snapshot was built for (sketch
    # 1.1/1.6); gh resolves @me itself inside the search query, so the login
    # rides ONLY the FILTER payload, never the gh query.
    if ($fromJsonMode) {
        if ($null -eq $fixture -or [string]::IsNullOrWhiteSpace([string]$fixture.viewerLogin)) {
            "sync-github-tree: viewer login could not be resolved (fixture.viewerLogin is absent)"
            exit 1
        }
        $resolvedLogin = Get-SanitizedText ([string]$fixture.viewerLogin)
    }
    else {
        $viewerOut = $null
        try {
            $viewerOut = & gh api graphql -f 'query={viewer{login}}' --jq '.data.viewer.login' 2>&1
        }
        catch {
            "sync-github-tree: viewer login could not be resolved: $($_.Exception.Message)"
            exit 1
        }
        if ($LASTEXITCODE -ne 0) {
            "sync-github-tree: viewer login could not be resolved (gh api graphql exit $LASTEXITCODE)"
            exit 1
        }
        $resolvedLogin = Get-SanitizedText ((($viewerOut | Out-String).Trim()))
        if ([string]::IsNullOrWhiteSpace($resolvedLogin)) {
            "sync-github-tree: viewer login could not be resolved (empty login)"
            exit 1
        }
    }
}
$filterPayload = $composed.Query
if (-not [string]::IsNullOrWhiteSpace($resolvedLogin)) {
    $filterPayload = "$filterPayload @me→$resolvedLogin"
}
$filterPayload = Get-SanitizedText $filterPayload

# --- 6. Fetch (sketch 1.5 step 2) --------------------------------------------

$limit = $treeMaxIssues + 1
$jsonFieldList = 'number,title,state,stateReason,labels,milestone,parent,subIssues,subIssuesSummary,issueType,createdAt,updatedAt,closedAt'
$issues = @()
if ($fromJsonMode) {
    $rawIssues = $null
    if ($null -ne $fixture) { $rawIssues = $fixture.issues }
    $allIssues = @()
    if ($null -ne $rawIssues) { $allIssues = @(@($rawIssues) | Where-Object { $null -ne $_ }) }
    # gh --limit semantics: the fixture is sliced exactly like the network
    # fetch, so cap+1 truncation probes behave identically offline.
    $issues = @($allIssues | Select-Object -First $limit)
}
else {
    $ghOut = @()
    try {
        $ghOut = & gh issue list --repo $repoName --state all --limit $limit --search $composed.Query --json $jsonFieldList 2>&1
    }
    catch {
        "sync-github-tree: gh could not be run: $($_.Exception.Message)"
        exit 1
    }
    if ($LASTEXITCODE -ne 0) {
        $ghText = Get-SanitizedText ((($ghOut | Out-String).Trim()))
        "sync-github-tree: gh issue list failed (exit $LASTEXITCODE) for query:"
        "sync-github-tree:   $($composed.Query)"
        if (-not [string]::IsNullOrWhiteSpace($ghText)) { "sync-github-tree: gh said: $ghText" }
        exit 1
    }
    try {
        $issues = @((($ghOut | Out-String)) | ConvertFrom-Json)
    }
    catch {
        "sync-github-tree: gh issue list returned unparseable JSON: $($_.Exception.Message)"
        exit 1
    }
}
$fetched = $issues.Count

# --- 7. Exact count (GraphQL ISSUE_ADVANCED, critique c.3) --------------------
# Only when issueQuery is set - knob-only membership keeps the fetched floor
# (documented decision in the header) so a plain sync stays one API call.

$exactCount = $null
if ($hasIssueQuery) {
    if ($fromJsonMode) {
        if ($null -ne $fixture -and $null -ne $fixture.PSObject.Properties['exactCount'] -and $null -ne $fixture.exactCount) {
            $parsedCount = 0L
            if ([long]::TryParse([string]$fixture.exactCount, [ref]$parsedCount)) {
                $exactCount = $parsedCount
            }
            else {
                $warnings.Add("fixture exactCount '$($fixture.exactCount)' is not a number - using fetched floor")
            }
        }
        else {
            $warnings.Add('exact count unavailable (fixture.exactCount absent) - using fetched floor')
        }
    }
    else {
        $countQuery = "( $($composed.Query) ) repo:$repoName type:issue"
        $gqDoc = 'query($q:String!){search(query:$q,type:ISSUE_ADVANCED){issueCount}}'
        $countOut = @()
        $countRan = $true
        try {
            $countOut = & gh api graphql -f "query=$gqDoc" -f "q=$countQuery" --jq '.data.search.issueCount' 2>&1
        }
        catch {
            $countRan = $false
            $countOut = @($_.Exception.Message)
        }
        $parsedCount = 0L
        if ($countRan -and $LASTEXITCODE -eq 0 -and [long]::TryParse((($countOut | Out-String).Trim()), [ref]$parsedCount)) {
            $exactCount = $parsedCount
        }
        else {
            $detail = Get-SanitizedText ((($countOut | Out-String).Trim()))
            $warnings.Add("exact count call failed - using fetched floor ($detail)")
        }
    }
}

# --- 8. Map rows (sketch 1.5 steps 3-4) --------------------------------------

$mappedRows = [System.Collections.Generic.List[object]]::new()
$childCounts = @{}
$fetchIndex = -1
foreach ($issue in $issues) {
    $fetchIndex++
    if ($null -eq $issue) { continue }
    $number = 0
    if (-not [int]::TryParse([string]$issue.number, [ref]$number) -or $number -lt 1) {
        $warnings.Add('a fetched issue without a usable number was skipped')
        continue
    }
    $id = '{0:D4}' -f $number
    $title = Get-SanitizedText ([string]$issue.title)

    # Labels: sanitized names; prefixes matched case-insensitively (labels
    # are data, not gh search qualifiers).
    $labelNames = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $issue.labels) {
        foreach ($label in @($issue.labels)) {
            $labelText = $null
            if ($label -is [string]) { $labelText = $label }
            elseif ($null -ne $label -and $null -ne $label.PSObject.Properties['name']) { $labelText = [string]$label.name }
            if (-not [string]::IsNullOrEmpty($labelText)) { [void]$labelNames.Add((Get-SanitizedText $labelText)) }
        }
    }
    foreach ($lname in $labelNames) {
        if ($lname -like 'parent:*') {
            $warnings.Add("issue #${id}: label '$lname' is unsupported (native gh sub-issues only) - ignored")
        }
    }

    # Status (sketch 1.5 step 3): open -> status: label override; closed ->
    # stateReason split (completed/unknown -> done, not_planned -> dropped).
    # The override applies to open issues only (literal spec wording).
    $state = ([string]$issue.state)
    $status = $null
    if ($state -ieq 'OPEN') {
        $status = 'open'
        $statusLabels = @($labelNames | Where-Object { $_ -like 'status:*' })
        if ($statusLabels.Count -gt 0) {
            $sortedStatus = [string[]]$statusLabels
            [Array]::Sort($sortedStatus, [System.StringComparer]::Ordinal)
            $firstStatus = $sortedStatus[0]
            $statusValue = ($firstStatus.Substring($firstStatus.IndexOf(':') + 1)).ToLowerInvariant()
            if ($statusValue -in @('open', 'in-progress', 'blocked', 'done', 'dropped')) {
                $status = $statusValue
            }
            else {
                $warnings.Add("issue #${id}: status label '$firstStatus' is not one of open/in-progress/blocked/done/dropped - ignored")
            }
        }
    }
    elseif ($state -ieq 'CLOSED') {
        $stateReason = ''
        if ($null -ne $issue.PSObject.Properties['stateReason'] -and $null -ne $issue.stateReason) {
            $stateReason = ([string]$issue.stateReason).ToLowerInvariant()
        }
        if ($stateReason -eq 'not_planned') { $status = 'dropped' }
        else { $status = 'done' }
    }
    else {
        $warnings.Add("issue #${id}: unknown state '$state' - treated as open")
        $status = 'open'
    }

    # Priority labels priority:P0..P3 (ordinal-first among matches), else none.
    $priority = 'none'
    $priorityRank = $null
    $priorityLabels = @($labelNames | Where-Object { $_ -like 'priority:*' })
    if ($priorityLabels.Count -gt 0) {
        $sortedPriority = [string[]]$priorityLabels
        [Array]::Sort($sortedPriority, [System.StringComparer]::Ordinal)
        $firstPriority = $sortedPriority[0]
        $priorityValue = ($firstPriority.Substring($firstPriority.IndexOf(':') + 1)).ToUpperInvariant()
        if ($priorityValue -in @('P0', 'P1', 'P2', 'P3')) {
            $priority = $priorityValue
            $priorityRank = Get-PriorityRank -Priority $priority
        }
        else {
            $warnings.Add("issue #${id}: priority label '$firstPriority' is not P0..P3 - treated as unlabeled")
        }
    }

    # Theme (sketch 1.5 step 3): theme: label wins -> T-<slug> with
    # lowercase/trim/non-alnum-collapse normalization; multiple theme: labels
    # -> ordinal-first + warning; milestone -> M<num>; else one repo bucket.
    # When the manifest declares `themeRealms` and the issue carries one, the
    # id becomes T-<realm>-<slug> (lowercase realm, duplicated realm stripped
    # from the slug); an issue without a realm label keeps T-<slug>.
    # Issue type (GitHub's native single-select field, NOT a label). The tree
    # grammar has no type slot - a row carries priority/status/theme - so the
    # type is used for TAXONOMY ENFORCEMENT: a value outside the configured
    # issueTypes vocabulary is a warning the caller must read. Unset types are
    # silent (a repo that never adopted the feature has no types to check).
    $nativeType = ''
    if ($null -ne $issue.PSObject.Properties['issueType'] -and $null -ne $issue.issueType) {
        $typeName = ''
        if ($null -ne $issue.issueType.PSObject.Properties['name']) { $typeName = [string]$issue.issueType.name }
        elseif ($issue.issueType -is [string]) { $typeName = [string]$issue.issueType }
        if (-not [string]::IsNullOrWhiteSpace($typeName)) {
            $nativeType = (Get-SanitizedText $typeName).ToLowerInvariant()
            if ($nativeType -notmatch '^[a-z0-9][a-z0-9-]{0,31}$') {
                $warnings.Add("issue #${id}: issue type '$typeName' is not a kebab-case name - ignored")
                $nativeType = ''
            }
        }
    }
    if ($nativeType -ne '' -and $taxonomyTypes.Count -gt 0 -and $taxonomyTypes -notcontains $nativeType) {
        $warnings.Add("issue #${id}: issue type '$nativeType' is outside the configured issueTypes ($($taxonomyTypes -join ', ')) - add it to .github/issue-tracker.json or retype the issue")
    }

    $themeId = ''
    $themeTitle = ''
    $themeLabels = @($labelNames | Where-Object { $_ -like 'theme:*' })
    if ($themeLabels.Count -gt 0) {
        $sortedThemes = [string[]]$themeLabels
        [Array]::Sort($sortedThemes, [System.StringComparer]::Ordinal)
        $firstTheme = $sortedThemes[0]
        if ($themeLabels.Count -gt 1) {
            $warnings.Add("issue #${id}: has $($themeLabels.Count) theme: labels - using '$firstTheme' (ordinal-first)")
        }
        $rawTheme = ($firstTheme.Substring($firstTheme.IndexOf(':') + 1)).Trim()
        $slug = [regex]::Replace($rawTheme.ToLowerInvariant().Trim(), '[^a-z0-9]+', '-')
        if ($slug -ne '') {
            $themeId = "T-$slug"
            # Realm prefix: an issue may carry one of the manifest's realm
            # labels (ordinal-first). T-<realm>-<slug>, lowercase, with a
            # duplicated realm stripped from the slug; no realm label -> T-<slug>.
            if ($themeRealms.Count -gt 0) {
                $realmMatches = [System.Collections.Generic.List[string]]::new()
                foreach ($lname in $labelNames) {
                    if ($themeRealms -contains $lname) { [void]$realmMatches.Add($lname) }
                }
                if ($realmMatches.Count -gt 0) {
                    $sortedRealmMatches = [string[]]$realmMatches
                    [Array]::Sort($sortedRealmMatches, [System.StringComparer]::Ordinal)
                    $realmName = $sortedRealmMatches[0]
                    if ($realmMatches.Count -gt 1) {
                        $warnings.Add("issue #${id}: has $($realmMatches.Count) realm labels - using '$realmName' (ordinal-first)")
                    }
                    $realm = [regex]::Replace($realmName.ToLowerInvariant().Trim(), '[^a-z0-9]+', '-')
                    if ($realm -ne '') {
                        if ($slug -eq $realm) { $bareSlug = '' }
                        elseif ($slug.StartsWith("$realm-", [System.StringComparison]::Ordinal)) {
                            $bareSlug = $slug.Substring($realm.Length + 1)
                        }
                        else { $bareSlug = $slug }
                        $themeId = if ($bareSlug -ne '') { "T-$realm-$bareSlug" } else { "T-$realm" }
                    }
                }
            }
            $themeTitle = $rawTheme
        }
        else {
            $warnings.Add("issue #${id}: theme label '$firstTheme' normalizes to an empty slug - ignored")
        }
    }
    if ($themeId -eq '' -and $null -ne $issue.milestone) {
        $msNumber = 0
        if ($null -ne $issue.milestone.PSObject.Properties['number'] -and [int]::TryParse([string]$issue.milestone.number, [ref]$msNumber)) {
            $themeId = "M$msNumber"
            $themeTitle = ''
            if ($null -ne $issue.milestone.PSObject.Properties['title']) {
                $themeTitle = Get-SanitizedText ([string]$issue.milestone.title)
            }
            if ([string]::IsNullOrWhiteSpace($themeTitle)) { $themeTitle = $themeId }
        }
        else {
            $warnings.Add("issue #${id}: milestone without a usable number - falling back to the default bucket")
        }
    }
    if ($themeId -eq '') {
        $themeId = "$repoName issues"
        $themeTitle = "$repoName issues"
    }

    # Hierarchy: native gh sub-issues ONLY (decision 3). parent:<NNNN> labels
    # warn above and are ignored here.
    $parentNumber = $null
    if ($null -ne $issue.parent -and $null -ne $issue.parent.PSObject.Properties['number']) {
        $pn = 0
        if ([int]::TryParse([string]$issue.parent.number, [ref]$pn) -and $pn -ge 1) {
            if ($pn -eq $number) {
                $warnings.Add("issue #${id}: native parent points at itself - ignored")
            }
            else {
                $parentNumber = $pn
            }
        }
    }
    $parentHint = '-'
    if ($null -ne $parentNumber) { $parentHint = '{0:D4}' -f $parentNumber }

    # subIssues shape guard (F.0.2: serialized shape was unverified) + the
    # summary total kept for the shortfall cross-check below.
    $subTotal = $null
    if ($null -ne $issue.subIssuesSummary -and $null -ne $issue.subIssuesSummary.PSObject.Properties['total']) {
        $st = 0
        if ([int]::TryParse([string]$issue.subIssuesSummary.total, [ref]$st)) { $subTotal = $st }
    }
    $subNodes = $null
    if ($null -ne $issue.subIssues) {
        if ($issue.subIssues -is [System.Array]) { $subNodes = @($issue.subIssues) }
        elseif ($null -ne $issue.subIssues.PSObject.Properties['nodes'] -and $null -ne $issue.subIssues.nodes) {
            $subNodes = @($issue.subIssues.nodes)
        }
    }
    if ($null -ne $subNodes -and $subNodes.Count -gt 0) {
        $badNodes = @($subNodes | Where-Object { $null -eq $_ -or $null -eq $_.PSObject.Properties['number'] })
        if ($badNodes.Count -gt 0) {
            $warnings.Add("issue #${id}: sub-issue node without a 'number' field (gh shape drift) - child link ignored")
        }
    }

    if ($null -ne $parentNumber) {
        if (-not $childCounts.ContainsKey($parentNumber)) { $childCounts[$parentNumber] = 0 }
        $childCounts[$parentNumber]++
    }

    $row = [PSCustomObject]@{
        Number         = $number
        Id             = $id
        FetchIndex     = $fetchIndex
        Title          = $title
        Status         = $status
        Priority       = $priority
        PriorityRank   = $priorityRank
        ThemeId        = $themeId
        ThemeTitle     = $themeTitle
        ParentNumber   = $parentNumber
        ParentHint     = $parentHint
        SubIssueTotal  = $subTotal
        IsClosedStatus = ($status -eq 'done' -or $status -eq 'dropped')
        IsRoot         = $true
        NestParentId   = $null
    }
    [void]$mappedRows.Add($row)
}

# Sub-issue shortfall cross-check (F.0.2): declared total vs the children we
# actually fetched - pagination or the fetch cap can drop some.
foreach ($row in $mappedRows) {
    if ($null -ne $row.SubIssueTotal -and $row.SubIssueTotal -gt 0) {
        $have = 0
        if ($childCounts.ContainsKey($row.Number)) { $have = $childCounts[$row.Number] }
        if ($row.SubIssueTotal -gt $have) {
            $warnings.Add("issue #$($row.Id): subIssuesSummary.total=$($row.SubIssueTotal) but only $have child issue(s) in the fetched set (sub-issue pagination or fetch cap)")
        }
    }
}

# --- 9. treeMinPriority floor (post-fetch client filter) ---------------------

$rows = @($mappedRows)
if (-not [string]::IsNullOrWhiteSpace($treeMinPriority)) {
    $floorRank = Get-PriorityRank -Priority $treeMinPriority
    $rows = @($mappedRows | Where-Object { $null -ne $_.PriorityRank -and $_.PriorityRank -le $floorRank })
    $droppedByFloor = $mappedRows.Count - $rows.Count
    if ($droppedByFloor -gt 0) {
        $warnings.Add("treeMinPriority $treeMinPriority dropped $droppedByFloor fetched issue(s)")
    }
}

# --- 10. Sections + promotion (sketch 1.5 step 5a/5b) ------------------------

$byNumber = @{}
foreach ($r in $rows) { $byNumber[$r.Number] = $r }
$childGroups = @{}
foreach ($r in $rows) {
    $r.IsRoot = $true
    $r.NestParentId = $null
    $parentRow = $null
    if ($null -ne $r.ParentNumber -and $byNumber.ContainsKey($r.ParentNumber)) {
        $parentRow = $byNumber[$r.ParentNumber]
    }
    if ($null -ne $parentRow) {
        # Promote, don't nest: cross-theme children become roots of their own
        # section (grammar: row theme must equal section id, F.3); open
        # children of closed ancestors become roots so they land in the
        # section's open region and survive the cap (F.4.1). Both promote.
        $crossTheme = ($parentRow.ThemeId -ne $r.ThemeId)
        $stateConflict = ((-not $r.IsClosedStatus) -and $parentRow.IsClosedStatus)
        if ($crossTheme) {
            $warnings.Add("issue #$($r.Id) (theme '$($r.ThemeId)') is a sub-issue of #$($parentRow.Id) (theme '$($parentRow.ThemeId)') - promoted to a root row of its own section")
        }
        if ($stateConflict) {
            $warnings.Add("issue #$($r.Id) is open under closed parent #$($parentRow.Id) - promoted to its section's open region")
        }
        if (-not $crossTheme -and -not $stateConflict) {
            $r.IsRoot = $false
            $r.NestParentId = $parentRow.Id
        }
    }
}
foreach ($r in $rows) {
    if (-not $r.IsRoot) {
        if (-not $childGroups.ContainsKey($r.NestParentId)) {
            $childGroups[$r.NestParentId] = [System.Collections.Generic.List[object]]::new()
        }
        [void]$childGroups[$r.NestParentId].Add($r)
    }
}
$sectionMap = @{}
foreach ($r in $rows) {
    if (-not $sectionMap.ContainsKey($r.ThemeId)) {
        $sectionMap[$r.ThemeId] = [System.Collections.Generic.List[object]]::new()
    }
    [void]$sectionMap[$r.ThemeId].Add($r)
}

# --- 11. Ordering + cap (sketch 1.5 step 5c) ---------------------------------

$sectionIds = [string[]]@($sectionMap.Keys)
if ($sectionIds.Count -gt 0) { [Array]::Sort($sectionIds, [System.StringComparer]::Ordinal) }
$remaining = $treeMaxIssues
$emittedSections = [System.Collections.Generic.List[object]]::new()
$shownRows = [System.Collections.Generic.List[object]]::new()
foreach ($sid in $sectionIds) {
    if ($remaining -le 0) { break }
    $members = $sectionMap[$sid]
    $openRoots = @(Sort-GithubRows -Rows @($members | Where-Object { $_.IsRoot -and -not $_.IsClosedStatus }))
    $closedRoots = @(Sort-GithubRows -Rows @($members | Where-Object { $_.IsRoot -and $_.IsClosedStatus }))
    $flat = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    foreach ($root in $openRoots) { Add-GithubSubtreeRows -Row $root -Depth 0 -ChildrenMap $childGroups -Flat $flat -Seen $seen }
    foreach ($root in $closedRoots) { Add-GithubSubtreeRows -Row $root -Depth 0 -ChildrenMap $childGroups -Flat $flat -Seen $seen }
    if ($flat.Count -lt $members.Count) {
        $warnings.Add("section '$sid': $($members.Count - $flat.Count) row(s) unreachable via the native parent chain (cycle) - dropped")
    }
    if ($flat.Count -eq 0) { continue }
    $take = $flat.Count
    if ($take -gt $remaining) { $take = $remaining }

    # Section header fields derive from the full member set (stable across
    # cap changes): best labeled priority, actionable-wins status, title =
    # ordinal-first member theme title.
    $bestRank = $null
    foreach ($m in $members) {
        if ($null -ne $m.PriorityRank -and ($null -eq $bestRank -or $m.PriorityRank -lt $bestRank)) { $bestRank = $m.PriorityRank }
    }
    $secPriority = 'none'
    if ($null -ne $bestRank) { $secPriority = "P$bestRank" }
    $secStatus = 'dropped'
    if (@($members | Where-Object { -not $_.IsClosedStatus }).Count -gt 0) { $secStatus = 'open' }
    elseif (@($members | Where-Object { $_.Status -eq 'done' }).Count -gt 0) { $secStatus = 'done' }
    $secTitle = Get-OrdinalFirst -Values @($members | ForEach-Object { $_.ThemeTitle })
    if ([string]::IsNullOrEmpty($secTitle)) { $secTitle = $sid }

    $secLines = [System.Collections.Generic.List[string]]::new()
    [void]$secLines.Add("## THEME|$sid|$secPriority|$secStatus|$secTitle")
    $secRows = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $take; $i++) {
        $entry = $flat[$i]
        $row = $entry.Row
        $parentField = $row.ParentHint
        if (-not $row.IsRoot) { $parentField = $row.NestParentId }
        $indent = ' ' * (3 * [int]$entry.Depth)
        [void]$secLines.Add("$indent- $($row.Id)|$($row.ThemeId)|$parentField|$($row.Priority)|$($row.Status)|$($row.Title)")
        [void]$secRows.Add($row)
        [void]$shownRows.Add($row)
        $remaining--
    }
    [void]$emittedSections.Add(@{ Id = $sid; Lines = $secLines; Rows = $secRows })
}
if ($sectionMap.Count -eq 0) {
    # Renderer hard-requires >= 1 THEME section: an empty fetch still emits
    # the single fallback bucket with zero rows so the artifact stays valid.
    $fbId = "$repoName issues"
    $secLines = [System.Collections.Generic.List[string]]::new()
    [void]$secLines.Add("## THEME|$fbId|none|open|$fbId")
    [void]$emittedSections.Add(@{ Id = $fbId; Lines = $secLines; Rows = ([System.Collections.Generic.List[object]]::new()) })
}
$shownCount = $shownRows.Count

# --- 12. NEXT (highest-priority actionable shown row) ------------------------

$candidates = [System.Collections.Generic.List[object]]::new()
for ($si = 0; $si -lt $emittedSections.Count; $si++) {
    foreach ($row in $emittedSections[$si].Rows) {
        if ($row.Status -ne 'open' -and $row.Status -ne 'in-progress') { continue }
        $flag = 0
        $rank = 4
        if ($null -ne $row.PriorityRank) { $rank = $row.PriorityRank } else { $flag = 1 }
        [void]$candidates.Add([PSCustomObject]@{ Row = $row; Flag = $flag; Rank = $rank; SecIdx = $si })
    }
}
$nextRow = $null
if ($candidates.Count -gt 0) {
    $nextKeys = @(
        @{ Expression = { $_.Flag } }
        @{ Expression = { $_.Rank } }
        @{ Expression = { $_.SecIdx } }
        @{ Expression = { $_.Row.Number } }
    )
    $best = @($candidates | Sort-Object -Property $nextKeys)[0]
    $nextRow = $best.Row
}

# --- 13. SUMMARY totals ------------------------------------------------------

$pCounts = @{ 'P0' = 0; 'P1' = 0; 'P2' = 0; 'P3' = 0 }
$blocked = 0
foreach ($row in $shownRows) {
    if ($pCounts.ContainsKey($row.Priority)) { $pCounts[$row.Priority]++ }
    if ($row.Status -eq 'blocked') { $blocked++ }
}
$total = $fetched
$countNote = 'floor'
if ($null -ne $exactCount) {
    if ($exactCount -ge $shownCount) {
        $total = $exactCount
        $countNote = 'exact'
    }
    else {
        $warnings.Add("exact count $exactCount is below the shown row count $shownCount - using the fetched floor")
    }
}
# Post-filter truncation rule (F.1.3): the cap bound AND the fetch probe hit
# its limit - a client-side filter dropping rows alone is not truncation.
$truncated = ($shownCount -eq $treeMaxIssues -and $fetched -eq ($treeMaxIssues + 1))

# --- 14. Emit tree.md (grammar per issue-tree.ps1 -Inventory) ----------------

$lines = [System.Collections.Generic.List[string]]::new()
# FILTER first (before summaries): single-line payload, grammar-optional -
# render-issue-tree.ps1 maps it to dataJson.filter; absent -> "".
[void]$lines.Add("FILTER|$filterPayload")
# cap is always known; lookback rides the SUMMARY only when the knob
# actually applied - a temporal qualifier in issueQuery (created:/updated:/
# closed:) suppresses the append, and the lib records it in SkippedKnobs.
# Both keys stay digits-only (grammar unchanged, additive).
$summaryLine = "SUMMARY|themes=$($emittedSections.Count)|issues=$shownCount|total=$total|asOfEpoch=$asOf|P0=$($pCounts['P0'])|P1=$($pCounts['P1'])|P2=$($pCounts['P2'])|P3=$($pCounts['P3'])|blocked=$blocked|cap=$treeMaxIssues"
$lookbackApplied = $true
foreach ($knob in @($composed.SkippedKnobs)) {
    if ($knob -like 'created:>=*') { $lookbackApplied = $false }
}
if ($lookbackApplied) { $summaryLine = "$summaryLine|lookback=$treeLookbackDays" }
[void]$lines.Add($summaryLine)
[void]$lines.Add('')
if ($null -ne $nextRow) {
    [void]$lines.Add("NEXT|$($nextRow.Id)|$($nextRow.ThemeId)|$($nextRow.Priority)|$($nextRow.Status)|$($nextRow.Title)")
    [void]$lines.Add('')
}
foreach ($sec in $emittedSections) {
    foreach ($secLine in $sec.Lines) { [void]$lines.Add($secLine) }
    [void]$lines.Add('')
}
$treeText = ($lines -join "`n") + "`n"

$absTree = Join-Path -Path (Get-Location).Path -ChildPath $treePath
$treeDir = Split-Path -Parent $absTree
if (-not [string]::IsNullOrEmpty($treeDir) -and -not (Test-Path -LiteralPath $treeDir)) {
    New-Item -ItemType Directory -Path $treeDir -Force | Out-Null
}
[System.IO.File]::WriteAllText($absTree, $treeText, [System.Text.UTF8Encoding]::new($false))

# --- 15. Sync summary --------------------------------------------------------

"sync-github-tree: query: $($composed.Query)"
if (@($composed.SkippedKnobs).Count -gt 0) {
    "sync-github-tree: skipped knobs: $(@($composed.SkippedKnobs) -join ', ')"
}
"sync-github-tree: fetched=$fetched shown=$shownCount truncated=$($truncated.ToString().ToLowerInvariant()) total=$total ($countNote) asOf=$asOf"
foreach ($w in $warnings) { "sync-github-tree: warning: $w" }
"sync-github-tree: OK ($($emittedSections.Count) themes, $shownCount issues, wrote $treeLabel)"
exit 0
