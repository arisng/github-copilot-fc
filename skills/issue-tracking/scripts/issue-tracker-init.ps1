<#
.SYNOPSIS
    Bootstraps .github/issue-tracker.json - the manifest schema owned by the
    issue-tracking skill (schema: ../references/manifest-schema.md).

.DESCRIPTION
    Modes (pass exactly one):
      -Probe   scan the repo from the current directory (run from the repo root)
               and print evidence rows:
                 MANIFEST|present|<path>        (or MANIFEST|absent|<path>)
                 STORE|<dir>|<count>            repo-root dir holding NNNN-*.md files
                 REMOTE|<host>|<url>            (REMOTE|none|- when git/origin is absent)
                 PARSE|repo|owner/name|         github-style parse of the remote
                 PARSE|org|<org>|               azure-style parse of the remote
                 PARSE|project|<project>|
               Remote URLs are sanitized (userinfo such as user@ or user:token@ is
               stripped) before printing - credentials never reach the manifest.
      -Apply   validate the supplied fields against the schema and write
               .github/issue-tracker.json; refuses to overwrite an existing
               manifest unless -Force is given. The github-only tree fields
               (treeSource, limits, issueQuery) are checked per
               references/manifest-schema.md; issueQuery runs through
               scripts/query-composition-lib.ps1 (the reject list). The
               template registry (-IssueTemplatesDir, -IssueTemplateOverride
               type=file) registers consumer issue templates that override
               the skill defaults per issue type
               (references/issue-templates.md); every registration is
               validated (the file must exist and its template must declare
               the registered type), and a -Force rewrite carries the
               persisted registration over, merging new entries into it.
               -IssueTypes <type,...> sets the issue `type` taxonomy, replacing
               the shipped defaults (task, bug, feature) wholesale; a -Force
               rewrite carries a persisted list over. Names are validated as
               kebab-case, unique, and at most 25 (GitHub's per-owner ceiling).
               Every configured type must resolve to a template (shipped
               default or registered override).

    Schema ownership and the bootstrap flow (interactive vs autopilot inference)
    live in this skill's SKILL.md step 0 and references/manifest-schema.md.

.EXAMPLE
    pwsh ~/.agents/skills/issue-tracking/scripts/issue-tracker-init.ps1 -Probe
.EXAMPLE
    pwsh ~/.agents/skills/issue-tracking/scripts/issue-tracker-init.ps1 -Apply -Tracker local-markdown
.EXAMPLE
    pwsh ~/.agents/skills/issue-tracking/scripts/issue-tracker-init.ps1 -Apply -Tracker github -Repo owner/name -Force
.EXAMPLE
    pwsh ~/.agents/skills/issue-tracking/scripts/issue-tracker-init.ps1 -Apply -Tracker github -Repo owner/name -TreeFile .issues/tree.md -IssueQuery 'label:area/*' -Force
.EXAMPLE
    pwsh ~/.agents/skills/issue-tracking/scripts/issue-tracker-init.ps1 -Apply -Tracker local-markdown -Force -IssueTemplateOverride bug=bug-report.md
#>
param(
    [switch]$Probe,
    [switch]$Apply,
    [string]$Tracker,
    [string]$IssuesDir,
    [string]$ArchiveDir,
    [string]$TreeFile,
    [string]$TreeScript,
    [string]$LintTask,
    [string]$IssueTemplatesDir,
    [string[]]$IssueTemplateOverride,
    [string[]]$IssueTypes,
    [string]$Repo,
    [string]$Org,
    [string]$Project,
    [string]$TreeSource,
    [switch]$NoTree,
    [int]$TreeMaxIssues,
    [int]$TreeLookbackDays,
    [bool]$TreeIncludeClosed = $true,
    [string]$TreeMinPriority,
    [int]$TreeFreshnessHours,
    [string]$IssueQuery,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. (Join-Path -Path $PSScriptRoot -ChildPath 'issue-template-lib.ps1')

$validTrackers = @('local-markdown', 'github', 'azure-devops')
$manifestRel = '.github/issue-tracker.json'
$defaultTreeScript = '~/.agents/skills/issue-tracking/scripts/issue-tree.ps1'
# treeFile is no longer local-markdown-only: github accepts it too
# (manifest-schema.md); issuesDir/archiveDir stay store-only.
$storeKeys = @('issuesDir', 'archiveDir', 'issueTemplatesDir')
$repoRelativeKeys = @('issuesDir', 'archiveDir', 'treeFile', 'issueTemplatesDir')
$validTreeSources = @('local-markdown', 'github')
$githubParams = [ordered]@{
    TreeSource         = 'treeSource'
    NoTree             = '-NoTree'
    TreeMaxIssues      = 'treeMaxIssues'
    TreeLookbackDays   = 'treeLookbackDays'
    TreeIncludeClosed  = 'treeIncludeClosed'
    TreeMinPriority    = 'treeMinPriority'
    TreeFreshnessHours = 'treeFreshnessHours'
    IssueQuery         = 'issueQuery'
}

if ($Probe -eq $Apply) {
    "issue-tracker-init: pass exactly one of -Probe or -Apply (schema: references/manifest-schema.md in this skill)"
    exit 1
}

function Get-SanitizedUrl {
    # Strip userinfo (user@, user:token@) so credentials never reach stdout/manifest.
    param([string]$Url)
    return ($Url -replace '^(https?://)[^/@]+@', '$1')
}

function Get-GitRemoteUrl {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $url = & git remote get-url origin 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($url -join ''))) { $url = $null }
    }
    catch {
        $url = $null
    }
    finally {
        $ErrorActionPreference = $prev
    }
    if ($null -eq $url) { return $null }
    return (Get-SanitizedUrl ($url -join '').Trim())
}

function Get-RemoteParse {
    # Parse a remote URL into host / repo / org / project (absent keys = unknown).
    param([string]$Url)
    $r = @{}
    if ([string]::IsNullOrWhiteSpace($Url)) { return $r }
    if ($Url -match '^git@([^:]+):(.+)$') {
        $hostName = $Matches[1]
        $path = $Matches[2]
    }
    elseif ($Url -match '^[a-z]+://([^/]+)/(.+)$') {
        $hostName = $Matches[1]
        $path = $Matches[2]
    }
    else {
        return $r
    }
    $r['host'] = $hostName
    $path = $path -replace '\.git$', ''
    if ($hostName -eq 'github.com' -or $hostName -eq 'ssh.github.com') {
        if ($path -match '^[^/\s]+/[^/\s]+$') { $r['repo'] = $path }
    }
    elseif ($hostName -match 'dev\.azure\.com$' -or $hostName -like '*.visualstudio.com') {
        if ($path -match '^v3/([^/]+)/([^/]+)/(.+)$') {
            $r['org'] = $Matches[1]
            $r['project'] = $Matches[2]
            $r['repo'] = $Matches[3]
        }
        elseif ($path -match '^([^/]+)/([^/]+)/_git/([^/]+)$') {
            $r['org'] = $Matches[1]
            $r['project'] = $Matches[2]
            $r['repo'] = $Matches[3]
        }
        elseif ($hostName -like '*.visualstudio.com') {
            $r['org'] = $hostName.Split('.')[0]
        }
    }
    return $r
}

function Get-TrackerHostHint {
    param([string]$HostName)
    if ([string]::IsNullOrWhiteSpace($HostName)) { return $null }
    if ($HostName -eq 'github.com' -or $HostName -eq 'ssh.github.com') { return 'github' }
    if ($HostName -match 'dev\.azure\.com$' -or $HostName -like '*.visualstudio.com') { return 'azure-devops' }
    return $HostName
}

function Test-RepoRelative {
    # Delegates to the template library so the repo-relative rule has exactly
    # one implementation (same pattern as query-composition-lib.ps1).
    param([string]$Value)
    return Test-IssueRepoRelativePath -Value $Value
}

# --- -Probe: evidence rows for the skill's bootstrap decision -----------------
if ($Probe) {
    if (Test-Path -LiteralPath $manifestRel) {
        "MANIFEST|present|$manifestRel"
    }
    else {
        "MANIFEST|absent|$manifestRel"
    }
    $skipDirs = @('.git', 'node_modules', 'bin', 'obj')
    foreach ($dir in (Get-ChildItem -LiteralPath . -Directory -Force | Where-Object { $skipDirs -notcontains $_.Name })) {
        $count = @(Get-ChildItem -LiteralPath $dir.FullName -File -Filter '*.md' |
            Where-Object { $_.Name -match '^\d{4}-.+\.md$' }).Count
        if ($count -gt 0) { "STORE|$($dir.Name)|$count" }
    }
    $url = Get-GitRemoteUrl
    if ($null -eq $url) {
        'REMOTE|none|-'
    }
    else {
        $parsed = Get-RemoteParse -Url $url
        $hostName = ''
        if ($parsed.ContainsKey('host')) { $hostName = $parsed['host'] }
        "REMOTE|$hostName|$url"
        if ($parsed.ContainsKey('repo')) { "PARSE|repo|$($parsed['repo'])|" }
        if ($parsed.ContainsKey('org')) { "PARSE|org|$($parsed['org'])|" }
        if ($parsed.ContainsKey('project')) { "PARSE|project|$($parsed['project'])|" }
    }
    exit 0
}

# --- -Apply: validate against the schema, then write ---------------------------
$errors = @()

if ([string]::IsNullOrWhiteSpace($Tracker)) {
    $errors += 'tracker is required (-Tracker local-markdown|github|azure-devops)'
}
elseif ($validTrackers -notcontains $Tracker) {
    $errors += "tracker '$Tracker' is not one of: $($validTrackers -join ', ')"
}

if ($Tracker -eq 'github') {
    if ([string]::IsNullOrWhiteSpace($Repo)) {
        $errors += 'github requires -Repo owner/name'
    }
    elseif ($Repo -notmatch '^[^/\s]+/[^/\s]+$') {
        $errors += "repo '$Repo' must look like owner/name"
    }
}
if ($Tracker -eq 'azure-devops') {
    if ([string]::IsNullOrWhiteSpace($Org)) { $errors += 'azure-devops requires -Org' }
    if ([string]::IsNullOrWhiteSpace($Project)) { $errors += 'azure-devops requires -Project' }
}

# GitHub tree fields (references/manifest-schema.md): github-only, additive to
# schema v1. The issueQuery reject list lives in query-composition-lib.ps1 -
# dot-sourced below, never reimplemented here.
if ($Tracker -eq 'github') {
    if ($PSBoundParameters.ContainsKey('TreeSource')) {
        if ($validTreeSources -notcontains $TreeSource) {
            $errors += "treeSource '$TreeSource' is not one of: $($validTreeSources -join ', ')"
        }
        if ($NoTree) {
            $errors += 'pass either -NoTree or -TreeSource, not both'
        }
    }
    foreach ($name in @('TreeMaxIssues', 'TreeLookbackDays', 'TreeFreshnessHours')) {
        if ($PSBoundParameters.ContainsKey($name) -and (Get-Variable -Name $name -ValueOnly) -le 0) {
            $errors += "$($githubParams[$name]) must be a positive integer"
        }
    }
    if ($PSBoundParameters.ContainsKey('IssueQuery')) {
        $libPath = Join-Path -Path $PSScriptRoot -ChildPath 'query-composition-lib.ps1'
        if (-not (Test-Path -LiteralPath $libPath)) {
            $errors += "issueQuery validation library not found: $libPath"
        }
        else {
            . $libPath
            $queryCheck = Test-GithubIssueQuery -Query $IssueQuery
            if (-not $queryCheck.IsValid) {
                foreach ($queryError in $queryCheck.Errors) { $errors += $queryError }
            }
        }
    }
}
elseif (-not [string]::IsNullOrWhiteSpace($Tracker)) {
    foreach ($name in $githubParams.Keys) {
        if ($PSBoundParameters.ContainsKey($name)) {
            $errors += "$($githubParams[$name]) only applies to tracker github"
        }
    }
}

if ($Tracker -ne 'local-markdown' -and -not [string]::IsNullOrWhiteSpace($Tracker)) {
    foreach ($key in $storeKeys) {
        $value = Get-Variable -Name $key -ValueOnly -ErrorAction SilentlyContinue
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $errors += "$key only applies to tracker local-markdown"
        }
    }
    if ($PSBoundParameters.ContainsKey('IssueTemplateOverride')) {
        $errors += 'issueTemplateOverrides only applies to tracker local-markdown'
    }
}
if ($Tracker -eq 'azure-devops' -and $PSBoundParameters.ContainsKey('IssueTypes')) {
    # Azure Boards has no issue-type field; only the GitHub-shaped trackers do.
    $errors += 'issueTypes only applies to tracker local-markdown or github'
}
if ($Tracker -eq 'azure-devops' -and $PSBoundParameters.ContainsKey('TreeFile')) {
    $errors += 'treeFile only applies to tracker local-markdown or github'
}
foreach ($key in $repoRelativeKeys) {
    $value = Get-Variable -Name $key -ValueOnly -ErrorAction SilentlyContinue
    if (-not [string]::IsNullOrWhiteSpace($value) -and -not (Test-RepoRelative -Value $value)) {
        $errors += "$key '$value' must be repo-relative (no root, no ..)"
    }
}

# --- Template registry (references/issue-templates.md) -----------------------
# Parse the CLI entries, then merge them over the registration persisted in an
# existing manifest: a -Force rewrite carries the registry over and new
# entries overwrite per type (removal stays a direct manifest edit). Every
# entry must resolve - the registered file has to exist and its template has
# to declare the registered type - so a manifest never carries a dead
# registration.
$registry = [ordered]@{}
$carriedTemplatesDir = $null
$carriedIssueTypes = $null
if ($Tracker -ne 'azure-devops' -and -not [string]::IsNullOrWhiteSpace($Tracker)) {
    $existingManifest = $null
    if ((Test-Path -LiteralPath $manifestRel) -and $Force) {
        try {
            $existingManifest = Get-Content -LiteralPath $manifestRel -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch {
            $errors += "$manifestRel is not valid JSON - fix or delete it, then re-run"
        }
    }
    if ($null -ne $existingManifest) {
        $existingNames = @($existingManifest.PSObject.Properties.Name)
        if ($existingNames -contains 'issueTemplatesDir' -and
            -not [string]::IsNullOrWhiteSpace([string]$existingManifest.issueTemplatesDir)) {
            $carriedTemplatesDir = [string]$existingManifest.issueTemplatesDir
        }
        if ($existingNames -contains 'issueTypes') {
            $carriedIssueTypes = @($existingManifest.issueTypes)
        }
        if ($existingNames -contains 'issueTemplateOverrides') {
            foreach ($prop in $existingManifest.issueTemplateOverrides.PSObject.Properties) {
                $registry[[string]$prop.Name] = [string]$prop.Value
            }
        }
    }
    # Taxonomy: -IssueTypes replaces the shipped defaults wholesale; otherwise a
    # -Force rewrite carries the persisted list over (critique A5: never strip).
    $taxonomyValues = $carriedIssueTypes
    if ($PSBoundParameters.ContainsKey('IssueTypes')) { $taxonomyValues = @($IssueTypes) }
    $taxonomy = Get-IssueTypeTaxonomy -Overrides $taxonomyValues
    foreach ($taxonomyError in $taxonomy.Errors) { $errors += $taxonomyError }
    $effectiveTypes = @($taxonomy.Types)
}

if ($Tracker -eq 'local-markdown') {
    if ($PSBoundParameters.ContainsKey('IssueTemplateOverride')) {
        $entryOverrides = @{}
        foreach ($entry in $IssueTemplateOverride) {
            $parts = $entry -split '=', 2
            if ($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[0]) -or [string]::IsNullOrWhiteSpace($parts[1])) {
                $errors += "issueTemplateOverride '$entry' must look like <type>=<file.md>"
                continue
            }
            $entryType = $parts[0].Trim()
            $entryFile = $parts[1].Trim()
            if ($effectiveTypes -notcontains $entryType) {
                $errors += "issueTemplateOverride type '$entryType' is not one of the configured types: $($effectiveTypes -join ', ')"
                continue
            }
            if ($entryFile -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*\.md$') {
                $errors += "issueTemplateOverride file '$entryFile' must be a plain .md filename (no path separators)"
                continue
            }
            if ($entryOverrides.ContainsKey($entryType)) {
                $errors += "issueTemplateOverride type '$entryType' is registered twice"
                continue
            }
            $entryOverrides[$entryType] = $entryFile
        }
        foreach ($entryType in $entryOverrides.Keys) {
            $registry[$entryType] = $entryOverrides[$entryType]
        }
    }

    $effectiveTemplatesDir = '.github/ISSUE_TEMPLATE'
    if (-not [string]::IsNullOrWhiteSpace($IssueTemplatesDir)) {
        $effectiveTemplatesDir = $IssueTemplatesDir
    }
    elseif ($null -ne $carriedTemplatesDir) {
        $effectiveTemplatesDir = $carriedTemplatesDir
    }
    $templatesLabel = $effectiveTemplatesDir -replace '\\', '/'
    if (-not (Test-RepoRelative -Value $effectiveTemplatesDir)) {
        $errors += "issueTemplatesDir '$effectiveTemplatesDir' must be repo-relative (no root, no ..)"
    }
    else {
        foreach ($entryType in @($registry.Keys)) {
            if ($effectiveTypes -notcontains $entryType) {
                $errors += "issueTemplateOverrides registers unknown type '$entryType' (configured types: $($effectiveTypes -join ', '))"
                continue
            }
            $entryFile = $registry[$entryType]
            if ($entryFile -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*\.md$') {
                $errors += "issueTemplateOverrides entry for '$entryType' is not a plain .md filename: '$entryFile'"
                continue
            }
            $entryPath = Join-Path -Path $effectiveTemplatesDir -ChildPath $entryFile
            $entryLabel = "${templatesLabel}/$entryFile"
            if (-not (Test-Path -LiteralPath $entryPath)) {
                $errors += "$entryLabel`: registered template not found (issueTemplateOverrides points at it)"
                continue
            }
            $parsed = ConvertTo-IssueTemplate -Path $entryPath -Label $entryLabel -ValidTypes $effectiveTypes
            foreach ($err in $parsed.Errors) { $errors += $err }
            if ($null -ne $parsed.Template -and $parsed.Template.Type -ne $entryType) {
                $errors += "$entryLabel`: template declares type '$($parsed.Template.Type)' but is registered for '$entryType'"
            }
        }
    }
}

if ((Test-Path -LiteralPath $manifestRel) -and -not $Force) {
    $errors += "$manifestRel already exists - re-run with -Force to replace it"
}

if ($errors.Count -gt 0) {
    foreach ($e in $errors) { "issue-tracker-init: $e" }
    exit 1
}

# Canonical key order and defaults (references/manifest-schema.md).
$jsonPairs = New-Object System.Collections.Generic.List[string]
function Add-JsonPair {
    param([string]$Key, $Value, [bool]$AsNumber = $false, [bool]$AsBool = $false)
    if ($AsNumber) {
        $script:jsonPairs.Add(('  "{0}": {1}' -f $Key, $Value))
    }
    elseif ($AsBool) {
        $script:jsonPairs.Add(('  "{0}": {1}' -f $Key, $(if ($Value) { 'true' } else { 'false' })))
    }
    else {
        $escaped = ([string]$Value).Replace('\', '\\').Replace('"', '\"')
        $script:jsonPairs.Add(('  "{0}": "{1}"' -f $Key, $escaped))
    }
}

function Add-JsonObjectPair {
    # JSON object value (used for issueTemplateOverrides); keys sorted for a
    # deterministic, byte-stable manifest.
    param([string]$Key, $Map)
    $innerNl = [Environment]::NewLine
    $pairs = foreach ($mapKey in @($Map.Keys | Sort-Object)) {
        $escapedKey = ([string]$mapKey).Replace('\', '\\').Replace('"', '\"')
        $escapedValue = ([string]$Map[$mapKey]).Replace('\', '\\').Replace('"', '\"')
        '    "{0}": "{1}"' -f $escapedKey, $escapedValue
    }
    $script:jsonPairs.Add(('  "{0}": {{{1}{2}{1}  }}' -f $Key, $innerNl, ($pairs -join (',' + $innerNl))))
}

function Add-JsonStringArrayPair {
    # JSON string-array value (used for issueTypes); one entry per line for a
    # deterministic, byte-stable manifest.
    param([string]$Key, [string[]]$Values)
    $innerNl = [Environment]::NewLine
    $entries = foreach ($value in @($Values)) {
        $escaped = ([string]$value).Replace('\', '\\').Replace('"', '\"')
        '    "{0}"' -f $escaped
    }
    $script:jsonPairs.Add(('  "{0}": [{1}{2}{1}  ]' -f $Key, $innerNl, ($entries -join (',' + $innerNl))))
}

Add-JsonPair -Key 'schemaVersion' -Value 1 -AsNumber $true
Add-JsonPair -Key 'tracker' -Value $Tracker

# Taxonomy (references/manifest-schema.md): written only when it departs from
# the shipped defaults, so a default-taxonomy repo keeps a minimal manifest.
# `issueTypes` describes the vocabulary, not the file store, so it applies to
# every GitHub-shaped tracker; Azure Boards has no issue-type field.
if ($Tracker -ne 'azure-devops' -and $null -ne $effectiveTypes -and $effectiveTypes.Count -gt 0) {
    $taxonomyIsDefault = ($effectiveTypes.Count -eq $issueDefaultTypes.Count)
    if ($taxonomyIsDefault) {
        foreach ($builtIn in $issueDefaultTypes) {
            if ($effectiveTypes -notcontains $builtIn) { $taxonomyIsDefault = $false; break }
        }
    }
    if (-not $taxonomyIsDefault) {
        Add-JsonStringArrayPair -Key 'issueTypes' -Values $effectiveTypes
    }
}

if ($Tracker -eq 'local-markdown') {
    if ([string]::IsNullOrWhiteSpace($IssuesDir)) { $IssuesDir = '.issues' }
    if ([string]::IsNullOrWhiteSpace($ArchiveDir)) { $ArchiveDir = "$IssuesDir/archived" }
    if ([string]::IsNullOrWhiteSpace($TreeFile)) { $TreeFile = "$IssuesDir/tree.md" }
    Add-JsonPair -Key 'issuesDir' -Value ($IssuesDir -replace '\\', '/')
    Add-JsonPair -Key 'archiveDir' -Value ($ArchiveDir -replace '\\', '/')
    Add-JsonPair -Key 'treeFile' -Value ($TreeFile -replace '\\', '/')
    # Template registry: dir whenever supplied, carried over, or implied by an
    # override; the overrides object whenever anything is registered.
    if (-not [string]::IsNullOrWhiteSpace($IssueTemplatesDir) -or
        $null -ne $carriedTemplatesDir -or
        $registry.Count -gt 0) {
        Add-JsonPair -Key 'issueTemplatesDir' -Value ($effectiveTemplatesDir -replace '\\', '/')
    }
    if ($registry.Count -gt 0) {
        Add-JsonObjectPair -Key 'issueTemplateOverrides' -Map $registry
    }
}

if ($Tracker -eq 'github') {
    # Sketch 1.1: treeSource defaults to github (-NoTree opts out); treeFile is
    # optional for github and written only when supplied.
    if (-not $NoTree) {
        $treeSourceValue = 'github'
        if ($PSBoundParameters.ContainsKey('TreeSource')) { $treeSourceValue = $TreeSource.ToLowerInvariant() }
        Add-JsonPair -Key 'treeSource' -Value $treeSourceValue
    }
    if (-not [string]::IsNullOrWhiteSpace($TreeFile)) {
        Add-JsonPair -Key 'treeFile' -Value ($TreeFile -replace '\\', '/')
    }
}

if (-not [string]::IsNullOrWhiteSpace($TreeScript)) {
    Add-JsonPair -Key 'treeScript' -Value ($TreeScript -replace '\\', '/')
}
elseif (Test-Path -LiteralPath ($defaultTreeScript -replace '^~', $HOME)) {
    Add-JsonPair -Key 'treeScript' -Value $defaultTreeScript
}

if (-not [string]::IsNullOrWhiteSpace($LintTask)) {
    Add-JsonPair -Key 'lintTask' -Value $LintTask
}

if ($Tracker -eq 'github') {
    # Limits always carry their schema defaults; optional knobs only when given.
    # The writer must know every key so -Force cannot strip them (critique A5).
    # Accumulators must not share a name with the params (PS names are
    # case-insensitive - $treeMaxIssues would clobber $TreeMaxIssues).
    $treeMaxIssuesValue = 300
    if ($PSBoundParameters.ContainsKey('TreeMaxIssues')) { $treeMaxIssuesValue = $TreeMaxIssues }
    $treeLookbackDaysValue = 365
    if ($PSBoundParameters.ContainsKey('TreeLookbackDays')) { $treeLookbackDaysValue = $TreeLookbackDays }
    Add-JsonPair -Key 'treeMaxIssues' -Value $treeMaxIssuesValue -AsNumber $true
    Add-JsonPair -Key 'treeLookbackDays' -Value $treeLookbackDaysValue -AsNumber $true
    Add-JsonPair -Key 'treeIncludeClosed' -Value $TreeIncludeClosed -AsBool $true
    if (-not [string]::IsNullOrWhiteSpace($TreeMinPriority)) {
        Add-JsonPair -Key 'treeMinPriority' -Value $TreeMinPriority
    }
    if ($PSBoundParameters.ContainsKey('TreeFreshnessHours')) {
        Add-JsonPair -Key 'treeFreshnessHours' -Value $TreeFreshnessHours -AsNumber $true
    }
    if ($PSBoundParameters.ContainsKey('IssueQuery')) {
        Add-JsonPair -Key 'issueQuery' -Value $IssueQuery
    }
}

if ($Tracker -eq 'github') {
    Add-JsonPair -Key 'repo' -Value $Repo
}
elseif ($Tracker -eq 'azure-devops') {
    Add-JsonPair -Key 'org' -Value $Org
    Add-JsonPair -Key 'project' -Value $Project
}

$remoteUrl = Get-GitRemoteUrl
if ($null -ne $remoteUrl) {
    $remoteHost = Get-TrackerHostHint -HostName (Get-RemoteParse -Url $remoteUrl)['host']
    if ($null -ne $remoteHost) { Add-JsonPair -Key 'gitRemoteHost' -Value $remoteHost }
    Add-JsonPair -Key 'gitRemoteUrl' -Value $remoteUrl
}

$nl = [Environment]::NewLine
$json = '{' + $nl + ($jsonPairs -join (',' + $nl)) + $nl + '}' + $nl
$manifestFull = Join-Path -Path (Get-Location).Path -ChildPath $manifestRel
$manifestParent = Split-Path -Parent $manifestFull
if (-not (Test-Path -LiteralPath $manifestParent)) {
    New-Item -ItemType Directory -Path $manifestParent -Force | Out-Null
}
[System.IO.File]::WriteAllText($manifestFull, $json, [System.Text.UTF8Encoding]::new($false))

"issue-tracker-init: wrote $manifestRel (tracker=$Tracker$(if ($Tracker -eq 'local-markdown') { ", store=$IssuesDir" }))"
exit 0
