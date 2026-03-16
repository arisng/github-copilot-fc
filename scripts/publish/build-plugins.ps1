<#
.SYNOPSIS
    Builds self-contained plugin bundles from workspace source directories.

.DESCRIPTION
    Discovers plugins under plugins/cli/ and plugins/vscode/, creates runtime-scoped
    bundle directories under plugins/<runtime>/.build*/<plugin-name>/, resolves component
    path fields, copies artifacts, embeds agent instruction EMBED markers, and validates
    the bundle.

    Can be dot-sourced by publish-plugins.ps1 (or other scripts) to reuse the build
    functions without running the standalone build flow.

    Convention: every plugin MUST declare a "runtime" field in plugin.json that explicitly
    states which Copilot runtime the plugin targets:
      - "github-copilot-cli"  for CLI plugins under plugins/cli/
      - "github-copilot-vscode" for VS Code plugins under plugins/vscode/

.PARAMETER Plugins
    Array or comma-separated plugin names to build. Supports wildcard patterns.
    If omitted, builds all discovered plugins.

.EXAMPLE
    ./build-plugins.ps1
    Builds all discovered plugins.

.EXAMPLE
    ./build-plugins.ps1 -Plugins ralph-v2
    Builds only the ralph-v2 plugin.
#>
param(
    [Parameter(Mandatory = $false)]
    [string[]]$Plugins,

    [Parameter(Mandatory = $false)]
    [ValidateSet("stable", "beta")]
    [string]$Channel = "beta"
)

function Merge-AgentInstructions {
    <#
    .SYNOPSIS
        Resolves EMBED markers in agent files by inlining instruction content.

    .DESCRIPTION
        Scans agent markdown files for <!-- EMBED: filename --> markers and replaces
        them with the content of the referenced instruction file. Instruction YAML
        frontmatter and H1 headers are stripped before inlining. Agent YAML frontmatter
        is preserved verbatim. Validates merged body length and required section markers.

    .PARAMETER AgentDir
        Path to the .build/agents/ directory containing agent markdown files.

    .PARAMETER InstructionsDir
        Path to the source instructions/ directory.

    .PARAMETER MaxChars
        Maximum allowed character count for the markdown body (after frontmatter).
        Defaults to 30000 per copilot-cli limits.

    .OUTPUTS
        [hashtable] Summary with keys: Processed, Merged, Skipped, Errors.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AgentDir,
        [Parameter(Mandatory)][string]$InstructionsDir,
        [int]$MaxChars = 30000
    )

    $result = @{ Processed = 0; Merged = 0; Skipped = 0; Errors = 0 }

    $agentFiles = Get-ChildItem -Path $AgentDir -Filter '*.agent.md' -Recurse -ErrorAction SilentlyContinue
    if (-not $agentFiles) {
        return $result
    }

    foreach ($agentFile in $agentFiles) {
        $result.Processed++
        $rawContent = Get-Content $agentFile.FullName -Raw

        # Split into YAML frontmatter and markdown body
        if ($rawContent -match '(?s)^(---\r?\n.*?\r?\n---)\r?\n(.*)$') {
            $frontmatter = $Matches[1]
            $body = $Matches[2]
        }
        else {
            # No frontmatter — treat entire content as body
            $frontmatter = $null
            $body = $rawContent
        }

        # Check for EMBED marker in body
        if ($body -notmatch '<!-- EMBED:\s*(.+?)\s*-->') {
            $result.Skipped++
            continue
        }

        $instructionFilename = $Matches[1]
        $instructionPath = Join-Path $InstructionsDir $instructionFilename

        if (-not (Test-Path $instructionPath)) {
            Write-Error "  Instruction file not found: $instructionFilename (referenced by $($agentFile.Name))"
            $result.Errors++
            continue
        }

        $instructionContent = Get-Content $instructionPath -Raw

        # Strip YAML frontmatter from instruction content
        if ($instructionContent -match '(?s)^---\r?\n.*?\r?\n---\r?\n(.*)$') {
            $instructionContent = $Matches[1]
        }

        # Strip the first H1 header line
        $instructionContent = ([regex]'(?m)^# .+\r?\n').Replace($instructionContent, '', 1)
        # Trim leading whitespace left after stripping
        $instructionContent = $instructionContent.TrimStart("`r", "`n")

        # Replace the EMBED marker line with instruction content (script block avoids .NET backreference interpretation)
        $body = [Regex]::Replace($body, '(?m)^.*<!-- EMBED:\s*.+?\s*-->.*$', { param($m) $instructionContent })

        # Reassemble
        if ($frontmatter) {
            $mergedContent = "$frontmatter`n`n$body"
        }
        else {
            $mergedContent = $body
        }

        # Measure body char count (everything after frontmatter closing ---)
        if ($body.Length -gt $MaxChars) {
            Write-Error "  Agent body exceeds $MaxChars chars ($($body.Length)): $($agentFile.Name)"
            $result.Errors++
            continue
        }

        # Validate required section markers
        $requiredMarkers = @(
            @{ Name = 'Persona';          Pattern = '<persona>' },
            @{ Name = 'Rules';            Pattern = '<rules>' },
            @{ Name = 'Signal Protocol';  Pattern = 'Poll-Signals|Live Signals' },
            @{ Name = 'Contract';         Pattern = '<contract>' },
            @{ Name = 'Workflow';         Pattern = 'Workflow|Modes of Operation' }
        )

        foreach ($marker in $requiredMarkers) {
            if ($body -notmatch $marker.Pattern) {
                Write-Warning "  Missing section marker '$($marker.Name)' in $($agentFile.Name)"
            }
        }

        # Write back in-place
        Set-Content -Path $agentFile.FullName -Value $mergedContent -NoNewline -Encoding UTF8
        $result.Merged++
    }

    return $result
}

function Get-BundledPluginName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PluginName,
        [ValidateSet("stable", "beta")][string]$Channel = "beta"
    )

    if ($Channel -eq 'beta') {
        return "$PluginName-beta"
    }

    return $PluginName
}

function Copy-PluginReadmeToBundle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PluginDir,
        [Parameter(Mandatory)][string]$BuildDir
    )

    $readmePath = Join-Path $PluginDir 'README.md'
    if (-not (Test-Path $readmePath -PathType Leaf)) {
        return $false
    }

    Copy-Item -Path $readmePath -Destination (Join-Path $BuildDir 'README.md') -Force
    return $true
}

function Get-BundledComponentItemName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Field,
        [Parameter(Mandatory)][string]$ItemName,
        [Parameter(Mandatory)][bool]$IsDirectory,
        [ValidateSet("stable", "beta")][string]$Channel = "beta"
    )

    if ($Field -eq 'agents' -and -not $IsDirectory -and $Channel -eq 'beta' -and $ItemName -match '\.agent\.md$') {
        return ($ItemName -replace '\.agent\.md$', '-beta.agent.md')
    }

    return $ItemName
}

function Get-AgentFrontmatterName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AgentPath
    )

    if (-not (Test-Path $AgentPath -PathType Leaf)) {
        return $null
    }

    $content = Get-Content -Path $AgentPath -Raw
    $lines = $content -split "`r?`n"
    if ($lines.Count -lt 3 -or $lines[0] -ne '---') {
        return $null
    }

    $frontmatterEnd = -1
    for ($index = 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -eq '---') {
            $frontmatterEnd = $index
            break
        }
    }

    if ($frontmatterEnd -lt 0) {
        return $null
    }

    for ($index = 1; $index -lt $frontmatterEnd; $index++) {
        if ($lines[$index] -match '^(name:\s*)(["'']?)(.+?)\2\s*$') {
            return $Matches[3].Trim()
        }
    }

    return $null
}

function Get-AgentMarkdownBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AgentPath
    )

    if (-not (Test-Path $AgentPath -PathType Leaf)) {
        return $null
    }

    $content = Get-Content -Path $AgentPath -Raw
    if ($content -match '(?s)^---\r?\n.*?\r?\n---\r?\n?(.*)$') {
        return $Matches[1]
    }

    return $content
}

function Get-AgentFrontmatterAgents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AgentPath
    )

    if (-not (Test-Path $AgentPath -PathType Leaf)) {
        return @()
    }

    $content = Get-Content -Path $AgentPath -Raw
    $lines = $content -split "`r?`n"
    if ($lines.Count -lt 3 -or $lines[0] -ne '---') {
        return @()
    }

    $frontmatterEnd = -1
    for ($index = 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -eq '---') {
            $frontmatterEnd = $index
            break
        }
    }

    if ($frontmatterEnd -lt 0) {
        return @()
    }

    for ($index = 1; $index -lt $frontmatterEnd; $index++) {
        if ($lines[$index] -match '^(\s*agents:\s*\[)(.*)(\]\s*)$') {
            $agentNames = @()

            foreach ($entry in ($Matches[2] -split ',')) {
                $trimmedEntry = $entry.Trim()
                if ([string]::IsNullOrWhiteSpace($trimmedEntry)) {
                    continue
                }

                if ($trimmedEntry -match '^(["'']?)(.+?)\1$') {
                    $agentNames += $Matches[2].Trim()
                }
                else {
                    $agentNames += $trimmedEntry
                }
            }

            return $agentNames
        }
    }

    return @()
}

function Get-AgentFrontmatterVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AgentPath
    )

    if (-not (Test-Path $AgentPath -PathType Leaf)) {
        return $null
    }

    $content = Get-Content -Path $AgentPath -Raw
    $lines = $content -split "`r?`n"
    if ($lines.Count -lt 3 -or $lines[0] -ne '---') {
        return $null
    }

    $frontmatterEnd = -1
    for ($index = 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -eq '---') {
            $frontmatterEnd = $index
            break
        }
    }

    if ($frontmatterEnd -lt 0) {
        return $null
    }

    for ($index = 1; $index -lt $frontmatterEnd; $index++) {
        if ($lines[$index] -match '^\s*version:\s*(["'']?)(.+?)\1\s*$') {
            return $Matches[2].Trim()
        }
    }

    return $null
}

function Test-SemanticVersionString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Version
    )

    return $Version -match '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$'
}

function Get-RalphWorkflowVersionContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PluginDir,
        [Parameter(Mandatory)][object]$Manifest
    )

    if ($Manifest.name -ne 'ralph-v2') {
        return $null
    }

    $agentProperty = $Manifest.PSObject.Properties['agents']
    if ($null -eq $agentProperty) {
        throw "Ralph plugin manifest is missing the 'agents' field."
    }

    $agentEntries = if ($agentProperty.Value -is [System.Array]) {
        $agentProperty.Value
    }
    else {
        @($agentProperty.Value)
    }

    if ($agentEntries.Count -eq 0) {
        throw "Ralph plugin manifest does not declare any agent entries."
    }

    $agentVersions = @()
    foreach ($agentEntry in $agentEntries) {
        $agentPath = Join-Path $PluginDir $agentEntry
        try {
            $resolvedAgentPath = (Resolve-Path $agentPath -ErrorAction Stop).Path
        }
        catch {
            throw "Unable to resolve Ralph agent path '$agentEntry'."
        }

        $agentVersion = Get-AgentFrontmatterVersion -AgentPath $resolvedAgentPath
        if ([string]::IsNullOrWhiteSpace($agentVersion)) {
            throw "Ralph agent '$agentEntry' is missing a YAML frontmatter version."
        }

        $agentVersions += [PSCustomObject]@{
            Path = $resolvedAgentPath
            Version = $agentVersion
        }
    }

    $distinctVersions = @($agentVersions.Version | Sort-Object -Unique)
    if ($distinctVersions.Count -ne 1) {
        $versionSummary = ($agentVersions | ForEach-Object { "$($_.Path)=$($_.Version)" }) -join '; '
        throw "Ralph agents do not share one canonical workflow version: $versionSummary"
    }

    $workflowVersion = $distinctVersions[0]
    $manifestVersion = if ($Manifest.PSObject.Properties['version']) { [string]$Manifest.version } else { $null }
    if ([string]::IsNullOrWhiteSpace($manifestVersion)) {
        throw "Ralph plugin manifest is missing the 'version' field."
    }

    $manifestVersion = $manifestVersion.Trim()
    if (-not (Test-SemanticVersionString -Version $manifestVersion)) {
        throw "Ralph plugin manifest version must be a semantic version. Received '$manifestVersion'."
    }

    return [PSCustomObject]@{
        WorkflowVersion              = $workflowVersion
        ManifestVersion              = $manifestVersion
        BundleVersion                = $manifestVersion
        BundleVersionSource          = 'manifest'
        BundleVersionMatchesWorkflow = ($manifestVersion -eq $workflowVersion)
    }
}

function Update-AgentFrontmatterNameForChannel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AgentPath,
        [ValidateSet("stable", "beta")][string]$Channel = "beta"
    )

    if ($Channel -ne 'beta' -or -not (Test-Path $AgentPath -PathType Leaf)) {
        return $false
    }

    $content = Get-Content -Path $AgentPath -Raw
    $lines = $content -split "`r?`n"
    if ($lines.Count -lt 3 -or $lines[0] -ne '---') {
        return $false
    }

    $frontmatterEnd = -1
    for ($index = 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -eq '---') {
            $frontmatterEnd = $index
            break
        }
    }

    if ($frontmatterEnd -lt 0) {
        return $false
    }

    $updated = $false
    for ($index = 1; $index -lt $frontmatterEnd; $index++) {
        if ($lines[$index] -match '^(name:\s*)(["'']?)(.+?)\2\s*$') {
            $prefix = $Matches[1]
            $quote = $Matches[2]
            $nameValue = $Matches[3].Trim()

            if ($nameValue -notmatch '-beta$') {
                $lines[$index] = "$prefix$quote$nameValue-beta$quote"
                $updated = $true
            }
            continue
        }

        if ($lines[$index] -match '^(\s*agents:\s*\[)(.*)(\]\s*)$') {
            $prefix = $Matches[1]
            $suffix = $Matches[3]
            $updatedAgentNames = @()
            $agentsUpdated = $false

            foreach ($entry in ($Matches[2] -split ',')) {
                $trimmedEntry = $entry.Trim()
                if ([string]::IsNullOrWhiteSpace($trimmedEntry)) {
                    continue
                }

                $quote = ''
                $agentName = $trimmedEntry
                if ($trimmedEntry -match '^(["'']?)(.+?)\1$') {
                    $quote = $Matches[1]
                    $agentName = $Matches[2].Trim()
                }

                if ($agentName -notmatch '-beta$') {
                    $agentName = "$agentName-beta"
                    $agentsUpdated = $true
                }

                if ($quote) {
                    $updatedAgentNames += "$quote$agentName$quote"
                }
                else {
                    $updatedAgentNames += $agentName
                }
            }

            if ($agentsUpdated) {
                $lines[$index] = "$prefix$($updatedAgentNames -join ', ')$suffix"
                $updated = $true
            }
        }
    }

    if (-not $updated) {
        return $false
    }

    $updatedContent = [string]::Join("`n", $lines)
    Set-Content -Path $AgentPath -Value $updatedContent -NoNewline -Encoding UTF8
    return $true
}

function Update-BundledAgentFrontmatterNames {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [ValidateSet("stable", "beta")][string]$Channel = "beta"
    )

    if ($Channel -ne 'beta' -or -not (Test-Path $TargetPath)) {
        return 0
    }

    $agentItems = @()
    if (Test-Path $TargetPath -PathType Container) {
        $agentItems = @(Get-ChildItem -Path $TargetPath -Filter '*.agent.md' -File -Recurse -ErrorAction SilentlyContinue)
    }
    elseif ((Get-Item -Path $TargetPath).Name -match '\.agent\.md$') {
        $agentItems = @((Get-Item -Path $TargetPath))
    }

    $updatedCount = 0
    foreach ($agentItem in $agentItems) {
        if (Update-AgentFrontmatterNameForChannel -AgentPath $agentItem.FullName -Channel $Channel) {
            $updatedCount++
        }
    }

    return $updatedCount
}

function Test-AgentChannelContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BuildDir,
        [Parameter(Mandatory)][object]$AgentEntries,
        [ValidateSet("stable", "beta")][string]$Channel = "beta"
    )

    $errors = @()
    $agentPaths = if ($AgentEntries -is [System.Array]) { $AgentEntries } else { @($AgentEntries) }
    $agentFiles = Get-ChildItem -Path (Join-Path $BuildDir 'agents') -Filter '*.agent.md' -File -ErrorAction SilentlyContinue
    $bundledAgentNames = @{}

    foreach ($agentPath in $agentPaths) {
        $leafName = Split-Path $agentPath -Leaf
        $isBetaAgentName = $leafName -match '-beta\.agent\.md$'

        if ($Channel -eq 'beta' -and -not $isBetaAgentName) {
            $errors += "agents`: $agentPath (beta bundle manifest entry must end with -beta.agent.md)"
        }

        if ($Channel -eq 'stable' -and $isBetaAgentName) {
            $errors += "agents`: $agentPath (stable bundle manifest entry must not end with -beta.agent.md)"
        }
    }

    foreach ($agentFile in $agentFiles) {
        $agentFrontmatterName = Get-AgentFrontmatterName -AgentPath $agentFile.FullName
        if (-not [string]::IsNullOrWhiteSpace($agentFrontmatterName)) {
            $bundledAgentNames[$agentFrontmatterName] = $true
        }
    }

    foreach ($agentFile in $agentFiles) {
        $isBetaAgentName = $agentFile.Name -match '-beta\.agent\.md$'
        $agentFrontmatterName = Get-AgentFrontmatterName -AgentPath $agentFile.FullName
        $agentFrontmatterAgents = @(Get-AgentFrontmatterAgents -AgentPath $agentFile.FullName)

        if ($Channel -eq 'beta' -and -not $isBetaAgentName) {
            $errors += "agents`: agents/$($agentFile.Name) (beta bundle file must end with -beta.agent.md)"
        }

        if ($Channel -eq 'stable' -and $isBetaAgentName) {
            $errors += "agents`: agents/$($agentFile.Name) (stable bundle file must not end with -beta.agent.md)"
        }

        if ([string]::IsNullOrWhiteSpace($agentFrontmatterName)) {
            $errors += "agents`: agents/$($agentFile.Name) (missing YAML frontmatter name field)"
            continue
        }

        if ($Channel -eq 'beta' -and ($agentFrontmatterName -notmatch '-beta$' -or $agentFrontmatterName -match '-beta-beta$')) {
            $errors += "agents`: agents/$($agentFile.Name) (beta bundle frontmatter name must end with -beta exactly once; found '$agentFrontmatterName')"
        }

        if ($Channel -eq 'stable' -and $agentFrontmatterName -match '-beta$') {
            $errors += "agents`: agents/$($agentFile.Name) (stable bundle frontmatter name must not end with -beta; found '$agentFrontmatterName')"
        }

        foreach ($agentReference in $agentFrontmatterAgents) {
            if ($Channel -eq 'beta' -and ($agentReference -notmatch '-beta$' -or $agentReference -match '-beta-beta$')) {
                $errors += "agents`: agents/$($agentFile.Name) (beta bundle frontmatter agents entry must end with -beta exactly once; found '$agentReference')"
            }

            if ($Channel -eq 'stable' -and $agentReference -match '-beta$') {
                $errors += "agents`: agents/$($agentFile.Name) (stable bundle frontmatter agents entry must not end with -beta; found '$agentReference')"
            }

            if (-not $bundledAgentNames.ContainsKey($agentReference)) {
                $errors += "agents`: agents/$($agentFile.Name) (frontmatter agents entry '$agentReference' does not match any bundled agent name)"
            }
        }
    }

    return $errors
}

function Convert-MarkdownTableLineToCells {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Line
    )

    $trimmedLine = $Line.Trim()
    if ($trimmedLine -notmatch '^\|.*\|$') {
        return @()
    }

    $cells = @()
    foreach ($cell in ($trimmedLine.Trim('|') -split '\|')) {
        $cells += $cell.Trim()
    }

    return $cells
}

function Get-RalphSubagentAlias {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AgentName
    )

    if ([string]::IsNullOrWhiteSpace($AgentName)) {
        return $null
    }

    if ($AgentName -match '^Ralph-v2-(Planner|Questioner|Executor|Reviewer|Librarian)(?:-(?:CLI|VSCode))?(?:-beta)?$') {
        return $Matches[1].ToLowerInvariant()
    }

    return $null
}

function Get-RalphExpectedAliasNameMatrix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot
    )

    $requiredAliases = @('planner', 'questioner', 'executor', 'reviewer', 'librarian')
    $errors = @()
    $stableNamesByRuntime = @{
        'vscode' = @{}
        'cli'    = @{}
    }

    $runtimeDirs = @{
        'vscode' = Join-Path (Join-Path (Join-Path $RepoRoot 'agents') 'ralph-v2') 'vscode'
        'cli'    = Join-Path (Join-Path (Join-Path $RepoRoot 'agents') 'ralph-v2') 'cli'
    }

    foreach ($runtimeName in $runtimeDirs.Keys) {
        $runtimeDir = $runtimeDirs[$runtimeName]
        if (-not (Test-Path $runtimeDir -PathType Container)) {
            $errors += "Ralph source runtime directory not found: $runtimeDir"
            continue
        }

        $sourceAgentFiles = @(Get-ChildItem -Path $runtimeDir -Filter '*.agent.md' -File -ErrorAction SilentlyContinue)
        foreach ($sourceAgentFile in $sourceAgentFiles) {
            $sourceAgentName = Get-AgentFrontmatterName -AgentPath $sourceAgentFile.FullName
            if ([string]::IsNullOrWhiteSpace($sourceAgentName) -or $sourceAgentName -match '^Ralph-v2-Orchestrator(?:-(?:CLI|VSCode))?$') {
                continue
            }

            $alias = Get-RalphSubagentAlias -AgentName $sourceAgentName
            if ($null -eq $alias) {
                continue
            }

            if ($stableNamesByRuntime[$runtimeName].ContainsKey($alias)) {
                $errors += "Ralph source runtime '$runtimeName' declares alias '$alias' more than once."
                continue
            }

            if ($sourceAgentName -cmatch '-beta$') {
                $errors += "Ralph source runtime '$runtimeName' agent '$sourceAgentName' must not end with -beta."
                continue
            }

            $stableNamesByRuntime[$runtimeName][$alias] = $sourceAgentName
        }

        foreach ($requiredAlias in $requiredAliases) {
            if (-not $stableNamesByRuntime[$runtimeName].ContainsKey($requiredAlias)) {
                $errors += "Ralph source runtime '$runtimeName' is missing alias '$requiredAlias'."
            }
        }
    }

    $rows = @{}
    if ($errors.Count -eq 0) {
        foreach ($alias in $requiredAliases) {
            $vscodeStable = $stableNamesByRuntime['vscode'][$alias]
            $cliStable = $stableNamesByRuntime['cli'][$alias]

            $rows[$alias] = [ordered]@{
                'VS Code Stable' = $vscodeStable
                'VS Code Beta'   = "$vscodeStable-beta"
                'CLI Stable'     = $cliStable
                'CLI Beta'       = "$cliStable-beta"
            }
        }
    }

    return [PSCustomObject]@{
        Errors = $errors
        Rows   = $rows
    }
}

function Get-RalphSubagentAliasTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AgentPath
    )

    $errors = @()
    $rows = @{}
    $agentDisplayPath = "agents/$([System.IO.Path]::GetFileName($AgentPath))"
    $body = Get-AgentMarkdownBody -AgentPath $AgentPath

    if ([string]::IsNullOrWhiteSpace($body)) {
        $errors += "agents`: $agentDisplayPath (missing merged markdown body)"
        return [PSCustomObject]@{
            Errors = $errors
            Rows   = $rows
        }
    }

    $lines = $body -split "`r?`n"
    $sectionIndex = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index].Trim() -ceq '## Subagent Alias Table') {
            $sectionIndex = $index
            break
        }
    }

    if ($sectionIndex -lt 0) {
        $errors += "agents`: $agentDisplayPath (missing '## Subagent Alias Table' section)"
        return [PSCustomObject]@{
            Errors = $errors
            Rows   = $rows
        }
    }

    $lineIndex = $sectionIndex + 1
    while ($lineIndex -lt $lines.Count -and [string]::IsNullOrWhiteSpace($lines[$lineIndex])) {
        $lineIndex++
    }

    if ($lineIndex -ge $lines.Count) {
        $errors += "agents`: $agentDisplayPath (subagent alias table is missing the table header)"
        return [PSCustomObject]@{
            Errors = $errors
            Rows   = $rows
        }
    }

    $expectedHeader = '| Alias | VS Code Stable | VS Code Beta | CLI Stable | CLI Beta |'
    if ($lines[$lineIndex].Trim() -cne $expectedHeader) {
        $errors += "agents`: $agentDisplayPath (subagent alias table header must be exactly '$expectedHeader')"
        return [PSCustomObject]@{
            Errors = $errors
            Rows   = $rows
        }
    }

    $lineIndex++
    if ($lineIndex -ge $lines.Count -or $lines[$lineIndex].Trim() -notmatch '^\|\s*-+\s*\|\s*-+\s*\|\s*-+\s*\|\s*-+\s*\|\s*-+\s*\|$') {
        $errors += "agents`: $agentDisplayPath (subagent alias table is missing a valid markdown separator row)"
        return [PSCustomObject]@{
            Errors = $errors
            Rows   = $rows
        }
    }

    $lineIndex++
    while ($lineIndex -lt $lines.Count) {
        $trimmedLine = $lines[$lineIndex].Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine -notmatch '^\|') {
            break
        }

        $cells = @(Convert-MarkdownTableLineToCells -Line $trimmedLine)
        if ($cells.Count -ne 5) {
            $errors += "agents`: $agentDisplayPath (subagent alias table row '$trimmedLine' must contain exactly 5 columns)"
            $lineIndex++
            continue
        }

        $alias = $cells[0].ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($alias)) {
            $errors += "agents`: $agentDisplayPath (subagent alias table contains an empty alias cell)"
            $lineIndex++
            continue
        }

        if ($rows.ContainsKey($alias)) {
            $errors += "agents`: $agentDisplayPath (subagent alias table declares alias '$alias' more than once)"
            $lineIndex++
            continue
        }

        $rows[$alias] = [ordered]@{
            'VS Code Stable' = $cells[1]
            'VS Code Beta'   = $cells[2]
            'CLI Stable'     = $cells[3]
            'CLI Beta'       = $cells[4]
        }

        $lineIndex++
    }

    if ($rows.Count -eq 0) {
        $errors += "agents`: $agentDisplayPath (subagent alias table does not contain any alias rows)"
    }

    return [PSCustomObject]@{
        Errors = $errors
        Rows   = $rows
    }
}

function Test-RalphNextAgentAliasExamples {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BuildDir
    )

    $errors = @()
    $agentDir = Join-Path $BuildDir 'agents'
    if (-not (Test-Path $agentDir -PathType Container)) {
        return $errors
    }

    $nextAgentRuntimeNamePattern = '(?im)^[^\r\n]*\bnext_agent\b[^\r\n]*\b(Ralph-v2-(?:Planner|Questioner|Executor|Reviewer|Librarian|Orchestrator)(?:-(?:CLI|VSCode))?(?:-beta)?)\b[^\r\n]*$'
    $agentFiles = @(Get-ChildItem -Path $agentDir -Filter '*.agent.md' -File -ErrorAction SilentlyContinue)

    foreach ($agentFile in $agentFiles) {
        $body = Get-AgentMarkdownBody -AgentPath $agentFile.FullName
        if ([string]::IsNullOrWhiteSpace($body)) {
            continue
        }

        $matches = [regex]::Matches($body, $nextAgentRuntimeNamePattern)
        foreach ($match in $matches) {
            $rawRuntimeName = $match.Groups[1].Value
            $errors += "agents`: agents/$($agentFile.Name) (next_agent examples must use aliases instead of raw runtime name '$rawRuntimeName')"
        }
    }

    return @($errors | Select-Object -Unique)
}

function Test-RalphSubagentAliasContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BuildDir,
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$PluginName,
        [ValidateSet('cli', 'vscode')][string]$RuntimeName,
        [ValidateSet('stable', 'beta')][string]$Channel = 'beta'
    )

    if ($PluginName -notmatch '^ralph-v2(?:-beta)?$') {
        return @()
    }

    $errors = @()
    $requiredAliases = @('planner', 'questioner', 'executor', 'reviewer', 'librarian')
    $agentDir = Join-Path $BuildDir 'agents'

    if (-not (Test-Path $agentDir -PathType Container)) {
        return @("agents`: agents/ (Ralph bundle is missing bundled agent files)")
    }

    $bundledAgentFiles = @(Get-ChildItem -Path $agentDir -Filter '*.agent.md' -File -ErrorAction SilentlyContinue)
    $orchestratorAgents = @($bundledAgentFiles | Where-Object { $_.Name -match 'orchestrator' })
    $bundledSubagentNamesByAlias = @{}

    foreach ($bundledAgentFile in $bundledAgentFiles) {
        $bundledAgentName = Get-AgentFrontmatterName -AgentPath $bundledAgentFile.FullName
        if ([string]::IsNullOrWhiteSpace($bundledAgentName)) {
            continue
        }

        $alias = Get-RalphSubagentAlias -AgentName $bundledAgentName
        if ($null -eq $alias) {
            continue
        }

        if ($bundledSubagentNamesByAlias.ContainsKey($alias)) {
            $errors += "agents`: agents/$($bundledAgentFile.Name) (Ralph bundle declares alias '$alias' more than once)"
            continue
        }

        $bundledSubagentNamesByAlias[$alias] = $bundledAgentName
    }

    foreach ($requiredAlias in $requiredAliases) {
        if (-not $bundledSubagentNamesByAlias.ContainsKey($requiredAlias)) {
            $errors += "agents`: agents/ (Ralph bundle is missing subagent alias '$requiredAlias')"
        }
    }

    $unexpectedBundledAliases = @($bundledSubagentNamesByAlias.Keys | Where-Object { $_ -notin $requiredAliases })
    foreach ($unexpectedAlias in $unexpectedBundledAliases) {
        $errors += "agents`: agents/ (Ralph bundle contains unexpected subagent alias '$unexpectedAlias')"
    }

    if ($orchestratorAgents.Count -ne 1) {
        $errors += "agents`: agents/ (Ralph bundle must contain exactly one orchestrator agent file; found $($orchestratorAgents.Count))"
    }

    $expectedMatrixResult = Get-RalphExpectedAliasNameMatrix -RepoRoot $RepoRoot
    $errors += $expectedMatrixResult.Errors

    if ($orchestratorAgents.Count -eq 1) {
        $aliasTableResult = Get-RalphSubagentAliasTable -AgentPath $orchestratorAgents[0].FullName
        $errors += $aliasTableResult.Errors

        if ($aliasTableResult.Errors.Count -eq 0) {
            $unexpectedAliases = @($aliasTableResult.Rows.Keys | Where-Object { $_ -notin $requiredAliases })
            foreach ($unexpectedAlias in $unexpectedAliases) {
                $errors += "agents`: agents/$($orchestratorAgents[0].Name) (subagent alias table contains unexpected alias '$unexpectedAlias')"
            }

            $currentColumnName = switch ($RuntimeName) {
                'vscode' {
                    if ($Channel -eq 'beta') { 'VS Code Beta' } else { 'VS Code Stable' }
                }
                'cli' {
                    if ($Channel -eq 'beta') { 'CLI Beta' } else { 'CLI Stable' }
                }
            }

            foreach ($requiredAlias in $requiredAliases) {
                if (-not $aliasTableResult.Rows.ContainsKey($requiredAlias)) {
                    $errors += "agents`: agents/$($orchestratorAgents[0].Name) (subagent alias table is missing alias '$requiredAlias')"
                    continue
                }

                $row = $aliasTableResult.Rows[$requiredAlias]
                foreach ($stableColumn in @('VS Code Stable', 'CLI Stable')) {
                    if ($row[$stableColumn] -cmatch '-beta$') {
                        $errors += "agents`: agents/$($orchestratorAgents[0].Name) (table value '$($row[$stableColumn])' in '$stableColumn' must not end with -beta)"
                    }
                }

                foreach ($betaColumn in @('VS Code Beta', 'CLI Beta')) {
                    if ($row[$betaColumn] -cnotmatch '-beta$' -or $row[$betaColumn] -cmatch '-beta-beta$') {
                        $errors += "agents`: agents/$($orchestratorAgents[0].Name) (table value '$($row[$betaColumn])' in '$betaColumn' must end with -beta exactly once)"
                    }
                }

                if ($expectedMatrixResult.Errors.Count -eq 0) {
                    $expectedRow = $expectedMatrixResult.Rows[$requiredAlias]
                    foreach ($columnName in $expectedRow.Keys) {
                        if ($row[$columnName] -cne $expectedRow[$columnName]) {
                            $errors += "agents`: agents/$($orchestratorAgents[0].Name) (alias '$requiredAlias' column '$columnName' expected '$($expectedRow[$columnName])' but found '$($row[$columnName])')"
                        }
                    }
                }

                if ($bundledSubagentNamesByAlias.ContainsKey($requiredAlias)) {
                    $resolvedBundledName = $bundledSubagentNamesByAlias[$requiredAlias]
                    if ($row[$currentColumnName] -cne $resolvedBundledName) {
                        $errors += "agents`: agents/$($orchestratorAgents[0].Name) (alias '$requiredAlias' column '$currentColumnName' must resolve to bundled agent name '$resolvedBundledName')"
                    }
                }
            }
        }
    }

    $errors += Test-RalphNextAgentAliasExamples -BuildDir $BuildDir
    return @($errors | Select-Object -Unique)
}

function Copy-HookSupportAssets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$BuildDir
    )

    $sourceHooksDir = Join-Path $RepoRoot 'hooks'
    if (-not (Test-Path $sourceHooksDir)) {
        return $false
    }

    $sourceScriptDirs = @(
        Get-ChildItem -Path $sourceHooksDir -Directory -Recurse |
            Where-Object { $_.Name -eq 'scripts' }
    )

    if ($sourceScriptDirs.Count -eq 0) {
        return $false
    }

    $hookBuildDir = Join-Path $BuildDir 'hooks'
    New-Item -Path $hookBuildDir -ItemType Directory -Force | Out-Null

    foreach ($sourceScriptDir in $sourceScriptDirs) {
        $relativeScriptDir = [System.IO.Path]::GetRelativePath($sourceHooksDir, $sourceScriptDir.FullName)
        if ($relativeScriptDir.StartsWith('..')) {
            throw "Hook support assets must remain inside hooks/: $($sourceScriptDir.FullName)"
        }

        $targetScriptDir = Join-Path $hookBuildDir $relativeScriptDir
        $targetParentDir = Split-Path -Path $targetScriptDir -Parent
        New-Item -Path $targetParentDir -ItemType Directory -Force | Out-Null

        if (Test-Path $targetScriptDir) {
            Remove-Item $targetScriptDir -Recurse -Force
        }

        Copy-Item -Path $sourceScriptDir.FullName -Destination $targetScriptDir -Recurse -Force
    }

    return $true
}

function Get-PluginBundleLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PluginDir,

        [ValidateSet("stable", "beta")]
        [string]$Channel = "beta"
    )

    $pluginItem = Get-Item -Path $PluginDir -ErrorAction Stop
    $runtimeDir = Split-Path $pluginItem.FullName -Parent
    $runtimeName = Split-Path $runtimeDir -Leaf
    $bundledPluginName = Get-BundledPluginName -PluginName $pluginItem.Name -Channel $Channel
    $buildRoot = Join-Path $runtimeDir '.build'
    $buildDir = Join-Path $buildRoot $bundledPluginName

    return [PSCustomObject]@{
        PluginName        = $bundledPluginName
        SourcePluginName  = $pluginItem.Name
        RuntimeDir        = $runtimeDir
        RuntimeName       = $runtimeName
        BuildRoot         = $buildRoot
        BuildDir          = $buildDir
        Channel           = $Channel
    }
}

function Initialize-PluginBundleOutput {
    <#
    .SYNOPSIS
        Prepares runtime-scoped bundle targets for a selected set of plugins.

    .DESCRIPTION
        Cleanup is orchestrated at the runtime level so full runtime builds can reset the
        entire plugins/<runtime>/.build/ tree, while filtered builds only reset the bundle
        directories for the selected plugins.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.DirectoryInfo[]]$SelectedPluginDirs,

        [Parameter(Mandatory)]
        [System.IO.DirectoryInfo[]]$AllPluginDirs,

        [ValidateSet("stable", "beta")]
        [string]$Channel = "beta"
    )

    if ($SelectedPluginDirs.Count -eq 0) {
        return
    }

    $selectedLayouts = $SelectedPluginDirs | ForEach-Object {
        Get-PluginBundleLayout -PluginDir $_.FullName -Channel $Channel
    }

    foreach ($runtimeGroup in ($selectedLayouts | Group-Object BuildRoot)) {
        $runtimeLayouts = @($runtimeGroup.Group)
        $buildRoot = $runtimeLayouts[0].BuildRoot

        New-Item -Path $buildRoot -ItemType Directory -Force | Out-Null

        foreach ($layout in $runtimeLayouts) {
            if (Test-Path $layout.BuildDir) {
                Remove-Item $layout.BuildDir -Recurse -Force
            }

            if ($layout.Channel -eq 'beta') {
                $legacyBetaDir = Join-Path (Join-Path $layout.RuntimeDir '.build-beta') $layout.SourcePluginName
                if (Test-Path $legacyBetaDir) {
                    Remove-Item $legacyBetaDir -Recurse -Force
                }
            }
        }
    }
}

function Build-PluginBundle {
    <#
    .SYNOPSIS
        Creates a self-contained build directory for a plugin.

    .DESCRIPTION
        Parses plugin.json, resolves all component path fields, copies referenced
        artifacts into a runtime-scoped bundle directory, and rewrites plugin.json with
        local paths. Only official schema fields plus the "runtime" convention field are
        retained in the output manifest.

        Convention: validates that the source plugin.json declares a "runtime" field
        matching the directory convention (cli -> "github-copilot-cli", vscode ->
        "github-copilot-vscode"). Emits a warning if missing.

    .PARAMETER PluginDir
        Full path to the plugin source directory containing plugin.json.

    .PARAMETER Channel
        Build channel: 'beta' (default) or 'stable'. Beta builds go to
        .build/<name>-beta/ while stable builds go to .build/<name>/.

    .OUTPUTS
        [string] Path to the runtime-scoped bundle directory on success, $null on failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PluginDir,

        [ValidateSet("stable", "beta")]
        [string]$Channel = "beta"
    )

    $officialComponentFields = @('agents', 'skills', 'commands', 'hooks', 'mcpServers', 'lspServers')
    # Official metadata fields + "runtime" convention field (runtime is preserved in bundles per workspace convention)
    $officialMetadataFields = @('name', 'description', 'version', 'author', 'license', 'homepage', 'bugs', 'repository', 'keywords', 'runtime')

    $manifestPath = Join-Path $PluginDir "plugin.json"
    if (-not (Test-Path $manifestPath)) {
        Write-Error "plugin.json not found in: $PluginDir"
        return $null
    }

    # Parse source manifest
    try {
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Error "Failed to parse plugin.json in $PluginDir`: $_"
        return $null
    }

    $sourcePluginName = $manifest.name
    $pluginName = Get-BundledPluginName -PluginName $sourcePluginName -Channel $Channel
    $ralphVersionContract = $null

    try {
        $ralphVersionContract = Get-RalphWorkflowVersionContract -PluginDir $PluginDir -Manifest $manifest
    }
    catch {
        Write-Error "Failed to resolve Ralph workflow version contract for $PluginDir`: $_"
        return $null
    }

    # Convention: validate runtime field
    if (-not $manifest.PSObject.Properties['runtime']) {
        Write-Warning "  plugin.json for '$pluginName' is missing the 'runtime' field. Convention requires explicitly declaring the target Copilot runtime (e.g., 'github-copilot-cli' or 'github-copilot-vscode')."
    }

    $bundleLayout = Get-PluginBundleLayout -PluginDir $PluginDir -Channel $Channel
    $buildDir = $bundleLayout.BuildDir

    # Bundle cleanup is orchestrated by Initialize-PluginBundleOutput.
    New-Item -Path $buildDir -ItemType Directory -Force | Out-Null

    Write-Host "  Bundling: $pluginName -> plugins/$($bundleLayout.RuntimeName)/.build/$($bundleLayout.PluginName)/" -ForegroundColor DarkGray

    if (Copy-PluginReadmeToBundle -PluginDir $PluginDir -BuildDir $buildDir) {
        Write-Host "  Bundled plugin README: README.md" -ForegroundColor DarkGray
    }

    # Build a clean manifest with only official + convention fields
    $cleanManifest = [ordered]@{}
    $repoRoot = Split-Path $PSScriptRoot -Parent | Split-Path -Parent

    # Copy metadata fields
    foreach ($field in $officialMetadataFields) {
        $value = $manifest.PSObject.Properties[$field]
        if ($null -ne $value) {
            $cleanManifest[$field] = $value.Value
        }
    }

    if ($null -ne $ralphVersionContract) {
        Write-Host "  Ralph workflow version: $($ralphVersionContract.WorkflowVersion)" -ForegroundColor DarkGray
        Write-Host "  Ralph plugin manifest version: $($ralphVersionContract.BundleVersion) ($($ralphVersionContract.BundleVersionSource))" -ForegroundColor DarkGray
    }

    # Override name for beta channel
    if ($Channel -eq 'beta') {
        $cleanManifest['name'] = $pluginName
    }

    # Process component fields: resolve, copy, and rewrite paths
    $validationErrors = @()

    foreach ($field in $officialComponentFields) {
        $value = $manifest.PSObject.Properties[$field]
        if ($null -eq $value) { continue }

        $componentBuildDir = Join-Path $buildDir $field

        if ($value.Value -is [System.Array] -or $value.Value -is [System.Collections.IEnumerable] -and $value.Value -isnot [string]) {
            # Array of paths (e.g., skills)
            New-Item -Path $componentBuildDir -ItemType Directory -Force | Out-Null
            $localPaths = @()

            foreach ($relativePath in $value.Value) {
                $sourcePath = Join-Path $PluginDir $relativePath
                try {
                    $resolvedSource = (Resolve-Path $sourcePath -ErrorAction Stop).Path
                }
                catch {
                    Write-Error "  Cannot resolve component path: $relativePath"
                    $validationErrors += "$field`: $relativePath (unresolvable)"
                    continue
                }

                $itemName = Split-Path $resolvedSource -Leaf
                $isDirectory = Test-Path $resolvedSource -PathType Container
                $bundledItemName = Get-BundledComponentItemName -Field $field -ItemName $itemName -IsDirectory $isDirectory -Channel $Channel
                $targetPath = Join-Path $componentBuildDir $bundledItemName

                Copy-Item -Path $resolvedSource -Destination $targetPath -Recurse -Force
                if ($field -eq 'agents') {
                    [void](Update-BundledAgentFrontmatterNames -TargetPath $targetPath -Channel $Channel)
                }
                if ($isDirectory) {
                    $localPaths += "$field/$bundledItemName/"
                }
                else {
                    $localPaths += "$field/$bundledItemName"
                }
            }

            $cleanManifest[$field] = $localPaths
        }
        else {
            # Single path (e.g., agents, hooks)
            $relativePath = $value.Value
            $sourcePath = Join-Path $PluginDir $relativePath
            try {
                $resolvedSource = (Resolve-Path $sourcePath -ErrorAction Stop).Path
            }
            catch {
                Write-Error "  Cannot resolve component path: $relativePath"
                $validationErrors += "$field`: $relativePath (unresolvable)"
                continue
            }

            Copy-Item -Path $resolvedSource -Destination $componentBuildDir -Recurse -Force
            if ($field -eq 'agents') {
                [void](Update-BundledAgentFrontmatterNames -TargetPath $componentBuildDir -Channel $Channel)
            }
            $cleanManifest[$field] = "$field/"
        }
    }

    if ($cleanManifest.Contains('hooks')) {
        if (Copy-HookSupportAssets -RepoRoot $repoRoot -BuildDir $buildDir) {
            Write-Host "  Bundled hook support assets under hooks/" -ForegroundColor DarkGray
        }
        else {
            Write-Warning "  Hook manifests were bundled, but no hook support assets were found under hooks/"
        }
    }

    # Write cleaned manifest
    $cleanManifest | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $buildDir "plugin.json") -Encoding UTF8

    # Merge agent instructions (embed instruction content into agent bodies)
    if ($cleanManifest.Contains('agents')) {
        $agentBuildDir = Join-Path $buildDir "agents"
        $instructionsDir = Join-Path $repoRoot "agents/ralph-v2/instructions"

        # VS Code has no CLI-style 30K body limit; allow large merged bodies
        $maxChars = if ($bundleLayout.RuntimeName -eq 'cli') { 30000 } else { [int]::MaxValue }

        if (Test-Path $agentBuildDir) {
            $mergeResult = Merge-AgentInstructions -AgentDir $agentBuildDir -InstructionsDir $instructionsDir -MaxChars $maxChars
            if ($mergeResult.Errors -gt 0) {
                Write-Warning "  Agent instruction merge had $($mergeResult.Errors) error(s)"
            }
            Write-Host "  Merged instructions: $($mergeResult.Merged) agent(s), $($mergeResult.Skipped) skipped, $($mergeResult.Errors) error(s)" -ForegroundColor DarkGray
        }
    }

    # Post-bundle validation: verify every component path in the bundle manifest
    foreach ($field in $officialComponentFields) {
        if (-not $cleanManifest.Contains($field)) { continue }

        $fieldValue = $cleanManifest[$field]
        $paths = if ($fieldValue -is [System.Array]) { $fieldValue } else { @($fieldValue) }

        foreach ($p in $paths) {
            $checkPath = Join-Path $buildDir $p
            if (-not (Test-Path $checkPath)) {
                $validationErrors += "$field`: $p (missing in bundle)"
            }
        }
    }

    if ($cleanManifest.Contains('agents')) {
        $validationErrors += Test-AgentChannelContract -BuildDir $buildDir -AgentEntries $cleanManifest['agents'] -Channel $Channel
        $validationErrors += Test-RalphSubagentAliasContract -BuildDir $buildDir -RepoRoot $repoRoot -PluginName $sourcePluginName -RuntimeName $bundleLayout.RuntimeName -Channel $Channel
    }

    if ($validationErrors.Count -gt 0) {
        Write-Error "  Bundle validation failed for $pluginName`:"
        foreach ($err in $validationErrors) {
            Write-Error "    - $err"
        }
        return $null
    }

    Write-Host "  Bundle validated: $pluginName" -ForegroundColor Green
    return $buildDir
}

function Invoke-PluginBuild {
    <#
    .SYNOPSIS
        Discovers workspace plugins and builds self-contained bundles for each.

    .DESCRIPTION
        Scans plugins/cli/ and plugins/vscode/ for plugin directories containing
        plugin.json, then calls Build-PluginBundle for each. Use this for CI/CD
        pre-validation or local testing without installing plugins.

    .PARAMETER Plugins
        Optional filter — array or comma-separated plugin names (supports wildcards).
    #>
    [CmdletBinding()]
    param(
        [string[]]$Plugins,

        [ValidateSet("stable", "beta")]
        [string]$Channel = "beta"
    )

    $repoRoot = Split-Path $PSScriptRoot -Parent | Split-Path -Parent
    $pluginsPath = Join-Path $repoRoot "plugins"

    if (-not (Test-Path $pluginsPath)) {
        throw "Plugins directory not found: $pluginsPath"
    }

    $pluginDirs = @()
    $runtimeDirs = Get-ChildItem -Path $pluginsPath -Directory | Where-Object { $_.Name -in @('cli', 'vscode') }
    foreach ($runtimeDir in $runtimeDirs) {
        $pluginDirs += Get-ChildItem -Path $runtimeDir.FullName -Directory | Where-Object {
            Test-Path (Join-Path $_.FullName "plugin.json")
        }
    }

    $allPluginDirs = @($pluginDirs)

    if ($Plugins) {
        $pluginList = @()
        foreach ($item in $Plugins) {
            $pluginList += @($item -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        }
        $pluginDirs = $pluginDirs | Where-Object {
            $dir = $_
            $pluginList | Where-Object { $dir.Name -like $_ } | Select-Object -First 1
        }
    }

    if ($pluginDirs.Count -eq 0) {
        Write-Host "No plugins found to build." -ForegroundColor Yellow
        return
    }

    Write-Host "Building $($pluginDirs.Count) plugin(s)..." -ForegroundColor Cyan

    Initialize-PluginBundleOutput -SelectedPluginDirs $pluginDirs -AllPluginDirs $allPluginDirs -Channel $Channel

    $built = 0
    $errors = 0
    foreach ($pluginDir in $pluginDirs) {
        $buildPath = Build-PluginBundle -PluginDir $pluginDir.FullName -Channel $Channel
        if ($buildPath) { $built++ } else { $errors++ }
    }

    Write-Host ""
    Write-Host "Build complete: $built built, $errors error(s)" -ForegroundColor Cyan
}

# Run standalone when invoked directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-PluginBuild -Plugins $Plugins -Channel $Channel
}
