<#
.SYNOPSIS
    Bumps the tree-template version after every edit to assets/tree-template.html.

.DESCRIPTION
    The generated view (.issues/tree.html) embeds the template version so
    consumer repos can detect version drift and patch by re-rendering. Any edit
    to assets/tree-template.html must therefore bump the version recorded in
    assets/tree-template.version.json; this script re-fingerprints the template
    and writes the new version + sha256 in one step.

    Guardrails:
      - refuses a non-MAJOR.MINOR.PATCH version;
      - refuses downgrades and same-core changes unless -Force;
      - refuses a template that has no __TREE_TEMPLATE_VERSION__ placeholder
        (the version would never reach the generated page).

    render-issue-tree.ps1 verifies the fingerprint before hydrating, so a
    template edited without a bump fails every render and -Check until this
    script is run from the skill repo.

.EXAMPLE
    pwsh ~/.agents/skills/issue-tracking/scripts/bump-tree-template-version.ps1 -Version 1.1.0
.EXAMPLE
    pwsh ~/.agents/skills/issue-tracking/scripts/bump-tree-template-version.ps1 -Version 2.0.0 -Force
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Version,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath 'template-version-lib.ps1')

$templatePath = Join-Path -Path $PSScriptRoot -ChildPath '..\assets\tree-template.html'
$versionPath = Join-Path -Path $PSScriptRoot -ChildPath '..\assets\tree-template.version.json'

if (-not (Test-TreeTemplateVersionFormat -Version $Version)) {
    "bump-tree-template: '$Version' is not a MAJOR.MINOR.PATCH version (optional -suffix allowed)"
    exit 1
}
if (-not (Test-Path -LiteralPath $templatePath)) {
    "bump-tree-template: template not found at $templatePath (skill assets must ship with the script)"
    exit 1
}

$template = [System.IO.File]::ReadAllText($templatePath)
$placeholderCount = ([regex]::Matches($template, '__TREE_TEMPLATE_VERSION__')).Count
if ($placeholderCount -eq 0) {
    "bump-tree-template: assets/tree-template.html has no __TREE_TEMPLATE_VERSION__ placeholder - add one (head meta + footer) so the version reaches the generated tree.html"
    exit 1
}

$state = Get-TreeTemplateVersionState -Path $versionPath
$current = $state.Version
if ($state.Error -and (Test-Path -LiteralPath $versionPath)) {
    "bump-tree-template: existing version file has issues - $($state.Error) (rewriting)"
}

if ($null -ne $current) {
    if ($Version -eq $current) {
        "bump-tree-template: already at v$current - nothing to do"
        exit 1
    }
    if (-not $Force) {
        $curCore = [version](($current -split '[-+]')[0])
        $newCore = [version](($Version -split '[-+]')[0])
        if ($newCore -lt $curCore) {
            "bump-tree-template: refusing downgrade v$current -> v$Version (drift detection relies on monotonic versions; use -Force to override)"
            exit 1
        }
        if ($newCore -eq $curCore) {
            "bump-tree-template: core version unchanged (v$current -> v$Version) - bump MAJOR, MINOR or PATCH, or use -Force"
            exit 1
        }
    }
}

$sha256 = Get-TreeTemplateSha256 -Path $templatePath
$json = '{' + "`n" +
    '  "version": "' + $Version + '",' + "`n" +
    '  "sha256": "' + $sha256 + '"' + "`n" +
    '}' + "`n"
[System.IO.File]::WriteAllText($versionPath, $json, [System.Text.UTF8Encoding]::new($false))

if ($null -eq $current) {
    "bump-tree-template: recorded v$Version (sha256 $sha256, $placeholderCount placeholder(s))"
}
else {
    "bump-tree-template: v$current -> v$Version (sha256 $sha256, $placeholderCount placeholder(s))"
}
"bump-tree-template: re-render generated tree.html files to embed the new version (render-issue-tree.ps1)"
exit 0
