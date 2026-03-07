<#
.SYNOPSIS
    Publishes Copilot plugins to CLI (Windows/WSL) and VS Code environments.

.DESCRIPTION
    Discovers plugin directories under plugins/cli/ and plugins/vscode/, builds a self-contained
    bundle for each, and installs based on the plugin's target runtime:

      - CLI plugins  (plugins/cli/):    installed via 'copilot plugin install'
      - VS Code plugins (plugins/vscode/): registered in VS Code's chat.plugins.paths setting

    Plugin directory structure:
      plugins/
        cli/           -- Plugins targeting GitHub Copilot CLI runtime
          ralph-v2/    -- plugin.json here
        vscode/        -- Plugins targeting VS Code Copilot runtime
          ralph-v2/    -- plugin.json here

        CLI install locations:
            This publisher stages local installs through a `local/<plugin-name>` source path so
            direct installs no longer land under `_direct/.build`. After install it also syncs a
            human-friendly mirror to `~/.copilot/installed-plugins/local/<PLUGIN-NAME>` on both
            Windows and WSL without moving the authoritative direct-install location.

    VS Code install: adds .build/ path to 'chat.plugins.paths' in user settings.json for
      both VS Code Stable and VS Code Insiders (whichever are present).
      See: https://code.visualstudio.com/docs/copilot/customization/agent-plugins

    NOTE: The -Environment parameter (windows/wsl/all) applies only to CLI plugins.
    VS Code plugins are always registered in settings.json regardless of -Environment.

.PARAMETER Plugins
    Array or comma-separated plugin names to install. Supports wildcard patterns.
    If omitted, installs all discovered plugins.

.PARAMETER Runtime
    Target runtime to publish. Valid values: 'cli', 'vscode', 'all'. Default: 'all'.
    - cli:    only publish CLI plugins (plugins/cli/)
    - vscode: only publish VS Code plugins (plugins/vscode/)
    - all:    publish plugins from both runtimes (default)

.PARAMETER Environment
    For CLI plugins only: target OS environment. Valid values: 'windows', 'wsl', 'all'. Default: 'all'.
    - windows: installs CLI plugin on Windows-native Copilot CLI only
    - wsl:     installs CLI plugin inside WSL only
    - all:     installs on both Windows and WSL
    Has no effect on VS Code plugins.
    NOTE: -SkipWSL is deprecated; use -Environment windows instead.

.PARAMETER Force
    For CLI plugins: uninstall each plugin before reinstalling.
    For VS Code plugins: overwrites any existing path entry (already idempotent).

.PARAMETER SkipWSL
    DEPRECATED. Use -Environment windows instead. Kept for backward compatibility.
    When used, emits a deprecation warning and sets Environment = 'windows'.
#>
param(
    [Parameter(Mandatory = $false)]
    [string[]]$Plugins,

    [Parameter(Mandatory = $false)]
    [ValidateSet("cli", "vscode", "all")]
    [string]$Runtime = "all",

    [Parameter(Mandatory = $false)]
    [ValidateSet("windows", "wsl", "all")]
    [string]$Environment = "all",

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$SkipWSL
)

# Deprecation handling for -SkipWSL
if ($SkipWSL) {
    Write-Warning "-SkipWSL is deprecated; use -Environment windows instead"
    $Environment = 'windows'
}

# Build functions (Merge-AgentInstructions, Build-PluginBundle, Invoke-PluginBuild)
# are defined in build-plugins.ps1. Dot-source to load without triggering standalone run.
. "$PSScriptRoot/build-plugins.ps1"
. "$PSScriptRoot/wsl-helpers.ps1"

function New-LocalPluginInstallSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BuildPath,
        [Parameter(Mandatory)][string]$PluginName
    )

    $pluginDir = Split-Path $BuildPath -Parent
    $installRoot = Join-Path $pluginDir '.install\local'
    $installPath = Join-Path $installRoot $PluginName

    if (Test-Path $installPath) {
        Remove-Item $installPath -Recurse -Force
    }

    New-Item -Path $installRoot -ItemType Directory -Force | Out-Null
    New-Item -Path $installPath -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Join-Path $BuildPath '*') -Destination $installPath -Recurse -Force
    return $installPath
}

function Sync-CopilotPluginInstallMirror {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InstalledPluginsRoot,
        [Parameter(Mandatory)][string]$PluginName,
        [switch]$UseWSL
    )

    if ($UseWSL) {
        $command = @"
mkdir -p '$InstalledPluginsRoot/local'
sourcePath=''
for candidate in '$InstalledPluginsRoot/_direct/$PluginName' '$InstalledPluginsRoot/_direct/.build'; do
  if [ -e "$candidate" ]; then
    sourcePath="$candidate"
    break
  fi
done

if [ -z "$sourcePath" ]; then
  exit 0
fi

targetPath='$InstalledPluginsRoot/local/$PluginName'
rm -rf "$targetPath"
cp -R "$sourcePath" "$targetPath"
"@
        Invoke-WSLCommand -Command $command -InitializeNode -SuppressStderr | Out-Null
        return
    }

    $localRoot = Join-Path $InstalledPluginsRoot 'local'
    $preferredPath = Join-Path $localRoot $PluginName
    $candidates = @(
        (Join-Path $InstalledPluginsRoot (Join-Path '_direct' $PluginName)),
        (Join-Path $InstalledPluginsRoot '_direct\.build')
    )

    $sourcePath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $sourcePath) {
        return
    }

    New-Item -Path $localRoot -ItemType Directory -Force | Out-Null
    if (Test-Path $preferredPath) {
        Remove-Item $preferredPath -Recurse -Force
    }

    Copy-Item -Path $sourcePath -Destination $preferredPath -Recurse -Force
}

function Update-VSCodePluginSettings {
    <#
    .SYNOPSIS
        Registers a plugin bundle path in VS Code's chat.plugins.paths setting.

    .DESCRIPTION
        Reads the VS Code user settings.json (for both Stable and Insiders installations),
        adds or updates the specified plugin path under 'chat.plugins.paths', and writes
        the result back. JSONC comments in settings.json are stripped during parsing;
        the file is rewritten as plain JSON.

        Supports: https://code.visualstudio.com/docs/copilot/customization/agent-plugins

    .PARAMETER PluginPath
        Absolute path to the plugin's .build/ directory to register.

    .PARAMETER PluginName
        Display name for log messages.

    .PARAMETER Enabled
        Whether to enable the plugin. Defaults to $true.

    .OUTPUTS
        [int] Number of VS Code settings files updated (0 if no VS Code installations found).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PluginPath,
        [Parameter(Mandatory)][string]$PluginName,
        [bool]$Enabled = $true
    )

    $settingsLocations = @(
        @{ Label = 'VS Code Stable';   Path = "$env:APPDATA\Code\User\settings.json" },
        @{ Label = 'VS Code Insiders'; Path = "$env:APPDATA\Code - Insiders\User\settings.json" }
    )

    $updated = 0

    foreach ($loc in $settingsLocations) {
        $settingsPath = $loc.Path
        if (-not (Test-Path $settingsPath)) { continue }

        $rawContent = Get-Content $settingsPath -Raw

        # Strip JSONC comments for parsing:
        #   - Full-line comments: lines whose non-whitespace content starts with //
        #   - Block comments: /* ... */
        #   - Trailing commas before } or ] (allowed in JSONC, not in JSON)
        # NOTE: This strips comments from the in-memory parse copy only.
        # The file is rewritten from the parsed+updated object (JSONC comments are not preserved).
        $jsonText = [regex]::Replace($rawContent, '(?m)^\s*//[^\n]*', '')
        $jsonText = [regex]::Replace($jsonText, '(?s)/\*.*?\*/', '')
        $jsonText = [regex]::Replace($jsonText, ',(?=\s*[\}\]])', '')

        try {
            $settings = $jsonText | ConvertFrom-Json
        }
        catch {
            Write-Warning "  Could not parse $($loc.Label) settings.json — skipping: $_"
            continue
        }

        # Get or create chat.plugins.paths as a PSCustomObject (VS Code expects an object, not array)
        $pathsProperty = $settings.PSObject.Properties['chat.plugins.paths']
        if ($null -ne $pathsProperty -and $pathsProperty.Value -is [PSCustomObject]) {
            $pathsObj = $pathsProperty.Value
        }
        else {
            $pathsObj = [PSCustomObject]@{}
        }

        # Add/update the plugin path entry. Use -InputObject (not pipeline) to safely handle
        # property names that contain special characters like backslashes and colons.
        Add-Member -InputObject $pathsObj -NotePropertyName $PluginPath -NotePropertyValue $Enabled -Force

        # Assign back (handles the case where chat.plugins.paths was missing or wrong type)
        Add-Member -InputObject $settings -NotePropertyName 'chat.plugins.paths' -NotePropertyValue $pathsObj -Force

        # Write back as clean JSON (JSONC comments are not preserved after rewrite)
        $newContent = $settings | ConvertTo-Json -Depth 20
        Set-Content -Path $settingsPath -Value $newContent -Encoding UTF8

        Write-Host "  Registered in $($loc.Label): $PluginName" -ForegroundColor Green
        Write-Host "    Path: $PluginPath" -ForegroundColor DarkGray
        $updated++
    }

    return $updated
}

function Publish-Plugins {
    <#
    .SYNOPSIS
        Discovers workspace plugins, bundles them, and installs based on each plugin's runtime:
          - CLI plugins:    installed via 'copilot plugin install' (respects -Environment)
          - VS Code plugins: registered in VS Code's chat.plugins.paths user setting

    .DESCRIPTION
        Scans plugins/cli/ and plugins/vscode/ for plugin directories containing plugin.json,
        creates a self-contained .build/ bundle for each (resolving component paths and copying
        artifacts), then installs by runtime:
          - cli:    runs 'copilot plugin install' on Windows and/or WSL per -Environment
          - vscode: calls Update-VSCodePluginSettings to register the .build/ path in
                    chat.plugins.paths for all installed VS Code variants (Stable + Insiders)

    .PARAMETER Plugins
        Array of plugin names to install. Supports comma-separated values and
        wildcard patterns. If omitted, installs all discovered plugins.

    .PARAMETER Runtime
        Filter by runtime ('cli', 'vscode', 'all'). Defaults to outer-scope $Runtime.

    .PARAMETER Force
        For CLI plugins: uninstall each plugin before reinstalling.
        For VS Code plugins: overwrites any existing path entry (already idempotent).

    .EXAMPLE
        Publish-Plugins
        Discovers and installs all plugins (CLI + VS Code) from the workspace.

    .EXAMPLE
        Publish-Plugins -Plugins ralph-v2 -Runtime vscode
        Registers only the 'ralph-v2' VS Code plugin in settings.json.

    .EXAMPLE
        Publish-Plugins -Runtime cli -Environment windows -Force
        Uninstalls and reinstalls all CLI plugins on Windows only.
    #>
    [CmdletBinding()]
    param()

    Write-Host "Publishing plugins..." -ForegroundColor Cyan

    $repoRoot = Split-Path $PSScriptRoot -Parent | Split-Path -Parent
    $pluginsPath = Join-Path $repoRoot "plugins"

    # Ensure plugins directory exists
    if (-not (Test-Path $pluginsPath)) {
        throw "Plugins directory not found: $pluginsPath"
    }

    # Discover plugins from runtime-specific subdirs: plugins/cli/ and plugins/vscode/
    # Each entry tracks the plugin directory and its target runtime.
    $pluginEntries = @()
    $runtimeDirs = Get-ChildItem -Path $pluginsPath -Directory | Where-Object { $_.Name -in @('cli', 'vscode') }
    foreach ($runtimeDir in $runtimeDirs) {
        $runtimeName = $runtimeDir.Name
        Get-ChildItem -Path $runtimeDir.FullName -Directory | Where-Object {
            Test-Path (Join-Path $_.FullName "plugin.json")
        } | ForEach-Object {
            $pluginEntries += [PSCustomObject]@{ Dir = $_; Runtime = $runtimeName }
        }
    }

    $allPluginEntries = @($pluginEntries)

    if ($pluginEntries.Count -eq 0) {
        Write-Host "No plugins found in: $pluginsPath" -ForegroundColor Yellow
        return
    }

    # Apply -Runtime filter
    if ($Runtime -ne 'all') {
        $pluginEntries = $pluginEntries | Where-Object { $_.Runtime -eq $Runtime }
        if ($pluginEntries.Count -eq 0) {
            Write-Host "No plugins found for runtime: $Runtime" -ForegroundColor Yellow
            return
        }
    }

    # Apply -Plugins name filter if specified
    if ($Plugins) {
        $pluginList = @()
        foreach ($item in $Plugins) {
            $pluginList += @($item -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        }
        $pluginEntries = $pluginEntries | Where-Object {
            $entry = $_
            $pluginList | Where-Object { $entry.Dir.Name -like $_ } | Select-Object -First 1
        }
        if ($pluginEntries.Count -eq 0) {
            Write-Host "Warning: No plugins found matching: $($pluginList -join ', ')" -ForegroundColor Yellow
            Write-Host "Available plugins:" -ForegroundColor Cyan
            $runtimeDirs | ForEach-Object {
                $rt = $_.Name
                Get-ChildItem -Path $_.FullName -Directory | Where-Object {
                    Test-Path (Join-Path $_.FullName "plugin.json")
                } | ForEach-Object { Write-Host "  - $($_.Name) ($rt)" }
            }
            return
        }
    }

    Write-Host "Discovered $($pluginEntries.Count) plugin(s)" -ForegroundColor Cyan

    Initialize-PluginBundleOutput -SelectedPluginDirs ($pluginEntries | ForEach-Object { $_.Dir }) -AllPluginDirs ($allPluginEntries | ForEach-Object { $_.Dir })

    # Pre-check WSL availability once (only needed for CLI plugins)
    $wslAvailable = $false
    $wslHome = $null
    $needsWsl = ($pluginEntries | Where-Object { $_.Runtime -eq 'cli' }).Count -gt 0 -and
                ($Environment -eq 'wsl' -or $Environment -eq 'all')
    if ($needsWsl) {
        $wslHelpersPath = Join-Path $PSScriptRoot "wsl-helpers.ps1"
        if (Test-Path $wslHelpersPath) {
            . $wslHelpersPath
            if (Test-WSLAvailable -WslHome ([ref]$wslHome)) {
                $wslAvailable = $true
                Write-Host "WSL detected at home: $wslHome" -ForegroundColor DarkGray
            }
            else {
                $msg = if ($Environment -eq 'wsl') { "WSL not available" } else { "WSL not available, skipping WSL installs" }
                Write-Host $msg -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "WSL helpers not found, skipping WSL publishing" -ForegroundColor Yellow
        }
    }

    $installed = 0
    $errors = 0

    foreach ($entry in $pluginEntries) {
        $pluginDir = $entry.Dir
        $pluginRuntime = $entry.Runtime
        $pluginName = $pluginDir.Name

        Write-Host ""
        Write-Host "[$pluginRuntime] $pluginName" -ForegroundColor Cyan

        # Build self-contained bundle
        $buildPath = Build-PluginBundle -PluginDir $pluginDir.FullName
        if (-not $buildPath) {
            Write-Error "  Bundle failed for $pluginName — skipping"
            $errors++
            continue
        }

        # --- VS Code: register in settings.json ---
        if ($pluginRuntime -eq 'vscode') {
            $registered = Update-VSCodePluginSettings -PluginPath $buildPath -PluginName $pluginName
            if ($registered -gt 0) {
                $installed++
            }
            else {
                Write-Warning "  No VS Code installations found — $pluginName not registered"
            }
            continue
        }

        # --- CLI: Windows install ---
        $installPath = New-LocalPluginInstallSource -BuildPath $buildPath -PluginName $pluginName

        if ($Environment -eq 'windows' -or $Environment -eq 'all') {
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
                    Sync-CopilotPluginInstallMirror -InstalledPluginsRoot (Join-Path $env:USERPROFILE '.copilot\installed-plugins') -PluginName $pluginName
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

        # --- CLI: WSL install ---
        if ($wslAvailable -and ($Environment -eq 'wsl' -or $Environment -eq 'all')) {
            $wslPluginPath = Convert-ToWSLPath -Path $installPath
            try {
                if ($Force) {
                    Write-Host "  WSL uninstalling: $pluginName" -ForegroundColor DarkGray
                    Invoke-WSLCommand -Command "copilot plugin uninstall '$pluginName'" -InitializeNode -SuppressStderr | Out-Null
                }

                Write-Host "  WSL installing: $pluginName" -ForegroundColor DarkGray
                Invoke-WSLCommand -Command "copilot plugin install '$wslPluginPath'" -InitializeNode | Out-Null

                if ($LASTEXITCODE -eq 0) {
                    Sync-CopilotPluginInstallMirror -InstalledPluginsRoot "$wslHome/.copilot/installed-plugins" -PluginName $pluginName -UseWSL
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

    Write-Host ""
    Write-Host "Done: $installed installed, $errors error(s)" -ForegroundColor Cyan
}

Publish-Plugins
