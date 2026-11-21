<#
.SYNOPSIS
    Renders the generated issue tree (.issues/tree.md) into a self-contained,
    deterministic static HTML page - the skill's primary human-facing surface.

.DESCRIPTION
    Reads the tree file (path from .github/issue-tracker.json, default
    .issues/tree.md), parses it per its machine grammar, embeds the result as
    JSON into assets/tree-template.html (inline CSS + JS, no external deps,
    opens over file://) and writes it next to the tree file as .html.

    Determinism: same tree file + same template -> byte-identical HTML
    (no timestamps; stable key order; platform line endings only).

    Validation (both trackers): SUMMARY keys must match [A-Za-z0-9_], values
    must fit a 64-bit integer, row ids must be unique, a nested row must name
    a parent row earlier in its section, and the embedded JSON is parse-checked
    before hydration. The manifest guard runs only for tracker local-markdown
    or tracker github + treeSource github (missing treeSource = local-markdown).

    Template versioning: assets/tree-template.version.json records the current
    template version + sha256 fingerprint. The fingerprint is verified before
    hydrating (an edit to assets/tree-template.html without a version bump via
    bump-tree-template-version.ps1 fails here), and the version is embedded in
    the page (meta tree-template-version + footer) so -Check can report template
    version drift separately from tree-data staleness - a version mismatch means
    the installed skill's template moved and re-rendering patches the output.

    Modes:
      default   write the HTML file
      -Check    fail (exit 1) when the HTML file is missing, built by another
                template version (drift), or stale (repo issue lint, pre-commit
                gate)
    -Out overrides the output path (default: tree file with .html extension).

    Interactive features live in the template: search (/), status/priority
    filter chips, expand/collapse, click-to-copy ids, NEXT callout, hash
    deep links (#0001) with highlight, light/dark via prefers-color-scheme.

.EXAMPLE
    pwsh ~/.agents/skills/issue-tracking/scripts/render-issue-tree.ps1
.EXAMPLE
    pwsh ~/.agents/skills/issue-tracking/scripts/render-issue-tree.ps1 -Check
#>
param(
    [switch]$Check,
    [string]$Out
)

$ErrorActionPreference = 'Stop'

$manifestPath = Join-Path -Path '.github' -ChildPath 'issue-tracker.json'
$treePath = '.issues/tree.md'
$tracker = 'local-markdown'
if (Test-Path -LiteralPath $manifestPath) {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $names = @($manifest.PSObject.Properties.Name)
    $treeSource = 'local-markdown'
    if ($names -contains 'treeSource' -and -not [string]::IsNullOrWhiteSpace([string]$manifest.treeSource)) {
        $treeSource = [string]$manifest.treeSource
    }
    if ($names -contains 'tracker' -and -not [string]::IsNullOrWhiteSpace([string]$manifest.tracker)) {
        $tracker = [string]$manifest.tracker
    }
    # Compound guard (sketch v6 section 1.2): render the local store or a
    # github tree file only. azure-devops (and any other tracker) stays
    # refused by the explicit tracker clause; a missing treeSource behaves
    # as local-markdown, so old github manifests fail closed.
    if ($tracker -ne 'local-markdown' -and
        -not ($tracker -eq 'github' -and $treeSource -eq 'github')) {
        "render-tree: tracker '$tracker' is not local-markdown - HTML rendering only handles the local file store"
        if ($tracker -eq 'github') {
            "render-tree: treeSource is '$treeSource' - set treeSource: 'github' in .github/issue-tracker.json to render the synced github tree"
        }
        exit 1
    }
    if ($names -contains 'treeFile' -and -not [string]::IsNullOrWhiteSpace([string]$manifest.treeFile)) {
        $treePath = [string]$manifest.treeFile
    }
}
$treeLabel = $treePath -replace '\\', '/'

$templatePath = Join-Path -Path $PSScriptRoot -ChildPath '..\assets\tree-template.html'
$versionPath = Join-Path -Path $PSScriptRoot -ChildPath '..\assets\tree-template.version.json'
. (Join-Path -Path $PSScriptRoot -ChildPath 'template-version-lib.ps1')
if (-not (Test-Path -LiteralPath $templatePath)) {
    "render-tree: template not found at $templatePath (skill assets must ship with the script)"
    exit 1
}

# --- Verify the template's recorded version (integrity gate) --------------------
$versionState = Get-TreeTemplateVersionState -Path $versionPath
if ($versionState.Error) {
    "render-tree: $($versionState.Error)"
    "render-tree: create/repair it from the skill repo: pwsh <skill-folder>/scripts/bump-tree-template-version.ps1 -Version <new-version>"
    exit 1
}
$templateVersion = $versionState.Version
$actualSha256 = Get-TreeTemplateSha256 -Path $templatePath
if ($actualSha256 -ne $versionState.Sha256) {
    "render-tree: assets/tree-template.html changed without a version bump (recorded v$templateVersion, sha256 $($versionState.Sha256) -> $actualSha256)"
    "render-tree: bump it from the skill repo: pwsh <skill-folder>/scripts/bump-tree-template-version.ps1 -Version <new-version>"
    exit 1
}
if (-not (Test-Path -LiteralPath $treePath)) {
    "render-tree: tree file '$treeLabel' not found - run the issue-tree script first"
    exit 1
}

# --- Parse tree.md per its machine grammar ------------------------------------
$summaryList = New-Object System.Collections.Generic.List[string]   # "k":v fragments in file order
$summaryCount = @{}
$nextNode = $null
$themes = New-Object System.Collections.Generic.List[object]
$allIds = @{}
$rowTotal = 0
$filterPayload = ''
$currentTheme = $null
$sectionIds = @{}
$stack = New-Object System.Collections.Stack
$fail = $null

function ConvertTo-JsString {
    param([string]$Value)
    if ($null -eq $Value) { $Value = '' }
    $escaped = $Value.Replace('\', '\\').Replace('"', '\"')
    $escaped = $escaped.Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
    $escaped = $escaped.Replace('<', '\u003c').Replace('>', '\u003e').Replace('&', '\u0026')
    return '"' + $escaped + '"'
}

function New-RowNode {
    param([string]$Id, [string]$Theme, [string]$Parent, [string]$Priority, [string]$Status, [string]$Title)
    return [pscustomobject]@{
        Id       = $Id
        Theme    = $Theme
        Parent   = $Parent
        Priority = $Priority
        Status   = $Status
        Title    = $Title
        Children = New-Object System.Collections.Generic.List[object]
    }
}

foreach ($line in [System.IO.File]::ReadAllLines((Join-Path (Get-Location).Path $treePath))) {
    if ($fail) { break }
    # Optional FILTER line (sync-github-tree.ps1 writes it before SUMMARY):
    # its payload rides dataJson.filter for the snapshot banner. Absent ->
    # "" keeps local-markdown output byte-identical.
    if ($line -match '^FILTER\|(.*)$') {
        $filterPayload = $Matches[1]
        continue
    }
    if ($line -match '^SUMMARY\|') {
        foreach ($seg in (($line -split '\|') | Select-Object -Skip 1)) {
            if ($seg -match '^([^=]+)=(\d+)$') {
                $key = $Matches[1]
                $rawValue = $Matches[2]
                # Audit C2: a hostile key interpolates raw into the embedded
                # JSON - reject it before anything is built or hydrated.
                if ($key -notmatch '^[A-Za-z0-9_]+$') {
                    $fail = "SUMMARY key '$key' is invalid (allowed: A-Z a-z 0-9 _)"
                    break
                }
                # Digits are the grammar; long range keeps asOfEpoch-style
                # epoch values (and any oversized count) from crashing parse.
                $value = 0L
                if (-not [long]::TryParse($rawValue, [ref]$value)) {
                    $fail = "SUMMARY segment '$seg' value is out of range"
                    break
                }
                $summaryList.Add(('"{0}":{1}' -f $key, $rawValue))
                $summaryCount[$key] = $value
            }
            else {
                $fail = "malformed SUMMARY segment '$seg'"
            }
        }
        continue
    }
    if ($line -match '^NEXT\|') {
        $f = $line -split '\|', 6
        if ($f.Count -lt 6) { $fail = 'malformed NEXT line'; continue }
        $nextNode = @{ Id = $f[1]; Theme = $f[2]; Priority = $f[3]; Status = $f[4]; Title = $f[5] }
        continue
    }
    if ($line -match '^## THEME\|') {
        $f = $line -split '\|', 5
        if ($f.Count -lt 5) { $fail = 'malformed THEME line'; continue }
        $currentTheme = [pscustomobject]@{
            Id       = $f[1]
            Priority = $f[2]
            Status   = $f[3]
            Title    = $f[4]
            Children = New-Object System.Collections.Generic.List[object]
        }
        $themes.Add($currentTheme)
        $sectionIds = @{}
        $stack.Clear()
        $stack.Push(@{ Node = $currentTheme; Depth = -1 })
        continue
    }
    if ($line -match '^( *)- \|') { $fail = 'malformed row line'; continue }
    if ($line -match '^( *)- ') {
        $indent = $Matches[1].Length
        if ($indent % 3 -ne 0) { $fail = "row indent $indent is not a multiple of 3"; continue }
        $depth = [int]($indent / 3)
        $f = ($line -replace '^( *)- ', '') -split '\|', 6
        if ($f.Count -lt 6) { $fail = "malformed row '$line'"; continue }
        if ($null -eq $currentTheme) { $fail = "row '$($f[0])' appears before any THEME section"; continue }
        if ($f[1] -ne $currentTheme.Id) { $fail = "row '$($f[0])' theme '$($f[1])' != section '$($currentTheme.Id)'"; continue }
        if ($allIds.ContainsKey($f[0])) { $fail = "duplicate row id '$($f[0])'"; continue }
        # Non-root = nested row naming a parent: it must resolve to an earlier
        # row of this section (audit F.3's dead "no visible parent" branch).
        # Root rows (depth 0, or parent "-" / empty) may keep a foreign parent
        # as a retained hint - promoted rows are legal and stay green.
        if ($depth -gt 0 -and -not [string]::IsNullOrWhiteSpace($f[2]) -and $f[2] -ne '-' -and
            -not $sectionIds.ContainsKey($f[2])) {
            $fail = "row '$($f[0])' parent '$($f[2])' does not exist earlier in section '$($currentTheme.Id)'"
            continue
        }
        $node = New-RowNode -Id $f[0] -Theme $f[1] -Parent $f[2] -Priority $f[3] -Status $f[4] -Title $f[5]
        while ($stack.Count -gt 0 -and $stack.Peek().Depth -ge $depth) { [void]$stack.Pop() }
        if ($stack.Count -eq 0) {
            $fail = "row '$($f[0])' at depth $depth has no visible parent"
            continue
        }
        [void]$stack.Peek().Node.Children.Add($node)
        $stack.Push(@{ Node = $node; Depth = $depth })
        $allIds[$node.Id] = $true
        $sectionIds[$node.Id] = $true
        $rowTotal++
        continue
    }
    # everything else (heading, blanks, comments, grammar docs) is not data
}

if ($fail) {
    "render-tree: $fail - regenerate the tree first"
    exit 1
}
if ($summaryList.Count -eq 0) {
    "render-tree: no SUMMARY line in '$treeLabel' - is this really a tree file?"
    exit 1
}
if ($themes.Count -eq 0) {
    "render-tree: no THEME sections in '$treeLabel' - regenerate the tree first"
    exit 1
}
if ($summaryCount.ContainsKey('themes') -and $summaryCount['themes'] -ne $themes.Count) {
    "render-tree: SUMMARY themes=$($summaryCount['themes']) but parsed $($themes.Count) sections"
    exit 1
}
if ($summaryCount.ContainsKey('issues') -and $summaryCount['issues'] -ne $rowTotal) {
    "render-tree: SUMMARY issues=$($summaryCount['issues']) but parsed $rowTotal rows"
    exit 1
}
# Optional github-mode keys: total is a floor (>= the rows actually shown);
# asOfEpoch rides the digits-only grammar and the long parse above.
if ($summaryCount.ContainsKey('total') -and $summaryCount['total'] -lt $rowTotal) {
    "render-tree: SUMMARY total=$($summaryCount['total']) is below issues=$rowTotal"
    exit 1
}
if ($null -ne $nextNode -and -not $allIds.ContainsKey($nextNode.Id)) {
    "render-tree: NEXT id '$($nextNode.Id)' does not exist in the tree"
    exit 1
}

# --- Serialize to JSON (stable order, script-safe escaping) --------------------
function ConvertTo-RowJson {
    param($Row)
    $childJson = (($Row.Children | ForEach-Object { ConvertTo-RowJson -Row $_ }) -join ',')
    return ('{{"id":{0},"theme":{1},"parent":{2},"priority":{3},"status":{4},"title":{5},"children":[{6}]}}' -f
        (ConvertTo-JsString $Row.Id), (ConvertTo-JsString $Row.Theme), (ConvertTo-JsString $Row.Parent),
        (ConvertTo-JsString $Row.Priority), (ConvertTo-JsString $Row.Status), (ConvertTo-JsString $Row.Title),
        $childJson)
}
function ConvertTo-ThemeJson {
    param($Theme)
    $childJson = (($Theme.Children | ForEach-Object { ConvertTo-RowJson -Row $_ }) -join ',')
    return ('{{"id":{0},"priority":{1},"status":{2},"title":{3},"children":[{4}]}}' -f
        (ConvertTo-JsString $Theme.Id), (ConvertTo-JsString $Theme.Priority),
        (ConvertTo-JsString $Theme.Status), (ConvertTo-JsString $Theme.Title), $childJson)
}

$themeJson = (($themes | ForEach-Object { ConvertTo-ThemeJson -Theme $_ }) -join ',')
$summaryJson = '{' + ($summaryList -join ',') + '}'
$nextJson = 'null'
if ($null -ne $nextNode) {
    $nextJson = ('{{"id":{0},"theme":{1},"priority":{2},"status":{3},"title":{4}}}' -f
        (ConvertTo-JsString $nextNode.Id), (ConvertTo-JsString $nextNode.Theme),
        (ConvertTo-JsString $nextNode.Priority), (ConvertTo-JsString $nextNode.Status),
        (ConvertTo-JsString $nextNode.Title))
}
# Contract (sketch v6 section 3): {source, summary, next, filter, themes}.
# filter is always a string: the optional FILTER line's payload, or "" when
# the line is absent (local-markdown trees). It never rides SUMMARY - that
# grammar stays digits-only.
$dataJson = '{{"source":{0},"summary":{1},"next":{2},"filter":{3},"themes":[{4}]}}' -f
    (ConvertTo-JsString $treeLabel), $summaryJson, $nextJson,
    (ConvertTo-JsString $filterPayload), $themeJson

# Audit C2/E2: a payload that fails JSON.parse blanks the hydrated page while
# -Check stays green - fail here, before hydrating anything.
try {
    $null = $dataJson | ConvertFrom-Json
}
catch {
    "render-tree: embedded data JSON failed to parse: $($_.Exception.Message)"
    exit 1
}

# --- Hydrate the template -------------------------------------------------------
$template = [System.IO.File]::ReadAllText($templatePath)
$versionPlaceholderCount = ([regex]::Matches($template, '__TREE_TEMPLATE_VERSION__')).Count
if ($versionPlaceholderCount -eq 0) {
    "render-tree: no __TREE_TEMPLATE_VERSION__ placeholder in the template - the generated view would carry no version marker"
    exit 1
}
$placeholderCount = [regex]::Matches($template, '__ISSUE_TREE_DATA__').Count
if ($placeholderCount -ne 1) {
    "render-tree: expected exactly 1 __ISSUE_TREE_DATA__ placeholder in the template, found $placeholderCount"
    exit 1
}
$htmlLf = ($template.Replace('__TREE_TEMPLATE_VERSION__', $templateVersion).Replace('__ISSUE_TREE_DATA__', $dataJson) -replace "`r`n", "`n")
$html = $htmlLf.Replace("`n", [Environment]::NewLine)

if ([string]::IsNullOrWhiteSpace($Out)) {
    $Out = $treePath -replace '\.[^.]+$', '.html'
}
$OutLabel = $Out -replace '\\', '/'

if ($Check) {
    if (-not (Test-Path -LiteralPath $Out)) {
        "TREE-HTML  $OutLabel is missing - run: pwsh $PSCommandPath"
        exit 1
    }
    $existing = ([System.IO.File]::ReadAllText((Join-Path (Get-Location).Path $Out)) -replace "`r`n", "`n")
    $existingVersion = ''
    if ($existing -match 'name="tree-template-version"\s+content="([^"]*)"') {
        $existingVersion = $Matches[1]
    }
    if ($existingVersion -ne $templateVersion) {
        if ([string]::IsNullOrEmpty($existingVersion)) {
            "TREE-HTML  $OutLabel has no template version marker (built before versioning or by a foreign template)"
        }
        else {
            "TREE-HTML  $OutLabel version drift: generated with template v$existingVersion, current template is v$templateVersion"
        }
        "TREE-HTML  patch it (re-render embeds the new version) - run: pwsh $PSCommandPath"
        exit 1
    }
    if ($existing -ne $htmlLf) {
        "TREE-HTML  $OutLabel is stale (tree data changed) - run: pwsh $PSCommandPath"
        exit 1
    }
    "render-tree: OK ($($themes.Count) themes, $rowTotal issues, template v$templateVersion, $OutLabel fresh)"
    exit 0
}

$fullOut = Join-Path -Path (Get-Location).Path -ChildPath $Out
$outDir = Split-Path -Parent $fullOut
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
[System.IO.File]::WriteAllText($fullOut, $html, [System.Text.UTF8Encoding]::new($false))
"render-tree: OK ($($themes.Count) themes, $rowTotal issues, template v$templateVersion, wrote $OutLabel)"
exit 0
