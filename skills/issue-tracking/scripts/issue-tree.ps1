<#
.SYNOPSIS
    Validates issue-to-theme relations, (re)generates the tree file, or dumps the
    store as machine rows (-Inventory).

.DESCRIPTION
    A theme (type: theme) is a prioritized workstream - the root grouping and the
    superset of the tree. Every active non-theme issue (epic, task, bug, chore)
    must relate to exactly one theme - directly via `theme: NNNN`, or indirectly
    via a `parent:` chain that ends at a theme (or at an issue carrying a theme).
    An epic is an intermediate grouping INSIDE a theme, so it must resolve like
    any other non-theme issue; only type: theme may be the target of `theme:`.

    Checks:
      1. Frontmatter: required fields, id matches filename, status/priority/type
         enums, numeric order, created as a YYYY-MM-DD date. Template
         conformance (scripts/issue-template-lib.ps1): the resolved template
         (skill defaults in assets/issue-templates, replaced per type by
         manifest-registered overrides) must accept every frontmatter field,
         get its required fields, and see its required body sections - errors
         print as TEMPLATE lines (references/issue-templates.md).
      2. Theme relations: resolvable, no cycles, theme refs point at type: theme,
         every theme has at least one active child, and a theme's status agrees
         with its completion (100% must be 'done'/'dropped'; 'done' must be 100%).
         Completion is the view's formula: done / (children - dropped).
         LOCAL-MARKDOWN ONLY: in github mode the sync derives each theme
         header's status from its members, so there is no authored value to
         contradict and -Check stays a structural check by design.
      3. -Check also fails when the tree file is missing or stale.

    Store resolution (repo-agnostic): .github/issue-tracker.json, read relative to
    the current directory, supplies tracker / treeSource / issuesDir / treeFile /
    archiveDir; falls back to .issues, .issues/tree.md and .issues/archived when
    the manifest is absent. The compound guard runs only for
    (tracker == 'local-markdown') OR (tracker == 'github' AND treeSource == 'github');
    azure-devops and every other tracker stay refused, and a missing treeSource
    behaves as local-markdown so old github manifests fail closed
    (issue-tracking skill, step 0).

    Github tree source (tracker: github + treeSource: github) - the committed
    treeFile is the source of truth; this script never regenerates it:
      default     no-op: prints "github tree source: run sync-github-tree.ps1
                  to regenerate" (exit 0, never writes)
      -Check      structural self-consistency of treeFile only (parser +
                  count cross-checks; no store dir, no byte-compare)
      -Inventory  parse treeFile and print its data rows (no NEXT_ID - GitHub
                  assigns issue numbers)

    Modes (local-markdown: all validate first; errors print as THEME lines and
    exit 1):
      default     regenerate the tree file (exits before writing when invalid)
      -Check      validate only + tree freshness (repo issue lint, pre-commit gate)
      -Inventory  print one pipe row per issue, then the next free id:
                    id|type|status|priority|theme|parent|order|file|title
                    NEXT_ID|NNNN   (max id across active + archived, plus one,
                    skipping ids reserved by issue-new-id leases)
    tree grammar (blank and comment lines are not data; title is always the
    last field and may contain '|'):
                  SUMMARY|themes=N|issues=N|P0=N|P1=N|P2=N|P3=N|blocked=N
                  NEXT|id|theme|priority|status|title   (absent when nothing actionable)
                  ## THEME|id|priority|status|title
                  - id|theme|parent|priority|status|title  (indent = nesting, 3 spaces
                    per level; parent "-" = theme root)

    Run from the repo root. The script ships inside the issue-tracking skill folder
    (next to its SKILL.md), so invoke it by its own path - installed at:
    pwsh ~/.agents/skills/issue-tracking/scripts/issue-tree.ps1 - the issue store is
    resolved relative to the current directory, never relative to this file.

.EXAMPLE
    pwsh ~/.agents/skills/issue-tracking/scripts/issue-tree.ps1
.EXAMPLE
    pwsh ~/.agents/skills/issue-tracking/scripts/issue-tree.ps1 -Check
.EXAMPLE
    pwsh ~/.agents/skills/issue-tracking/scripts/issue-tree.ps1 -Inventory
#>
param(
    [switch]$Check,
    [switch]$Inventory
)

$ErrorActionPreference = 'Stop'
. (Join-Path -Path $PSScriptRoot -ChildPath 'issue-id-lib.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'issue-template-lib.ps1')

# --- Store resolution: manifest first, .issues fallback (repo-agnostic) ------
$issuesDir = '.issues'
$treePath = Join-Path -Path $issuesDir -ChildPath 'tree.md'
$archiveDir = Join-Path -Path $issuesDir -ChildPath 'archived'
$issueTemplatesDir = '.github/ISSUE_TEMPLATE'
$issueTemplateOverrides = $null
$manifestPath = Join-Path -Path '.github' -ChildPath 'issue-tracker.json'
$tracker = 'local-markdown'
$treeSource = 'local-markdown'
$githubMode = $false
if (Test-Path -LiteralPath $manifestPath) {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $names = @($manifest.PSObject.Properties.Name)
    if ($names -contains 'tracker' -and
        -not [string]::IsNullOrWhiteSpace([string]$manifest.tracker)) {
        $tracker = [string]$manifest.tracker
    }
    if ($names -contains 'treeSource' -and
        -not [string]::IsNullOrWhiteSpace([string]$manifest.treeSource)) {
        $treeSource = [string]$manifest.treeSource
    }
    # Compound guard (sketch v6 section 1.2): run for the local store or for a
    # github tree source only. azure-devops (and any other tracker) stays
    # refused by the explicit tracker clause; a missing treeSource behaves as
    # local-markdown, so old github manifests fail closed until the manifest
    # declares treeSource: github.
    if ($tracker -ne 'local-markdown' -and
        -not ($tracker -eq 'github' -and $treeSource -eq 'github')) {
        "issue-tree: tracker '$tracker' is not local-markdown - this script only handles the local file store (issue-tracking skill, step 0)"
        if ($tracker -eq 'github') {
            "issue-tree: treeSource is '$treeSource' - set treeSource: 'github' in .github/issue-tracker.json to use the synced github tree"
        }
        exit 1
    }
    $githubMode = ($tracker -eq 'github' -and $treeSource -eq 'github')
    if ($names -contains 'issuesDir' -and -not [string]::IsNullOrWhiteSpace([string]$manifest.issuesDir)) {
        $issuesDir = [string]$manifest.issuesDir
    }
    if ($names -contains 'treeFile' -and -not [string]::IsNullOrWhiteSpace([string]$manifest.treeFile)) {
        $treePath = [string]$manifest.treeFile
    }
    else {
        $treePath = Join-Path -Path $issuesDir -ChildPath 'tree.md'
    }
    if ($names -contains 'archiveDir' -and -not [string]::IsNullOrWhiteSpace([string]$manifest.archiveDir)) {
        $archiveDir = [string]$manifest.archiveDir
    }
    else {
        $archiveDir = Join-Path -Path $issuesDir -ChildPath 'archived'
    }
    # Template registry (references/issue-templates.md): consumer overrides of
    # the skill-default issue templates, resolved per issue type.
    if ($names -contains 'issueTemplatesDir' -and
        -not [string]::IsNullOrWhiteSpace([string]$manifest.issueTemplatesDir)) {
        $issueTemplatesDir = [string]$manifest.issueTemplatesDir
    }
    if ($names -contains 'issueTemplateOverrides') {
        $issueTemplateOverrides = $manifest.issueTemplateOverrides
    }
}
$issuesLabel = $issuesDir -replace '\\', '/'
$treeLabel = $treePath -replace '\\', '/'

# --- Github tree source: parse-only semantics (sketch v6 section 1.3) --------
# treeSource: github means the committed treeFile is the source of truth.
# Never regenerate it here, never require the local store: -Inventory echoes
# the parsed data rows, -Check is structural self-consistency (parser +
# count cross-checks, no byte-compare against a regeneration), and a plain
# run is a no-op pointer to the sync script.
function Read-GithubTreeFile {
    param([string]$Path)
    $state = [pscustomobject]@{
        Fail       = $null
        DataLines  = New-Object System.Collections.Generic.List[string]
        Summary    = @{}
        RowIds     = @{}
        ThemeTotal = 0
        RowTotal   = 0
    }
    $summarySeen = $false
    $nextId = $null
    $currentThemeId = $null
    $sectionIds = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($state.Fail) { break }
        if ($line -match '^SUMMARY\|') {
            $summarySeen = $true
            $state.DataLines.Add($line)
            foreach ($seg in (($line -split '\|') | Select-Object -Skip 1)) {
                if ($seg -match '^([^=]+)=(\d+)$') {
                    $key = $Matches[1]
                    $rawValue = $Matches[2]
                    if ($key -notmatch '^[A-Za-z0-9_]+$') {
                        $state.Fail = "SUMMARY key '$key' is invalid (allowed: A-Z a-z 0-9 _)"
                        break
                    }
                    $value = 0L
                    if (-not [long]::TryParse($rawValue, [ref]$value)) {
                        $state.Fail = "SUMMARY segment '$seg' value is out of range"
                        break
                    }
                    $state.Summary[$key] = $value
                }
                else {
                    $state.Fail = "malformed SUMMARY segment '$seg'"
                    break
                }
            }
            continue
        }
        if ($line -match '^NEXT\|') {
            $f = $line -split '\|', 6
            if ($f.Count -lt 6) { $state.Fail = 'malformed NEXT line'; continue }
            $nextId = $f[1]
            $state.DataLines.Add($line)
            continue
        }
        if ($line -match '^## THEME\|') {
            $f = $line -split '\|', 5
            if ($f.Count -lt 5) { $state.Fail = 'malformed THEME line'; continue }
            $currentThemeId = $f[1]
            $sectionIds = @{}
            $state.ThemeTotal++
            $state.DataLines.Add($line)
            continue
        }
        if ($line -match '^( *)- \|') { $state.Fail = 'malformed row line'; continue }
        if ($line -match '^( *)- ') {
            $indent = $Matches[1].Length
            if ($indent % 3 -ne 0) { $state.Fail = "row indent $indent is not a multiple of 3"; continue }
            $f = ($line -replace '^( *)- ', '') -split '\|', 6
            if ($f.Count -lt 6) { $state.Fail = "malformed row '$line'"; continue }
            if ($null -eq $currentThemeId) { $state.Fail = "row '$($f[0])' appears before any THEME section"; continue }
            if ($f[1] -ne $currentThemeId) { $state.Fail = "row '$($f[0])' theme '$($f[1])' != section '$currentThemeId'"; continue }
            if ($state.RowIds.ContainsKey($f[0])) { $state.Fail = "duplicate row id '$($f[0])'"; continue }
            # Non-root = nested row that names a parent: it must resolve to an
            # earlier row of this section (dead "no visible parent" branch,
            # audit F.3). Root rows (depth 0, or parent "-" / empty) keep a
            # foreign parent as a retained hint - promotion severing is legal.
            $depth = [int]($indent / 3)
            $parentId = $f[2]
            if ($depth -gt 0 -and -not [string]::IsNullOrWhiteSpace($parentId) -and
                $parentId -ne '-' -and -not $sectionIds.ContainsKey($parentId)) {
                $state.Fail = "row '$($f[0])' parent '$parentId' does not exist earlier in section '$currentThemeId'"
                continue
            }
            $state.RowIds[$f[0]] = $true
            $sectionIds[$f[0]] = $true
            $state.RowTotal++
            $state.DataLines.Add($line)
            continue
        }
        # blank, comment and heading lines are not data
    }
    if ($state.Fail) { return $state }
    if (-not $summarySeen) { $state.Fail = 'no SUMMARY line'; return $state }
    if ($state.ThemeTotal -eq 0) { $state.Fail = 'no THEME sections'; return $state }
    if ($state.Summary.ContainsKey('themes') -and $state.Summary['themes'] -ne $state.ThemeTotal) {
        $state.Fail = "SUMMARY themes=$($state.Summary['themes']) but parsed $($state.ThemeTotal) sections"
        return $state
    }
    if ($state.Summary.ContainsKey('issues') -and $state.Summary['issues'] -ne $state.RowTotal) {
        $state.Fail = "SUMMARY issues=$($state.Summary['issues']) but parsed $($state.RowTotal) rows"
        return $state
    }
    if ($state.Summary.ContainsKey('total') -and $state.Summary['total'] -lt $state.RowTotal) {
        $state.Fail = "SUMMARY total=$($state.Summary['total']) is below issues=$($state.RowTotal)"
        return $state
    }
    if ($null -ne $nextId -and -not $state.RowIds.ContainsKey($nextId)) {
        $state.Fail = "NEXT id '$nextId' does not exist in the tree"
        return $state
    }
    return $state
}

if ($githubMode) {
    if ($Check -and $Inventory) {
        "issue-tree: pass either -Check or -Inventory, not both"
        exit 1
    }
    if (-not $Check -and -not $Inventory) {
        "github tree source: run sync-github-tree.ps1 to regenerate"
        exit 0
    }
    $absGithubTree = Join-Path -Path (Get-Location).Path -ChildPath $treePath
    if (-not (Test-Path -LiteralPath $absGithubTree)) {
        "TREE    $treeLabel is missing - run: pwsh <skill-folder>/scripts/sync-github-tree.ps1"
        exit 1
    }
    $parsed = Read-GithubTreeFile -Path $absGithubTree
    if ($parsed.Fail) {
        "TREE    ${treeLabel}: $($parsed.Fail)"
        "issue-tree: FAILED - fix the TREE errors above, then re-run"
        exit 1
    }
    if ($Inventory) {
        foreach ($dataLine in $parsed.DataLines) { $dataLine }
        exit 0
    }
    "issue-tree: OK ($($parsed.ThemeTotal) themes, $($parsed.RowTotal) issues, tree.md structurally consistent)"
    exit 0
}

if (-not (Test-Path -LiteralPath $issuesDir)) {
    "issue-tree: issue store '$issuesLabel' not found - create it, or point .github/issue-tracker.json issuesDir at it"
    exit 1
}

# Enums and the frontmatter contract live in issue-template-lib.ps1 (single
# source shared with the template CLI and the manifest writer).
$validStatus = $issueValidStatus
$validPriority = $issueValidPriority
$validType = $issueValidType

$fail = $false

# --- Template set: skill defaults + manifest-registered overrides -----------
# references/issue-templates.md. A broken default or a broken registration
# fails the gate here, before any store file is looked at.
$templatesLabel = $issueTemplatesDir -replace '\\', '/'
$templateSet = @{ Templates = @{}; Errors = @() }
if (-not (Test-IssueRepoRelativePath -Value $issueTemplatesDir)) {
    $fail = $true
    "TEMPLATE   ${templatesLabel}: issueTemplatesDir must be repo-relative (no root, no ..)"
}
else {
    $templateSet = Get-IssueTemplateSet `
        -DefaultsDir (Join-Path -Path $PSScriptRoot -ChildPath '..\assets\issue-templates') `
        -TemplatesDir $issueTemplatesDir `
        -TemplatesLabel $templatesLabel `
        -Overrides $issueTemplateOverrides
    foreach ($templateError in $templateSet.Errors) {
        $fail = $true
        "TEMPLATE   $templateError"
    }
}

function Get-PriorityRank {
    param([string]$Priority)
    switch ($Priority) {
        'P0' { return 0 }
        'P1' { return 1 }
        'P2' { return 2 }
        'P3' { return 3 }
        default { return 9 }
    }
}

function Get-ChildLines {
    # Nested sub-issues of one parent inside a theme, depth-first, sorted input.
    param(
        [string]$ParentId,
        $ThemeChildren,
        [int]$Depth,
        $Seen
    )
    $result = @()
    foreach ($child in $ThemeChildren) {
        if ($child.Parent -ne $ParentId) { continue }
        if ($Seen.ContainsKey($child.Id)) { continue }
        $Seen[$child.Id] = $true
        $indent = '   ' * $Depth
        $result += "$indent- $($child.Id)|$($child.ResolvedTheme)|$($child.Parent)|$($child.Priority)|$($child.Status)|$($child.Title)"
        $result += Get-ChildLines -ParentId $child.Id -ThemeChildren $ThemeChildren -Depth ($Depth + 1) -Seen $Seen
    }
    return $result
}

# Frontmatter parsing lives in issue-template-lib.ps1 (Read-IssueDocument) -
# one parser for store files and templates, so comment/quote semantics cannot
# drift between the validator and the template gate.

# --- 1. Load and validate frontmatter ---------------------------------------
$records = @()
$byId = @{}

$files = Get-ChildItem -LiteralPath $issuesDir -File -Filter '*.md' |
    Where-Object { $_.Name -match '^\d{4}-' } |
    Sort-Object Name

foreach ($file in $files) {
    $fileId = $file.Name.Substring(0, 4)
    $doc = Read-IssueDocument -Path $file.FullName
    $fm = $doc.Frontmatter
    if ($null -eq $fm) {
        $fail = $true
        "THEME   $issuesLabel/$($file.Name): missing or malformed YAML frontmatter"
        continue
    }
    foreach ($required in @('id', 'title', 'status', 'priority', 'type', 'created')) {
        if (-not $fm.ContainsKey($required) -or [string]::IsNullOrWhiteSpace($fm[$required])) {
            $fail = $true
            "THEME   $issuesLabel/$($file.Name): missing required frontmatter field '$required'"
        }
    }
    if ($fm.ContainsKey('id') -and $fm['id'] -ne $fileId) {
        $fail = $true
        "THEME   $issuesLabel/$($file.Name): id '$($fm['id'])' does not match the filename"
    }
    if ($fm.ContainsKey('status') -and $validStatus -notcontains $fm['status']) {
        $fail = $true
        "THEME   $issuesLabel/$($file.Name): invalid status '$($fm['status'])'"
    }
    if ($fm.ContainsKey('priority') -and $validPriority -notcontains $fm['priority']) {
        $fail = $true
        "THEME   $issuesLabel/$($file.Name): invalid priority '$($fm['priority'])'"
    }
    if ($fm.ContainsKey('type') -and $validType -notcontains $fm['type']) {
        $fail = $true
        "THEME   $issuesLabel/$($file.Name): invalid type '$($fm['type'])' (expected theme|epic|task|bug|chore)"
    }
    if ($fm.ContainsKey('created') -and -not [string]::IsNullOrWhiteSpace($fm['created'])) {
        $createdDate = [datetime]::MinValue
        if ($fm['created'] -notmatch '^\d{4}-\d{2}-\d{2}$' -or
            -not [datetime]::TryParseExact($fm['created'], 'yyyy-MM-dd',
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::None,
                [ref]$createdDate)) {
            $fail = $true
            "THEME   $issuesLabel/$($file.Name): created '$($fm['created'])' is not a YYYY-MM-DD date"
        }
    }
    $order = 999
    if ($fm.ContainsKey('order') -and -not [string]::IsNullOrWhiteSpace($fm['order'])) {
        $parsedOrder = 0
        if ([int]::TryParse($fm['order'], [ref]$parsedOrder)) {
            $order = $parsedOrder
        }
        else {
            $fail = $true
            "THEME   $issuesLabel/$($file.Name): order '$($fm['order'])' is not an integer"
        }
    }
    # Template conformance (references/issue-templates.md): field policy and
    # required body sections come from the resolved template. A file whose
    # type has no usable template is already failed by the template set above.
    if ($fm.ContainsKey('type') -and
        $templateSet.Templates.ContainsKey([string]$fm['type'])) {
        $fileTemplate = $templateSet.Templates[[string]$fm['type']]
        $conformanceErrors = Test-IssueTemplateConformance -Frontmatter $fm `
            -Headings $doc.Headings -Template $fileTemplate
        foreach ($templateError in $conformanceErrors) {
            $fail = $true
            "TEMPLATE   $issuesLabel/$($file.Name): $templateError"
        }
    }
    if ($byId.ContainsKey($fileId)) {
        $fail = $true
        "THEME   $issuesLabel/$($file.Name): duplicate issue id $fileId"
        continue
    }
    $record = [pscustomobject]@{
        File          = $file.Name
        Id            = $fileId
        Title         = $(if ($fm.ContainsKey('title')) { $fm['title'] } else { '' })
        Status        = $(if ($fm.ContainsKey('status')) { $fm['status'] } else { '' })
        Priority      = $(if ($fm.ContainsKey('priority')) { $fm['priority'] } else { '' })
        Type          = $(if ($fm.ContainsKey('type')) { $fm['type'] } else { '' })
        Theme         = $(if ($fm.ContainsKey('theme')) { $fm['theme'] } else { '' })
        Parent        = $(if ($fm.ContainsKey('parent')) { $fm['parent'] } else { '' })
        Order         = $order
        ResolvedTheme = ''
    }
    $byId[$fileId] = $record
    $records += $record
}

# --- 2. Parent chains: exist, no cycles --------------------------------------
foreach ($record in $records) {
    if ([string]::IsNullOrWhiteSpace($record.Parent)) { continue }
    $visited = @{}
    $visited[$record.Id] = $true
    $cursor = $record
    while (-not [string]::IsNullOrWhiteSpace($cursor.Parent)) {
        if ($visited.ContainsKey($cursor.Parent)) {
            $fail = $true
            "THEME   $issuesLabel/$($record.File): parent chain cycles at '$($cursor.Parent)'"
            break
        }
        if (-not $byId.ContainsKey($cursor.Parent)) {
            $fail = $true
            "THEME   $issuesLabel/$($record.File): parent '$($cursor.Parent)' does not exist"
            break
        }
        $visited[$cursor.Parent] = $true
        $cursor = $byId[$cursor.Parent]
    }
}

# --- 3. Theme relations ------------------------------------------------------
foreach ($record in $records) {
    if ($record.Type -eq 'theme') {
        if (-not [string]::IsNullOrWhiteSpace($record.Theme)) {
            $fail = $true
            "THEME   $issuesLabel/$($record.File): a theme must not declare 'theme:'"
        }
        if (-not [string]::IsNullOrWhiteSpace($record.Parent)) {
            $fail = $true
            "THEME   $issuesLabel/$($record.File): a theme must not declare 'parent:'"
        }
        continue
    }
    if (-not [string]::IsNullOrWhiteSpace($record.Theme)) {
        if (-not $byId.ContainsKey($record.Theme)) {
            $fail = $true
            "THEME   $issuesLabel/$($record.File): theme '$($record.Theme)' does not exist"
        }
        elseif ($byId[$record.Theme].Type -ne 'theme') {
            $fail = $true
            "THEME   $issuesLabel/$($record.File): theme '$($record.Theme)' is not a theme issue"
        }
        else {
            $record.ResolvedTheme = $record.Theme
        }
        continue
    }
    if ([string]::IsNullOrWhiteSpace($record.Parent)) {
        $fail = $true
        "THEME   $issuesLabel/$($record.File): not related to a theme - add 'theme: <id>' (or a parent chain ending at a theme)"
        continue
    }
    # Indirect relation: walk the parent chain until a theme (or a themed issue).
    $seen = @{}
    $seen[$record.Id] = $true
    $cursor = $record
    $resolved = $null
    $chainError = $null
    while (-not [string]::IsNullOrWhiteSpace($cursor.Parent)) {
        if ($seen.ContainsKey($cursor.Parent)) {
            $chainError = "parent chain cycles at '$($cursor.Parent)'"
            break
        }
        if (-not $byId.ContainsKey($cursor.Parent)) {
            $chainError = "parent '$($cursor.Parent)' does not exist"
            break
        }
        $seen[$cursor.Parent] = $true
        $cursor = $byId[$cursor.Parent]
        if ($cursor.Type -eq 'theme') {
            $resolved = $cursor.Id
            break
        }
        if (-not [string]::IsNullOrWhiteSpace($cursor.Theme)) {
            if (-not $byId.ContainsKey($cursor.Theme) -or $byId[$cursor.Theme].Type -ne 'theme') {
                $chainError = "parent '$($cursor.Id)' references invalid theme '$($cursor.Theme)'"
            }
            else {
                $resolved = $cursor.Theme
            }
            break
        }
    }
    if ($chainError) {
        $fail = $true
        "THEME   $issuesLabel/$($record.File): $chainError"
    }
    elseif ($null -eq $resolved) {
        $fail = $true
        "THEME   $issuesLabel/$($record.File): parent chain '$($record.Parent)' does not reach a theme"
    }
    else {
        $record.ResolvedTheme = $resolved
    }
}

# Every theme must carry active work (otherwise it is clutter to archive), and
# its status must agree with its completion - a theme rendered at 100% beside an
# 'open' pill is self-contradictory. Completion is the view's own definition
# (assets/tree-template.html): done / (children - dropped), an all-dropped theme
# being vacuously complete. Status stays authoritative (enforced, not derived),
# and the two directions are mutually exclusive, so any reported state has a fix.
foreach ($record in $records) {
    if ($record.Type -ne 'theme') { continue }
    $members = @($records | Where-Object {
        $_.Type -ne 'theme' -and $_.ResolvedTheme -eq $record.Id
    })
    if ($members.Count -eq 0) {
        $fail = $true
        "THEME   $issuesLabel/$($record.File): theme has no active child issues"
        continue
    }
    $countable = $members.Count - @($members | Where-Object { $_.Status -eq 'dropped' }).Count
    $doneCount = @($members | Where-Object { $_.Status -eq 'done' }).Count
    $pct = 100
    if ($countable -gt 0) {
        # Round half away from zero: JavaScript's Math.round, so this percentage
        # and the one the HTML view prints can never drift apart.
        $pct = [int][math]::Round($doneCount * 100 / $countable,
            [System.MidpointRounding]::AwayFromZero)
    }
    $complete = ($doneCount -eq $countable)
    if ($complete -and $record.Status -ne 'done' -and $record.Status -ne 'dropped') {
        $fail = $true
        $scope = "$doneCount of $countable child issues done"
        if ($countable -eq 0) { $scope = 'every child is dropped' }
        "THEME   $issuesLabel/$($record.File): theme is 100% complete ($scope) but status is '$($record.Status)' - set 'status: done'"
    }
    elseif ($record.Status -eq 'done' -and -not $complete) {
        $fail = $true
        $remaining = @($members |
            Where-Object { $_.Status -ne 'done' -and $_.Status -ne 'dropped' } |
            Group-Object Status |
            Sort-Object Name |
            ForEach-Object { "$($_.Count) $($_.Name)" })
        "THEME   $issuesLabel/$($record.File): theme is marked done but only $pct% complete ($($countable - $doneCount) of $countable child issues not done: $($remaining -join ', '))"
    }
}

if ($fail) {
    "issue-tree: FAILED - fix the THEME and TEMPLATE errors above, then re-run"
    exit 1
}

if ($Check -and $Inventory) {
    "issue-tree: pass either -Check or -Inventory, not both"
    exit 1
}

# --- 4. Inventory: the store as machine rows ---------------------------------
if ($Inventory) {
    'id|type|status|priority|theme|parent|order|file|title'
    foreach ($record in $records) {
        $themeField = '-'
        if (-not [string]::IsNullOrWhiteSpace($record.ResolvedTheme)) {
            $themeField = $record.ResolvedTheme
        }
        $parentField = '-'
        if (-not [string]::IsNullOrWhiteSpace($record.Parent)) {
            $parentField = $record.Parent
        }
        "$($record.Id)|$($record.Type)|$($record.Status)|$($record.Priority)|$themeField|$parentField|$($record.Order)|$($record.File)|$($record.Title)"
    }
    $maxId = 0
    foreach ($record in $records) {
        $parsedId = 0
        if ([int]::TryParse($record.Id, [ref]$parsedId) -and $parsedId -gt $maxId) {
            $maxId = $parsedId
        }
    }
    $archivedDir = $archiveDir
    if (Test-Path -LiteralPath $archivedDir) {
        foreach ($archived in (Get-ChildItem -LiteralPath $archivedDir -File -Filter '*.md')) {
            if ($archived.Name -match '^(\d{4})-') {
                $parsedId = [int]$Matches[1]
                if ($parsedId -gt $maxId) { $maxId = $parsedId }
            }
        }
    }
    # NEXT_ID must agree with the allocator (issue-new-id.ps1): skip ids that
    # are only reserved (outstanding lease in the shared git-common-dir store).
    $nextCandidate = $maxId + 1
    $reservedLeases = Get-IssueIdLeases -LeaseDir (Get-IssueIdLeaseDir)
    while ($nextCandidate -le 9999 -and
        $reservedLeases.Active.ContainsKey(('{0:D4}' -f $nextCandidate))) {
        $nextCandidate++
    }
    $nextId = '{0:D4}' -f $nextCandidate
    ''
    "NEXT_ID|$nextId"
    exit 0
}

# --- 5. Render the tree ------------------------------------------------------
$themes = @($records |
    Where-Object { $_.Type -eq 'theme' } |
    Sort-Object @{ Expression = { Get-PriorityRank $_.Priority } }, @{ Expression = { $_.Id } })
$children = @($records | Where-Object { $_.Type -ne 'theme' })
$sortedChildren = @($children |
    Sort-Object @{ Expression = { Get-PriorityRank $_.Priority } },
                 @{ Expression = { $_.Order } },
                 @{ Expression = { $_.Id } })

$pCounts = @{}
foreach ($priority in $validPriority) { $pCounts[$priority] = 0 }
$blocked = 0
foreach ($child in $children) {
    if ($pCounts.ContainsKey($child.Priority)) { $pCounts[$child.Priority]++ }
    if ($child.Status -eq 'blocked') { $blocked++ }
}
$lines = @()
$lines += '# Issue tree'
$lines += ''
$lines += '<!-- Generated by issue-tree.ps1 (issue-tracking skill) - do not edit by hand. -->'
$lines += '<!-- Regenerate: pwsh <skill-folder>/scripts/issue-tree.ps1 | Validate: the same script with -Check -->'
$lines += '<!-- Human view: .issues/tree.html - render: pwsh <skill-folder>/scripts/render-issue-tree.ps1 -->'
$lines += '<!-- Machine grammar (blank and comment lines are not data): -->'
$lines += '<!--   SUMMARY|themes=N|issues=N|P0=N|P1=N|P2=N|P3=N|blocked=N -->'
$lines += '<!--   NEXT|id|theme|priority|status|title          (absent when nothing actionable) -->'
$lines += '<!--   ## THEME|id|priority|status|title -->'
$lines += '<!--   - id|theme|parent|priority|status|title      (indent = nesting, 3 spaces per -->'
$lines += '<!--     level, parent "-" = theme root; title is last and may contain "|") -->'
$lines += ''
$lines += "SUMMARY|themes=$($themes.Count)|issues=$($children.Count)|P0=$($pCounts['P0'])|P1=$($pCounts['P1'])|P2=$($pCounts['P2'])|P3=$($pCounts['P3'])|blocked=$blocked"
$lines += ''

# "What to do next": first actionable child in theme order.
$next = $null
foreach ($theme in $themes) {
    foreach ($child in @($sortedChildren | Where-Object { $_.ResolvedTheme -eq $theme.Id })) {
        if ($child.Status -eq 'open' -or $child.Status -eq 'in-progress') {
            $next = $child
            break
        }
    }
    if ($null -ne $next) { break }
}
if ($null -ne $next) {
    $lines += "NEXT|$($next.Id)|$($next.ResolvedTheme)|$($next.Priority)|$($next.Status)|$($next.Title)"
    $lines += ''
}

foreach ($theme in $themes) {
    $lines += "## THEME|$($theme.Id)|$($theme.Priority)|$($theme.Status)|$($theme.Title)"
    $lines += ''
    $themeChildren = @($sortedChildren | Where-Object { $_.ResolvedTheme -eq $theme.Id })
    $memberIds = @{}
    foreach ($member in $themeChildren) { $memberIds[$member.Id] = $true }
    $roots = @($themeChildren | Where-Object {
        [string]::IsNullOrWhiteSpace($_.Parent) -or -not $memberIds.ContainsKey($_.Parent)
    })
    $seen = @{}
    foreach ($root in $roots) {
        $seen[$root.Id] = $true
        $rootParent = '-'
        if (-not [string]::IsNullOrWhiteSpace($root.Parent)) { $rootParent = $root.Parent }
        $lines += "- $($root.Id)|$($root.ResolvedTheme)|$rootParent|$($root.Priority)|$($root.Status)|$($root.Title)"
        $lines += Get-ChildLines -ParentId $root.Id -ThemeChildren $themeChildren -Depth 1 -Seen $seen
    }
    $lines += ''
}

$generated = ($lines -join [Environment]::NewLine) + [Environment]::NewLine
$absTree = Join-Path -Path (Get-Location).Path -ChildPath $treePath

if ($Check) {
    if (-not (Test-Path -LiteralPath $absTree)) {
        "TREE    $treeLabel is missing - run: pwsh $PSCommandPath"
        exit 1
    }
    $existing = [System.IO.File]::ReadAllText($absTree, [System.Text.Encoding]::UTF8)
    $normExisting = ($existing -replace "`r`n", "`n").TrimEnd("`n")
    $normGenerated = ($generated -replace "`r`n", "`n").TrimEnd("`n")
    if ($normExisting -ne $normGenerated) {
        "TREE    $treeLabel is stale - run: pwsh $PSCommandPath"
        exit 1
    }
    "issue-tree: OK ($($themes.Count) themes, $($children.Count) issues, tree.md fresh)"
    exit 0
}

[System.IO.File]::WriteAllText($absTree, $generated, [System.Text.UTF8Encoding]::new($false))
"issue-tree: OK ($($themes.Count) themes, $($children.Count) issues, wrote $treeLabel)"
exit 0
