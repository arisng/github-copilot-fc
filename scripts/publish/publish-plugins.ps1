param(
    [Parameter(Mandatory = $false)]
    [string[]]$Plugins,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$SkipWSL
)

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

        try {
            if ($Force) {
                Write-Host "  Uninstalling: $pluginName" -ForegroundColor DarkGray
                $uninstallOutput = & copilot plugin uninstall $pluginName 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "  Uninstall note: $pluginName may not have been installed ($uninstallOutput)" -ForegroundColor DarkGray
                }
            }

            Write-Host "  Installing: $pluginName" -ForegroundColor DarkGray
            & copilot plugin install $pluginPath
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
                    $wslPluginPath = Convert-ToWSLPath -Path $pluginDir.FullName

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
