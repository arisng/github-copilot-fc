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
               manifest unless -Force is given.

    Schema ownership and the bootstrap flow (interactive vs autopilot inference)
    live in this skill's SKILL.md step 0 and references/manifest-schema.md.

.EXAMPLE
    pwsh ~/.agents/skills/issue-tracking/scripts/issue-tracker-init.ps1 -Probe
.EXAMPLE
    pwsh ~/.agents/skills/issue-tracking/scripts/issue-tracker-init.ps1 -Apply -Tracker local-markdown
.EXAMPLE
    pwsh ~/.agents/skills/issue-tracking/scripts/issue-tracker-init.ps1 -Apply -Tracker github -Repo owner/name -Force
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
    [string]$Repo,
    [string]$Org,
    [string]$Project,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$validTrackers = @('local-markdown', 'github', 'azure-devops')
$manifestRel = '.github/issue-tracker.json'
$defaultTreeScript = '~/.agents/skills/issue-tracking/scripts/issue-tree.ps1'
$storeKeys = @('issuesDir', 'archiveDir', 'treeFile')

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
    param([string]$Value)
    if ([System.IO.Path]::IsPathRooted($Value)) { return $false }
    foreach ($seg in ($Value -split '[\\/]')) {
        if ($seg -eq '..') { return $false }
    }
    return $true
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

if ($Tracker -ne 'local-markdown' -and -not [string]::IsNullOrWhiteSpace($Tracker)) {
    foreach ($key in $storeKeys) {
        $value = Get-Variable -Name $key -ValueOnly -ErrorAction SilentlyContinue
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $errors += "$key only applies to tracker local-markdown"
        }
    }
}
foreach ($key in $storeKeys) {
    $value = Get-Variable -Name $key -ValueOnly -ErrorAction SilentlyContinue
    if (-not [string]::IsNullOrWhiteSpace($value) -and -not (Test-RepoRelative -Value $value)) {
        $errors += "$key '$value' must be repo-relative (no root, no ..)"
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
    param([string]$Key, $Value, [bool]$AsNumber = $false)
    if ($AsNumber) {
        $script:jsonPairs.Add(('  "{0}": {1}' -f $Key, $Value))
    }
    else {
        $escaped = ([string]$Value).Replace('\', '\\').Replace('"', '\"')
        $script:jsonPairs.Add(('  "{0}": "{1}"' -f $Key, $escaped))
    }
}

Add-JsonPair -Key 'schemaVersion' -Value 1 -AsNumber $true
Add-JsonPair -Key 'tracker' -Value $Tracker

if ($Tracker -eq 'local-markdown') {
    if ([string]::IsNullOrWhiteSpace($IssuesDir)) { $IssuesDir = '.issues' }
    if ([string]::IsNullOrWhiteSpace($ArchiveDir)) { $ArchiveDir = "$IssuesDir/archived" }
    if ([string]::IsNullOrWhiteSpace($TreeFile)) { $TreeFile = "$IssuesDir/tree.md" }
    Add-JsonPair -Key 'issuesDir' -Value ($IssuesDir -replace '\\', '/')
    Add-JsonPair -Key 'archiveDir' -Value ($ArchiveDir -replace '\\', '/')
    Add-JsonPair -Key 'treeFile' -Value ($TreeFile -replace '\\', '/')
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
