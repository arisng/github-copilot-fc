<#
.SYNOPSIS
    Lists, prints, or validates the issue templates (issue-tracking skill).

.DESCRIPTION
    Template-driven filing for the local markdown issue store. The effective
    template set is the skill default for every issue type (assets/issue-templates,
    GitHub-conventional markdown templates) replaced per type by consumer
    overrides registered in .github/issue-tracker.json (issueTemplatesDir +
    issueTemplateOverrides) - format: references/issue-templates.md.

    Modes (pass exactly one):
      -List         print one registry row per issue type:
                      TEMPLATE|<type>|<source>|<path>|<name>
                    (source = default | override; name is last and may
                    contain '|')
      -Show <type>  print the resolved template file verbatim - copy it to
                    NNNN-slug.md when filing a new issue (exit 1 when the
                    template is missing or invalid)
      -Validate     validate the whole effective set and the registration
                    (TEMPLATE errors, exit 1) - the standalone template gate

    Tracker guard: templates describe the local file store, so only
    tracker: local-markdown (or a missing manifest) runs; github and
    azure-devops are refused (issue-tracking skill, step 0).

    Run from the repo root (the store and manifest resolve from the current
    directory). The script ships inside the issue-tracking skill folder next
    to its SKILL.md: pwsh ~/.agents/skills/issue-tracking/scripts/issue-template.ps1

.EXAMPLE
    pwsh ~/.agents/skills/issue-tracking/scripts/issue-template.ps1 -List
.EXAMPLE
    pwsh ~/.agents/skills/issue-tracking/scripts/issue-template.ps1 -Show bug
.EXAMPLE
    pwsh ~/.agents/skills/issue-tracking/scripts/issue-template.ps1 -Validate
#>
param(
    [switch]$List,
    [string]$Show,
    [switch]$Validate
)

$ErrorActionPreference = 'Stop'
. (Join-Path -Path $PSScriptRoot -ChildPath 'issue-template-lib.ps1')

$modeCount = @($List, $Validate).Where({ $_ }).Count
if ($PSBoundParameters.ContainsKey('Show') -and -not [string]::IsNullOrWhiteSpace($Show)) { $modeCount++ }
if ($modeCount -ne 1) {
    "issue-template: pass exactly one of -List, -Show <type>, -Validate"
    exit 1
}

# --- Manifest: tracker guard + registry (references/manifest-schema.md) ------
$manifestPath = Join-Path -Path '.github' -ChildPath 'issue-tracker.json'
$tracker = 'local-markdown'
$templatesDir = '.github/ISSUE_TEMPLATE'
$templatesLabel = '.github/ISSUE_TEMPLATE'
$overrides = $null
if (Test-Path -LiteralPath $manifestPath) {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $names = @($manifest.PSObject.Properties.Name)
    if ($names -contains 'tracker' -and
        -not [string]::IsNullOrWhiteSpace([string]$manifest.tracker)) {
        $tracker = [string]$manifest.tracker
    }
    if ($tracker -ne 'local-markdown') {
        "issue-template: tracker '$tracker' is not local-markdown - issue templates describe the local file store (issue-tracking skill, step 0)"
        exit 1
    }
    if ($names -contains 'issueTemplatesDir' -and
        -not [string]::IsNullOrWhiteSpace([string]$manifest.issueTemplatesDir)) {
        $templatesDir = [string]$manifest.issueTemplatesDir
        $templatesLabel = $templatesDir -replace '\\', '/'
        if (-not (Test-IssueRepoRelativePath -Value $templatesDir)) {
            "TEMPLATE   ${templatesLabel}: issueTemplatesDir must be repo-relative (no root, no ..)"
            "issue-template: FAILED - fix the TEMPLATE errors above, then re-run"
            exit 1
        }
    }
    if ($names -contains 'issueTemplateOverrides') {
        $overrides = $manifest.issueTemplateOverrides
    }
}

$defaultsDir = Join-Path -Path $PSScriptRoot -ChildPath '..\assets\issue-templates'
$set = Get-IssueTemplateSet -DefaultsDir $defaultsDir -TemplatesDir $templatesDir `
    -TemplatesLabel $templatesLabel -Overrides $overrides

# --- -Validate: the whole effective set + registration -----------------------
if ($Validate) {
    if ($set.Errors.Count -gt 0) {
        foreach ($err in $set.Errors) { "TEMPLATE   $err" }
        "issue-template: FAILED - fix the TEMPLATE errors above, then re-run"
        exit 1
    }
    $overrideCount = 0
    if ($null -ne $overrides) { $overrideCount = @($overrides.PSObject.Properties).Count }
    "issue-template: OK ($($set.Templates.Count) templates, $overrideCount override(s))"
    exit 0
}

# --- -List: the resolved registry -------------------------------------------
if ($List) {
    foreach ($typeName in $issueValidType) {
        $template = $set.Templates[$typeName]
        if ($null -eq $template) { continue }
        $source = 'default'
        $path = "skill assets/issue-templates/$typeName.md"
        if ($null -ne $overrides -and $null -ne $overrides.PSObject.Properties[$typeName]) {
            $source = 'override'
            $path = "$templatesLabel/$($overrides.PSObject.Properties[$typeName].Value)"
        }
        "TEMPLATE|$typeName|$source|$path|$($template.Name)"
    }
    if ($set.Errors.Count -gt 0) {
        foreach ($err in $set.Errors) { "TEMPLATE   $err" }
        "issue-template: FAILED - fix the TEMPLATE errors above, then re-run"
        exit 1
    }
    exit 0
}

# --- -Show <type>: the filing skeleton ---------------------------------------
if ($issueValidType -notcontains $Show) {
    "issue-template: unknown issue type '$Show' (expected one of: $($issueValidType -join ', '))"
    exit 1
}
if (-not $set.Templates.ContainsKey($Show)) {
    foreach ($err in $set.Errors) { "TEMPLATE   $err" }
    "issue-template: no usable template for type '$Show' - fix the TEMPLATE errors above"
    exit 1
}
Get-Content -LiteralPath $set.Templates[$Show].Path -Encoding UTF8 | ForEach-Object { $_ }
exit 0
