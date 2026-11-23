# Shared issue-template model for the issue-tracking skill.
# Format: references/issue-templates.md (GitHub-conventional markdown
# templates: YAML frontmatter + markdown body skeleton).
#
# Single source of truth for:
#   - the store frontmatter contract (core fields, link fields, enums);
#   - the template vocabulary and template self-validation;
#   - registry resolution (skill defaults + consumer overrides registered in
#     .github/issue-tracker.json via issueTemplatesDir/issueTemplateOverrides);
#   - per-issue template conformance (fields + required body sections).
#
# Dot-sourced by issue-tree.ps1 (enforcement), issue-template.ps1 (CLI) and
# issue-tracker-init.ps1 (registration validation). Callers pass paths and
# display labels; this library never resolves locations on its own.

# --- Store contract (template-independent; the tree grammar depends on it) ---
$issueValidStatus = @('open', 'in-progress', 'blocked', 'done', 'dropped')
$issueValidPriority = @('P0', 'P1', 'P2', 'P3')

# --- Taxonomy: `type` is classification, grouping is a LABEL ------------------
# `type` mirrors GitHub's native issue type (a single-select field that is NOT a
# label): one value per issue, drawn from an owner-scoped vocabulary. The skill
# ships GitHub's own defaults and lets a consumer repo replace them through the
# manifest key `issueTypes` (references/manifest-schema.md).
#
# Grouping is deliberately NOT a type: GitHub models it as a label, and so does
# this skill. A theme root carries the `theme` label (or `theme:<slug>`); the
# relation to it stays the `theme:`/`parent:` frontmatter link. `theme`, `epic`
# and `chore` remain available as EXTENSION types - a repo opts in by listing
# them in `issueTypes`, which also makes their shipped templates resolvable.
$issueDefaultTypes = @('task', 'bug', 'feature')
$issueExtensionTypes = @('theme', 'epic', 'chore')
# `theme` was a type before grouping moved to the label axis. Its frontmatter
# value stays accepted forever so a migrated store never has to rewrite a file;
# a normalizing pass is `labels: [theme]`. It is NOT part of the taxonomy: the
# type describes classification, and grouping is a label.
$issueLegacyTypes = @('theme')
$issueTaxonomyMaxTypes = 25   # GitHub's per-owner issue-type ceiling
$issueThemeLabel = 'theme'
# Kept for callers that only need the defaults (issue-template.ps1 -List/Show).
$issueValidType = $issueDefaultTypes

# Core frontmatter fields every issue must carry. Link fields are the tree
# relations every issue may carry. `labels` mirrors GitHub's label set and is
# where grouping lives; it is optional (an unlabelled issue simply has none).
# Templates extend this per type via their requiredFields/optionalFields lists -
# never by replacing the core.
$issueCoreFields = @('id', 'title', 'status', 'priority', 'type', 'created', 'labels')
$issueLinkFields = @('theme', 'parent', 'order')

# --- Template frontmatter vocabulary (references/issue-templates.md) ---------
# GitHub-conventional metadata keys (name/about/title/labels/assignees),
# stamping keys written into new issues, and the field-extension lists.
$issueTemplateMetaKeys = @('name', 'about', 'description', 'title', 'labels', 'assignees')
$issueTemplateStampKeys = @('type', 'status', 'priority')
$issueTemplateFieldKeys = @('requiredFields', 'optionalFields')
$issueTemplateKeys = @($issueTemplateMetaKeys) + @($issueTemplateStampKeys) + @($issueTemplateFieldKeys)

function Test-IssueRepoRelativePath {
    # Repo-relative only: no rooted paths, no '..' segments (same rule the
    # manifest writer enforces for issuesDir/archiveDir/treeFile).
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    if ([System.IO.Path]::IsPathRooted($Value)) { return $false }
    foreach ($seg in ($Value -split '[\\/]')) {
        if ($seg -eq '..') { return $false }
    }
    return $true
}

function Get-IssueTypeTaxonomy {
    # Resolves the effective `type` taxonomy: the skill defaults, replaced
    # wholesale by the manifest's `issueTypes` array when present. Returns
    # @{ Types = string[]; IsDefault = bool; Errors = string[] }.
    # Validation mirrors GitHub's real constraints (kebab-ish names, unique,
    # at most 25) so a manifest cannot declare a taxonomy GitHub would reject.
    param(
        $Overrides,
        [string]$Label = 'issueTypes'
    )
    $errors = @()
    if ($null -eq $Overrides) {
        return @{ Types = @($issueDefaultTypes); IsDefault = $true; Errors = @() }
    }
    $values = @()
    if ($Overrides -is [string]) {
        $values = @(ConvertTo-StringList -Value $Overrides)
    }
    else {
        foreach ($entry in @($Overrides)) {
            if ($null -eq $entry) { continue }
            # A shell may hand the whole list over as one comma-separated
            # string even for an array parameter (pwsh -File does).
            foreach ($part in (ConvertTo-StringList -Value ([string]$entry))) { $values += $part }
        }
    }
    if ($values.Count -eq 0) {
        $errors += "$Label must list at least one type (omit the key to keep the defaults: $($issueDefaultTypes -join ', '))"
        return @{ Types = @(); IsDefault = $false; Errors = $errors }
    }
    if ($values.Count -gt $issueTaxonomyMaxTypes) {
        $errors += "$Label lists $($values.Count) types - GitHub allows at most $issueTaxonomyMaxTypes per owner"
    }
    $seen = @{}
    $clean = @()
    foreach ($raw in $values) {
        $name = ([string]$raw).Trim().ToLowerInvariant()
        if ($name -eq '') {
            $errors += "$Label contains an empty type name"
            continue
        }
        if ($name -notmatch '^[a-z0-9][a-z0-9-]{0,31}$') {
            $errors += "$Label entry '$raw' is not a kebab-case type name (a-z, 0-9, '-', max 32 chars)"
            continue
        }
        if ($seen.ContainsKey($name)) {
            $errors += "$Label lists '$name' twice"
            continue
        }
        $seen[$name] = $true
        $clean += $name
    }
    return @{ Types = $clean; IsDefault = $false; Errors = $errors }
}

function Test-IssueThemeMarker {
    # Grouping lives on the label axis. A record is a theme root when its labels
    # carry the bare `theme` marker (canonical) or a `theme:<slug>` family value.
    # `type: theme` is accepted as a legacy alias so stores migrated from the
    # old taxonomy keep working once they opt into the extension type.
    param(
        [string]$Type,
        [string[]]$Labels
    )
    foreach ($label in @($Labels)) {
        if ([string]::IsNullOrWhiteSpace($label)) { continue }
        $name = ([string]$label).Trim()
        if ($name -ieq $issueThemeLabel) { return $true }
        if ($name -like "$issueThemeLabel`:*") { return $true }
    }
    return ($Type -eq 'theme')
}

function Get-IssueTemplateDefaultPath {
    # Shipped template for a type: defaults at assets/issue-templates/<type>.md,
    # extension types one level down at assets/issue-templates/extensions/.
    # Returns $null for a type the skill ships no template for (the repo must
    # register an override).
    param(
        [string]$DefaultsDir,
        [string]$Type
    )
    if ($issueDefaultTypes -contains $Type) {
        return (Join-Path -Path $DefaultsDir -ChildPath "$Type.md")
    }
    if ($issueExtensionTypes -contains $Type) {
        return (Join-Path -Path $DefaultsDir -ChildPath "extensions/$Type.md")
    }
    return $null
}

function Read-IssueDocument {
    # Parses one markdown issue or template file: YAML-style frontmatter
    # (--- delimited, scalar 'key: value' lines) plus the body. Level-2 body
    # headings ('## Text') are the section names templates enforce; fenced
    # code blocks are skipped so an example heading never counts.
    # Returns @{ Frontmatter = hashtable or $null; Headings = string[]; Error = string or $null }.
    param([string]$Path)
    $result = [pscustomobject]@{
        Frontmatter = $null
        Headings    = @()
        Error       = $null
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        $result.Error = 'file not found'
        return $result
    }
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    if ($lines.Count -lt 3 -or $lines[0].Trim() -ne '---') {
        $result.Error = 'missing or malformed YAML frontmatter'
        return $result
    }
    $fm = @{}
    $closed = $false
    $bodyStart = 0
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line.Trim() -eq '---') {
            $closed = $true
            $bodyStart = $i + 1
            break
        }
        if ($line -match '^([A-Za-z_][A-Za-z0-9_]*):[ \t]*(.*)$') {
            $key = $Matches[1]
            $value = $Matches[2].Trim()
            # Strip inline comments the way the README format example shows
            # them (never for title: - a title may legitimately contain ' #').
            if ($key -ne 'title' -and $value -match ' #') {
                $value = ($value -split ' #', 2)[0].Trim()
            }
            if ($value.Length -ge 2 -and
                ($value[0] -eq '"' -or $value[0] -eq "'") -and
                $value[$value.Length - 1] -eq $value[0]) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $fm[$key] = $value
        }
    }
    if (-not $closed) {
        $result.Error = 'missing or malformed YAML frontmatter'
        return $result
    }
    $result.Frontmatter = $fm
    $headings = New-Object System.Collections.Generic.List[string]
    $inFence = $false
    foreach ($line in ($lines | Select-Object -Skip $bodyStart)) {
        if ($line -match '^\s*```') {
            $inFence = -not $inFence
            continue
        }
        if ($inFence) { continue }
        if ($line -match '^##[ \t]+(.+?)[ \t]*$') {
            $headings.Add($Matches[1])
        }
    }
    $result.Headings = $headings.ToArray()
    return $result
}

function ConvertTo-StringList {
    # 'a, b' or '[a, "b"]' or '' -> string[] (template list fields).
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
    $raw = $Value.Trim()
    if ($raw.StartsWith('[') -and $raw.EndsWith(']')) {
        $raw = $raw.Substring(1, $raw.Length - 2).Trim()
    }
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    $items = New-Object System.Collections.Generic.List[string]
    foreach ($part in ($raw -split ',')) {
        $item = $part.Trim()
        if ($item.Length -ge 2 -and
            ($item[0] -eq '"' -or $item[0] -eq "'") -and
            $item[$item.Length - 1] -eq $item[0]) {
            $item = $item.Substring(1, $item.Length - 2)
        }
        if (-not [string]::IsNullOrWhiteSpace($item)) { $items.Add($item) }
    }
    return $items.ToArray()
}

function ConvertTo-IssueTemplate {
    # Parses and validates one template file. Returns
    # @{ Template = pscustomobject or $null; Errors = string[] } where every
    # error is '<Label>: <reason>' (Label is the caller's display path).
    param(
        [string]$Path,
        [string]$Label,
        [string[]]$ValidTypes
    )
    $errors = @()
    if ($null -eq $ValidTypes -or $ValidTypes.Count -eq 0) { $ValidTypes = @($issueDefaultTypes) }
    $doc = Read-IssueDocument -Path $Path
    if ($null -ne $doc.Error) {
        return @{ Template = $null; Errors = @("$Label`: $($doc.Error)") }
    }
    $fm = $doc.Frontmatter

    foreach ($key in $fm.Keys) {
        if ($issueTemplateKeys -notcontains $key) {
            $errors += "$Label`: unknown template frontmatter field '$key'"
        }
    }

    $get = {
        param($Name)
        if ($fm.ContainsKey($Name) -and -not [string]::IsNullOrWhiteSpace($fm[$Name])) {
            return $fm[$Name]
        }
        return $null
    }
    $name = & $get 'name'
    $about = & $get 'about'
    if ($null -eq $about) { $about = & $get 'description' }
    $type = & $get 'type'
    $status = & $get 'status'
    $priority = & $get 'priority'

    if ($null -eq $name) { $errors += "$Label`: template frontmatter field 'name' is required" }
    if ($null -eq $about) { $errors += "$Label`: template frontmatter field 'about' is required" }
    if ($null -eq $type) {
        $errors += "$Label`: template frontmatter field 'type' is required"
    }
    elseif ($ValidTypes -notcontains $type) {
        $errors += "$Label`: template type '$type' is not one of the configured types: $($ValidTypes -join ', ')"
    }
    if ($null -ne $status -and $issueValidStatus -notcontains $status) {
        $errors += "$Label`: template status default '$status' is not one of: $($issueValidStatus -join ', ')"
    }
    if ($null -ne $priority -and $issueValidPriority -notcontains $priority) {
        $errors += "$Label`: template priority default '$priority' is not one of: $($issueValidPriority -join ', ')"
    }

    $requiredFields = @(ConvertTo-StringList -Value $(if ($fm.ContainsKey('requiredFields')) { $fm['requiredFields'] } else { '' }))
    $optionalFields = @(ConvertTo-StringList -Value $(if ($fm.ContainsKey('optionalFields')) { $fm['optionalFields'] } else { '' }))
    $declared = @{}
    foreach ($field in ($requiredFields + $optionalFields)) {
        if ($field -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            $errors += "$Label`: field declaration '$field' is not a frontmatter field name"
            continue
        }
        if ($declared.ContainsKey($field)) {
            $errors += "$Label`: field '$field' is declared twice"
            continue
        }
        if ($issueCoreFields -contains $field) {
            $errors += "$Label`: field '$field' is part of the core issue contract and cannot be redeclared"
            continue
        }
        if ($issueLinkFields -contains $field) {
            $errors += "$Label`: field '$field' is a reserved link field and cannot be redeclared"
            continue
        }
        $declared[$field] = $true
    }

    $sections = @($doc.Headings | Select-Object -Unique)
    if ($sections.Count -eq 0) {
        $errors += "$Label`: template body must declare at least one required section ('## ' heading)"
    }

    if ($errors.Count -gt 0) {
        return @{ Template = $null; Errors = $errors }
    }
    $template = [pscustomobject]@{
        Path           = $Path
        Label          = $Label
        Type           = $type
        Name           = $name
        About          = $about
        Title          = $(if ($fm.ContainsKey('title')) { $fm['title'] } else { '' })
        Labels         = @(ConvertTo-StringList -Value $(if ($fm.ContainsKey('labels')) { $fm['labels'] } else { '' }))
        Assignees      = @(ConvertTo-StringList -Value $(if ($fm.ContainsKey('assignees')) { $fm['assignees'] } else { '' }))
        Status         = $status
        Priority       = $priority
        RequiredFields = $requiredFields
        OptionalFields = $optionalFields
        Sections       = $sections
    }
    return @{ Template = $template; Errors = @() }
}

function Get-IssueTemplateSet {
    # Resolves the effective template set: one template per configured issue
    # type, replaced per type by a consumer override registered in the manifest
    # (issueTemplatesDir + issueTemplateOverrides). Broken defaults and broken
    # registrations fail closed.
    # Returns @{ Templates = hashtable type->template; Errors = string[] }.
    param(
        [string]$DefaultsDir,
        [string]$TemplatesDir,
        [string]$TemplatesLabel,
        $Overrides,
        [string[]]$ValidTypes
    )
    $templates = @{}
    $errors = @()
    if ($null -eq $ValidTypes -or $ValidTypes.Count -eq 0) { $ValidTypes = @($issueDefaultTypes) }
    if ([string]::IsNullOrWhiteSpace($TemplatesLabel)) { $TemplatesLabel = $TemplatesDir }

    $overrideMap = @{}
    if ($null -ne $Overrides) {
        if ($Overrides -is [System.Collections.IDictionary]) {
            foreach ($key in $Overrides.Keys) {
                $overrideMap[[string]$key] = [string]$Overrides[$key]
            }
        }
        else {
            foreach ($prop in $Overrides.PSObject.Properties) {
                $overrideMap[$prop.Name] = [string]$prop.Value
            }
        }
    }
    foreach ($typeName in $overrideMap.Keys) {
        if ($ValidTypes -notcontains $typeName) {
            $errors += "${TemplatesLabel}: issueTemplateOverrides registers unknown type '$typeName' (configured types: $($ValidTypes -join ', '))"
        }
    }

    foreach ($typeName in $ValidTypes) {
        $path = $null
        $label = $null
        if ($overrideMap.ContainsKey($typeName)) {
            $fileName = $overrideMap[$typeName]
            if ($fileName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*\.md$') {
                $errors += "${TemplatesLabel}: issueTemplateOverrides entry for '$typeName' is not a plain .md filename: '$fileName'"
                continue
            }
            if ([string]::IsNullOrWhiteSpace($TemplatesDir)) {
                $errors += "issueTemplateOverrides registers '$typeName' but issueTemplatesDir is empty"
                continue
            }
            $path = Join-Path -Path $TemplatesDir -ChildPath $fileName
            $label = "$TemplatesLabel/$fileName"
        }
        else {
            $path = Get-IssueTemplateDefaultPath -DefaultsDir $DefaultsDir -Type $typeName
            if ($null -eq $path) {
                $errors += "type '$typeName' ships no skill default template - register one in issueTemplateOverrides"
                continue
            }
            $isExtension = $issueExtensionTypes -contains $typeName
            $label = "skill assets/issue-templates/$(if ($isExtension) { 'extensions/' })$typeName.md"
        }
        if (-not (Test-Path -LiteralPath $path)) {
            if ($overrideMap.ContainsKey($typeName)) {
                $errors += "${label}: registered template not found (issueTemplateOverrides points at it)"
            }
            else {
                $errors += "${label}: skill default template not found (skill assets must ship with the scripts)"
            }
            continue
        }
        $parsed = ConvertTo-IssueTemplate -Path $path -Label $label -ValidTypes $ValidTypes
        foreach ($err in $parsed.Errors) { $errors += $err }
        if ($null -eq $parsed.Template) { continue }
        if ($parsed.Template.Type -ne $typeName) {
            $errors += "${label}: template declares type '$($parsed.Template.Type)' but is registered for '$typeName'"
            continue
        }
        $templates[$typeName] = $parsed.Template
    }
    return @{ Templates = $templates; Errors = $errors }
}

function Test-IssueTemplateConformance {
    # Validates one issue's parsed frontmatter and body headings against its
    # template. Returns bare reasons; the caller prints them with the file
    # name and template identity.
    param(
        $Frontmatter,
        [string[]]$Headings,
        $Template
    )
    $errors = @()
    $allowed = @{}
    foreach ($field in ($issueCoreFields + $issueLinkFields + $Template.RequiredFields + $Template.OptionalFields)) {
        $allowed[$field] = $true
    }
    foreach ($key in $Frontmatter.Keys) {
        if (-not $allowed.ContainsKey($key)) {
            $errors += "unknown frontmatter field '$key' (template '$($Template.Type)' does not declare it)"
        }
    }
    foreach ($field in $Template.RequiredFields) {
        if (-not $Frontmatter.ContainsKey($field) -or [string]::IsNullOrWhiteSpace($Frontmatter[$field])) {
            $errors += "missing required frontmatter field '$field' (template '$($Template.Type)')"
        }
    }
    $headingSet = @{}
    foreach ($heading in $Headings) {
        $headingSet[$heading.Trim().ToLowerInvariant()] = $true
    }
    foreach ($section in $Template.Sections) {
        if (-not $headingSet.ContainsKey($section.Trim().ToLowerInvariant())) {
            $errors += "missing required section '$section' (template '$($Template.Type)')"
        }
    }
    return $errors
}
