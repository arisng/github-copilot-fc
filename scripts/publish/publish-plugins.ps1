param(
    [Parameter(Mandatory = $false)]
    [string[]]$Plugins,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$SkipWSL,

    [Parameter(Mandatory = $false)]
    [switch]$Bundle
)

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
        Discovers workspace plugins and installs them via copilot plugin install.

    .DESCRIPTION
        Scans the plugins/ directory for subdirectories containing plugin.json,
        then runs 'copilot plugin install' for each discovered plugin. Supports
        filtering by name, force reinstallation, and WSL cross-publishing.

    .PARAMETER Plugins
        Array of plugin names to install. Supports comma-separated values and
        wildcard patterns. If omitted, installs all discovered plugins.

    .PARAMETER Force
        Uninstall each plugin before reinstalling.

    .PARAMETER SkipWSL
        Skip plugin installation in WSL (Windows-only mode).

    .PARAMETER Bundle
        Create a self-contained .build/ directory for each plugin before install.
        Resolves component paths, copies artifacts, and rewrites plugin.json with
        local paths. Installs from .build/ instead of the source directory.

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

    .EXAMPLE
        Publish-Plugins -Bundle
        Bundles each plugin into .build/ and installs from there.
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

        # Bundle mode: build self-contained directory first
        if ($Bundle) {
            $buildPath = Build-PluginBundle -PluginDir $pluginPath
            if (-not $buildPath) {
                Write-Error "  Bundle failed for $pluginName — skipping install"
                $errors++
                continue
            }
            $installPath = $buildPath
        }
        else {
            $installPath = $pluginPath
        }

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
                    $wslInstallDir = if ($Bundle) {
                        Join-Path $pluginDir.FullName ".build"
                    } else {
                        $pluginDir.FullName
                    }
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
