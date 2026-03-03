param(
    [Parameter(Mandatory = $false)]
    [string[]]$Plugins,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$SkipWSL
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
            @{ Name = 'Signal Protocol';  Pattern = 'Live Signals Protocol|Poll-Signals Routine' },
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

function Build-PluginBundle {
    <#
    .SYNOPSIS
        Creates a self-contained build directory for a plugin.

    .DESCRIPTION
        Parses plugin.json, resolves all component path fields, copies referenced
        artifacts into a .build/ directory, and rewrites plugin.json with local paths.
        Only official schema fields are retained in the output manifest.

    .PARAMETER PluginDir
        Full path to the plugin source directory containing plugin.json.

    .OUTPUTS
        [string] Path to the .build/ directory on success, $null on failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PluginDir
    )

    $officialComponentFields = @('agents', 'skills', 'commands', 'hooks', 'mcpServers', 'lspServers')
    $officialMetadataFields = @('name', 'description', 'version', 'author', 'license', 'homepage', 'bugs', 'repository', 'keywords', 'strict')

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

    $pluginName = $manifest.name
    $buildDir = Join-Path $PluginDir ".build"

    # Clean and create .build/ directory
    if (Test-Path $buildDir) {
        Remove-Item $buildDir -Recurse -Force
    }
    New-Item -Path $buildDir -ItemType Directory -Force | Out-Null

    Write-Host "  Bundling: $pluginName -> .build/" -ForegroundColor DarkGray

    # Build a clean manifest with only official fields
    $cleanManifest = [ordered]@{}

    # Copy metadata fields
    foreach ($field in $officialMetadataFields) {
        $value = $manifest.PSObject.Properties[$field]
        if ($null -ne $value) {
            $cleanManifest[$field] = $value.Value
        }
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
                $targetPath = Join-Path $componentBuildDir $itemName

                Copy-Item -Path $resolvedSource -Destination $targetPath -Recurse -Force
                $localPaths += "$field/$itemName/"
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
            $cleanManifest[$field] = "$field/"
        }
    }

    # Write cleaned manifest
    $cleanManifest | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $buildDir "plugin.json") -Encoding UTF8

    # Merge agent instructions (embed instruction content into agent bodies)
    if ($cleanManifest.Contains('agents')) {
        $agentBuildDir = Join-Path $buildDir "agents"
        $repoRoot = Split-Path $PSScriptRoot -Parent | Split-Path -Parent
        $instructionsDir = Join-Path $repoRoot "instructions"

        if (Test-Path $agentBuildDir) {
            $mergeResult = Merge-AgentInstructions -AgentDir $agentBuildDir -InstructionsDir $instructionsDir
            if ($mergeResult.Errors -gt 0) {
                Write-Warning "  Agent instruction merge had $($mergeResult.Errors) error(s)"
            }
            Write-Host "  Merged instructions: $($mergeResult.Merged) agent(s), $($mergeResult.Skipped) skipped, $($mergeResult.Errors) error(s)" -ForegroundColor DarkGray
        }
    }

    # Post-bundle validation: verify every component path in .build/plugin.json
    foreach ($field in $officialComponentFields) {
        if (-not $cleanManifest.Contains($field)) { continue }

        $fieldValue = $cleanManifest[$field]
        $paths = if ($fieldValue -is [System.Array]) { $fieldValue } else { @($fieldValue) }

        foreach ($p in $paths) {
            $checkPath = Join-Path $buildDir $p
            if (-not (Test-Path $checkPath)) {
                $validationErrors += "$field`: $p (missing in .build/)"
            }
        }
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

function Publish-Plugins {
    <#
    .SYNOPSIS
        Discovers workspace plugins, bundles them, and installs via copilot plugin install.

    .DESCRIPTION
        Scans the plugins/ directory for subdirectories containing plugin.json.
        By default, creates a self-contained .build/ bundle for each plugin
        (resolving component paths and copying artifacts) before running
        'copilot plugin install'.
        Supports filtering by name, force reinstallation, and WSL cross-publishing.

    .PARAMETER Plugins
        Array of plugin names to install. Supports comma-separated values and
        wildcard patterns. If omitted, installs all discovered plugins.

    .PARAMETER Force
        Uninstall each plugin before reinstalling.

    .PARAMETER SkipWSL
        Skip plugin installation in WSL (Windows-only mode).

    .EXAMPLE
        Publish-Plugins
        Discovers and installs all plugins from the workspace.

    .EXAMPLE
        Publish-Plugins -Plugins ralph-v2
        Installs only the 'ralph-v2' plugin.

    .EXAMPLE
        Publish-Plugins -Force
        Uninstalls and reinstalls all plugins.

    .EXAMPLE
        Publish-Plugins -SkipWSL
        Installs plugins on Windows only, skipping WSL.
    #>
    [CmdletBinding()]
    param()

    Write-Host "Publishing plugins via copilot plugin install..." -ForegroundColor Cyan

    $repoRoot = Split-Path $PSScriptRoot -Parent | Split-Path -Parent
    $pluginsPath = Join-Path $repoRoot "plugins"

    # Ensure plugins directory exists
    if (-not (Test-Path $pluginsPath)) {
        throw "Plugins directory not found: $pluginsPath"
    }

    # Discover plugins: directories containing plugin.json
    $pluginDirs = Get-ChildItem -Path $pluginsPath -Directory | Where-Object {
        Test-Path (Join-Path $_.FullName "plugin.json")
    }

    if ($pluginDirs.Count -eq 0) {
        Write-Host "No plugins found in: $pluginsPath" -ForegroundColor Yellow
        return
    }

    # Apply name filter if specified
    if ($Plugins) {
        $pluginList = @()
        foreach ($item in $Plugins) {
            $pluginList += @($item -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        }
        $pluginDirs = $pluginDirs | Where-Object {
            $dir = $_
            $pluginList | Where-Object { $dir.Name -like $_ } | Select-Object -First 1
        }
        if ($pluginDirs.Count -eq 0) {
            Write-Host "Warning: No plugins found matching: $($pluginList -join ', ')" -ForegroundColor Yellow
            Write-Host "Available plugins:" -ForegroundColor Cyan
            Get-ChildItem -Path $pluginsPath -Directory | Where-Object {
                Test-Path (Join-Path $_.FullName "plugin.json")
            } | ForEach-Object { Write-Host "  - $($_.Name)" }
            return
        }
    }

    Write-Host "Discovered $($pluginDirs.Count) plugin(s)" -ForegroundColor Cyan

    $installed = 0
    $errors = 0

    # --- Windows installation ---
    foreach ($pluginDir in $pluginDirs) {
        $pluginName = $pluginDir.Name
        $pluginPath = $pluginDir.FullName

        $buildPath = Build-PluginBundle -PluginDir $pluginPath
        if (-not $buildPath) {
            Write-Error "  Bundle failed for $pluginName — skipping install"
            $errors++
            continue
        }
        $installPath = $buildPath

        try {
            if ($Force) {
                Write-Host "  Uninstalling: $pluginName" -ForegroundColor DarkGray
                $uninstallOutput = & copilot plugin uninstall $pluginName 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "  Uninstall note: $pluginName may not have been installed ($uninstallOutput)" -ForegroundColor DarkGray
                }
            }

            Write-Host "  Installing: $pluginName" -ForegroundColor DarkGray
            & copilot plugin install $installPath
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Installed: $pluginName" -ForegroundColor Green
                $installed++
            }
            else {
                Write-Error "  Failed to install: $pluginName (exit code $LASTEXITCODE)"
                $errors++
            }
        }
        catch {
            Write-Error "  Failed to install $pluginName : $_"
            $errors++
        }
    }

    # --- WSL installation ---
    if (-not $SkipWSL) {
        $wslHelpersPath = Join-Path $PSScriptRoot "wsl-helpers.ps1"
        $wslAvailable = $false

        if (Test-Path $wslHelpersPath) {
            . $wslHelpersPath

            $wslHome = $null
            if (Test-WSLAvailable -WslHome ([ref]$wslHome)) {
                $wslAvailable = $true
                Write-Host "WSL detected at home: $wslHome" -ForegroundColor DarkGray

                foreach ($pluginDir in $pluginDirs) {
                    $pluginName = $pluginDir.Name
                    $wslInstallDir = Join-Path $pluginDir.FullName ".build"
                    $wslPluginPath = Convert-ToWSLPath -Path $wslInstallDir

                    try {
                        if ($Force) {
                            Write-Host "  WSL uninstalling: $pluginName" -ForegroundColor DarkGray
                            wsl bash -c "copilot plugin uninstall '$pluginName'" 2>$null
                        }

                        Write-Host "  WSL installing: $pluginName" -ForegroundColor DarkGray
                        wsl bash -c "copilot plugin install '$wslPluginPath'"

                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "  WSL installed: $pluginName" -ForegroundColor Green
                            $installed++
                        }
                        else {
                            Write-Error "  WSL failed to install: $pluginName (exit code $LASTEXITCODE)"
                            $errors++
                        }
                    }
                    catch {
                        Write-Error "  WSL failed to install $pluginName : $_"
                        $errors++
                    }
                }
            }
        }

        if (-not $wslAvailable -and -not (Test-Path $wslHelpersPath)) {
            Write-Host "WSL helpers not found, skipping WSL publishing" -ForegroundColor Yellow
        }
        elseif (-not $wslAvailable) {
            Write-Host "WSL not available, skipping WSL publishing" -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "Done: $installed installed, $errors error(s)" -ForegroundColor Cyan
}

Publish-Plugins
