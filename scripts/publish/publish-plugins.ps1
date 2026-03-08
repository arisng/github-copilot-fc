<#
.SYNOPSIS
    Publishes Copilot plugins to CLI (Windows/WSL) and VS Code environments.

.DESCRIPTION
    Discovers plugin directories under plugins/cli/ and plugins/vscode/, builds a self-contained
    bundle for each, and installs based on the plugin's target runtime:

      - CLI plugins  (plugins/cli/):    copied directly into Copilot CLI's `_direct/<plugin-name>` install roots
      - VS Code plugins (plugins/vscode/): registered in VS Code's chat.plugins.paths setting

    Plugin directory structure:
      plugins/
        cli/           -- Plugins targeting GitHub Copilot CLI runtime
          ralph-v2/    -- plugin.json here
        vscode/        -- Plugins targeting VS Code Copilot runtime
          ralph-v2/    -- plugin.json here

        CLI install locations:
            This publisher copies the prepared runtime bundle from `plugins/cli/.build/<plugin-name>/`
            directly into `~/.copilot/installed-plugins/_direct/<plugin-name>/` on Windows and WSL/Linux.
            The destination is replaced exactly on each publish. The payload copy is verified, but
            raw `_direct` copies are still treated as a best-effort publish path because local probes
            have not proven that Copilot CLI discovers them the same way as `copilot plugin install`.

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
    Retained for backward compatibility. CLI publishing now performs exact replacement on every
    publish, so no explicit uninstall step is required. VS Code registration remains idempotent.

.PARAMETER SkipWSL
    DEPRECATED. Use -Environment windows instead. Kept for backward compatibility.
    When used, emits a deprecation warning and sets Environment = 'windows'.

.PARAMETER Channel
    Publishing channel: 'beta' (default) or 'stable'.
    - beta: builds to .build-beta/, installs to _direct/<name>-beta/ (CLI),
            registers .build-beta/ path in VS Code settings. Does not overwrite stable.
    - stable: standard publish to default locations.

.PARAMETER Promote
    Promotes the current beta build to stable. Copies .build-beta/ to .build/, then
    publishes as stable. Requires a prior beta build to exist.
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
    [ValidateSet("stable", "beta")]
    [string]$Channel = "beta",

    [Parameter(Mandatory = $false)]
    [switch]$Promote,

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

function Import-BuildPluginFunctions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScriptPath
    )

    if (-not (Test-Path $ScriptPath)) {
        throw "Build helper script not found: $ScriptPath"
    }

    $buildModule = New-Module -Name "copilot-build-plugins-$PID" -ScriptBlock {
        param([string]$InnerScriptPath)

        . $InnerScriptPath
        Export-ModuleMember -Function *
    } -ArgumentList $ScriptPath

    Import-Module $buildModule -Force -DisableNameChecking | Out-Null
}

Import-BuildPluginFunctions -ScriptPath (Join-Path $PSScriptRoot 'build-plugins.ps1')
. "$PSScriptRoot/wsl-helpers.ps1"

function Copy-DirectoryExact {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    $parentDir = Split-Path $Destination -Parent
    New-Item -Path $parentDir -ItemType Directory -Force | Out-Null

    if (Test-Path $Destination) {
        Remove-Item $Destination -Recurse -Force
    }

    Copy-Item -Path $Source -Destination $Destination -Recurse -Force
    return (Test-Path $Destination)
}

function Test-CopilotPluginDiscovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PluginName,
        [string]$InstalledPluginsRoot,
        [switch]$UseWSL
    )

    $listOutput = $null

    try {
        if ($UseWSL) {
            $listOutput = Invoke-WSLCommand -Command 'copilot plugin list' -InitializeNode -SuppressStderr
        }
        else {
            $listOutput = & copilot plugin list 2>$null
        }
    }
    catch {
        $listOutput = $null
    }

    $commandSucceeded = $LASTEXITCODE -eq 0 -and $null -ne $listOutput
    $detected = $false
    if ($commandSucceeded) {
        $escapedName = [regex]::Escape($PluginName)
        $detected = ($listOutput | Out-String) -match "(?im)^.*$escapedName.*$"
    }

    return [PSCustomObject]@{
        CommandSucceeded = $commandSucceeded
        Detected = $detected
        Output = ($listOutput | Out-String).Trim()
        InstalledPluginsRoot = $InstalledPluginsRoot
    }
}

function Install-CopilotPluginBundle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BuildPath,
        [Parameter(Mandatory)][string]$InstalledPluginsRoot,
        [Parameter(Mandatory)][string]$PluginName,
        [switch]$UseWSL
    )

    $destinationPath = if ($UseWSL) {
        "$InstalledPluginsRoot/_direct/$PluginName"
    }
    else {
        Join-Path (Join-Path $InstalledPluginsRoot '_direct') $PluginName
    }

    $copySucceeded = if ($UseWSL) {
        Copy-ToWSL -Source $BuildPath -Destination $destinationPath -Recurse
    }
    else {
        Copy-DirectoryExact -Source $BuildPath -Destination $destinationPath
    }

    $pluginJsonPath = if ($UseWSL) {
        "$destinationPath/plugin.json"
    }
    else {
        Join-Path $destinationPath 'plugin.json'
    }

    $destinationVerified = if ($UseWSL) {
        Test-WSLPathExists -Path $pluginJsonPath
    }
    else {
        Test-Path $pluginJsonPath
    }

    $discovery = Test-CopilotPluginDiscovery -PluginName $PluginName -InstalledPluginsRoot $InstalledPluginsRoot -UseWSL:$UseWSL

    return [PSCustomObject]@{
        CopySucceeded = $copySucceeded
        DestinationPath = $destinationPath
        DestinationVerified = $destinationVerified
        DiscoveryProbeSucceeded = $discovery.CommandSucceeded
        DiscoveryDetected = $discovery.Detected
        DiscoveryOutput = $discovery.Output
    }
}

function Write-CopilotDiscoveryRiskWarning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PluginName,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][bool]$DiscoveryProbeSucceeded,
        [Parameter(Mandatory)][bool]$DiscoveryDetected,
        [switch]$UseWSL
    )

    $scopeLabel = if ($UseWSL) { 'WSL' } else { 'Windows' }
    $probeLabel = if ($DiscoveryProbeSucceeded) {
        if ($DiscoveryDetected) {
            'copilot plugin list currently shows the plugin'
        }
        else {
            'copilot plugin list did not show the plugin after the raw copy'
        }
    }
    else {
        'copilot plugin list could not be verified in this environment'
    }

    Write-Warning "$scopeLabel direct-copy publish verified files at '$DestinationPath', but Copilot CLI discovery remains unproven. Local probes have not established that raw _direct copies are equivalent to 'copilot plugin install'; $probeLabel for '$PluginName'."
}

function Resolve-VSCodePluginRegistrationPath {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$PluginPath,
            [Parameter(Mandatory)][string]$PluginName
        )

        $resolvedPath = [System.IO.Path]::GetFullPath($PluginPath)

        if ((Split-Path $resolvedPath -Leaf) -ieq '.build') {
            $pluginDir = Split-Path $resolvedPath -Parent
            $runtimeDir = Split-Path $pluginDir -Parent
            if ((Split-Path $pluginDir -Leaf) -ieq $PluginName -and (Split-Path $runtimeDir -Leaf) -ieq 'vscode') {
                return (Join-Path (Join-Path $runtimeDir '.build') $PluginName)
            }
        }

        return $resolvedPath
    }

    function Get-VSCodePluginRegistrationIdentity {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$PluginPath
        )

        $resolvedPath = [System.IO.Path]::GetFullPath($PluginPath)
        $bundleRoot = Split-Path $resolvedPath -Parent
        $bundleFolderName = Split-Path $bundleRoot -Leaf
        $runtimeRoot = Split-Path $bundleRoot -Parent

        if (($bundleFolderName -ieq '.build' -or $bundleFolderName -ieq '.build-beta') -and (Split-Path $runtimeRoot -Leaf) -ieq 'vscode') {
            return [PSCustomObject]@{
                ResolvedPath = $resolvedPath
                RuntimeRoot = [System.IO.Path]::GetFullPath($runtimeRoot)
                SourcePluginName = Split-Path $resolvedPath -Leaf
            }
        }

        return [PSCustomObject]@{
            ResolvedPath = $resolvedPath
            RuntimeRoot = $null
            SourcePluginName = $null
        }
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

        $canonicalPluginPath = Resolve-VSCodePluginRegistrationPath -PluginPath $PluginPath -PluginName $PluginName
    $canonicalRegistration = Get-VSCodePluginRegistrationIdentity -PluginPath $canonicalPluginPath
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

            $stalePathEntries = @()
            foreach ($property in @($pathsObj.PSObject.Properties)) {
                $normalizedEntryPath = Resolve-VSCodePluginRegistrationPath -PluginPath $property.Name -PluginName $PluginName
                $entryRegistration = Get-VSCodePluginRegistrationIdentity -PluginPath $property.Name
                $isSamePluginRegistration =
                    $null -ne $canonicalRegistration.RuntimeRoot -and
                    $null -ne $entryRegistration.RuntimeRoot -and
                    $entryRegistration.RuntimeRoot -ieq $canonicalRegistration.RuntimeRoot -and
                    $entryRegistration.SourcePluginName -ieq $canonicalRegistration.SourcePluginName

                if (($normalizedEntryPath -ieq $canonicalPluginPath -or $isSamePluginRegistration) -and $property.Name -cne $canonicalPluginPath) {
                    $stalePathEntries += $property.Name
                }
            }

            foreach ($stalePath in $stalePathEntries) {
                $pathsObj.PSObject.Properties.Remove($stalePath)
            }

            # Add/update the plugin path entry. Use -InputObject (not pipeline) to safely handle
            # property names that contain special characters like backslashes and colons.
            Add-Member -InputObject $pathsObj -NotePropertyName $canonicalPluginPath -NotePropertyValue $Enabled -Force

            # Assign back (handles the case where chat.plugins.paths was missing or wrong type)
            Add-Member -InputObject $settings -NotePropertyName 'chat.plugins.paths' -NotePropertyValue $pathsObj -Force

            # Write back as clean JSON (JSONC comments are not preserved after rewrite)
            $newContent = $settings | ConvertTo-Json -Depth 20
            Set-Content -Path $settingsPath -Value $newContent -Encoding UTF8

            Write-Host "  Registered in $($loc.Label): $PluginName" -ForegroundColor Green
            Write-Host "    Path: $canonicalPluginPath" -ForegroundColor DarkGray
            $updated++
        }

    return $updated
}

function Publish-Plugins {
    <#
    .SYNOPSIS
        Discovers workspace plugins, bundles them, and installs based on each plugin's runtime:
                    - CLI plugins:    copied directly into Copilot CLI `_direct/<plugin-name>` install roots (respects -Environment)
          - VS Code plugins: registered in VS Code's chat.plugins.paths user setting

    .DESCRIPTION
        Scans plugins/cli/ and plugins/vscode/ for plugin directories containing plugin.json,
        creates a self-contained .build/ bundle for each (resolving component paths and copying
        artifacts), then installs by runtime:
                    - cli:    copies the bundle into `~/.copilot/installed-plugins/_direct/<plugin-name>/`
                                        on Windows and/or WSL per -Environment, verifies the destination payload,
                                        and warns that Copilot CLI discovery parity with `copilot plugin install`
                                        is still unproven
          - vscode: calls Update-VSCodePluginSettings to register the .build/ path in
                    chat.plugins.paths for all installed VS Code variants (Stable + Insiders)

    .PARAMETER Plugins
        Array of plugin names to install. Supports comma-separated values and
        wildcard patterns. If omitted, installs all discovered plugins.

    .PARAMETER Runtime
        Filter by runtime ('cli', 'vscode', 'all'). Defaults to outer-scope $Runtime.

    .PARAMETER Force
        Retained for backward compatibility. CLI publishing now replaces the target `_direct`
        directory exactly on every publish, so no uninstall step is needed.

    .EXAMPLE
        Publish-Plugins
        Discovers and installs all plugins (CLI + VS Code) from the workspace.

    .EXAMPLE
        Publish-Plugins -Plugins ralph-v2 -Runtime vscode
        Registers only the 'ralph-v2' VS Code plugin in settings.json.

    .EXAMPLE
        Publish-Plugins -Runtime cli -Environment windows -Force
        Replaces all CLI plugin payloads under the Windows `_direct` install root.
    #>
    [CmdletBinding()]
    param()

    $channelLabel = if ($Channel -eq 'beta') { ' [BETA]' } else { '' }
    Write-Host "Publishing plugins${channelLabel}..." -ForegroundColor Cyan

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

    # Determine effective channel
    $effectiveChannel = $Channel

    Initialize-PluginBundleOutput -SelectedPluginDirs ($pluginEntries | ForEach-Object { $_.Dir }) -AllPluginDirs ($allPluginEntries | ForEach-Object { $_.Dir }) -Channel $effectiveChannel

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
        $buildPath = Build-PluginBundle -PluginDir $pluginDir.FullName -Channel $effectiveChannel
        if (-not $buildPath) {
            Write-Error "  Bundle failed for $pluginName — skipping"
            $errors++
            continue
        }

        # For beta channel, the install name is suffixed
        $installName = if ($effectiveChannel -eq 'beta') { "$pluginName-beta" } else { $pluginName }

        # --- VS Code: register in settings.json ---
        if ($pluginRuntime -eq 'vscode') {
            $registered = Update-VSCodePluginSettings -PluginPath $buildPath -PluginName $installName
            if ($registered -gt 0) {
                $installed++
            }
            else {
                Write-Warning "  No VS Code installations found — $pluginName not registered"
            }
            continue
        }

        # --- CLI: Windows direct-copy install ---
        if ($Environment -eq 'windows' -or $Environment -eq 'all') {
            try {
                $windowsInstall = Install-CopilotPluginBundle -BuildPath $buildPath -InstalledPluginsRoot (Join-Path $env:USERPROFILE '.copilot\installed-plugins') -PluginName $installName

                if ($windowsInstall.CopySucceeded -and $windowsInstall.DestinationVerified) {
                    Write-Host "  Copied to: $($windowsInstall.DestinationPath)" -ForegroundColor Green
                    Write-CopilotDiscoveryRiskWarning -PluginName $installName -DestinationPath $windowsInstall.DestinationPath -DiscoveryProbeSucceeded $windowsInstall.DiscoveryProbeSucceeded -DiscoveryDetected $windowsInstall.DiscoveryDetected
                    $installed++
                }
                else {
                    Write-Error "  Failed to publish direct-copy payload for $installName to $($windowsInstall.DestinationPath)"
                    $errors++
                }
            }
            catch {
                Write-Error "  Failed to publish $installName to the Windows direct-install root: $_"
                $errors++
            }
        }

        # --- CLI: WSL direct-copy install ---
        if ($wslAvailable -and ($Environment -eq 'wsl' -or $Environment -eq 'all')) {
            try {
                $wslInstall = Install-CopilotPluginBundle -BuildPath $buildPath -InstalledPluginsRoot "$wslHome/.copilot/installed-plugins" -PluginName $installName -UseWSL

                if ($wslInstall.CopySucceeded -and $wslInstall.DestinationVerified) {
                    Write-Host "  WSL copied to: $($wslInstall.DestinationPath)" -ForegroundColor Green
                    Write-CopilotDiscoveryRiskWarning -PluginName $installName -DestinationPath $wslInstall.DestinationPath -DiscoveryProbeSucceeded $wslInstall.DiscoveryProbeSucceeded -DiscoveryDetected $wslInstall.DiscoveryDetected -UseWSL
                    $installed++
                }
                else {
                    Write-Error "  WSL failed to publish direct-copy payload for $installName to $($wslInstall.DestinationPath)"
                    $errors++
                }
            }
            catch {
                Write-Error "  WSL failed to publish $installName to the direct-install root: $_"
                $errors++
            }
        }
    }

    Write-Host ""
    $channelLabel = if ($effectiveChannel -eq 'beta') { ' (beta)' } else { '' }
    Write-Host "Done${channelLabel}: $installed installed, $errors error(s)" -ForegroundColor Cyan
}

function Promote-BetaToStable {
    <#
    .SYNOPSIS
        Promotes beta plugin builds to stable by rebuilding as stable and publishing.

    .DESCRIPTION
        Verifies that .build-beta/ bundles exist for the requested plugins, then
        triggers a full stable build + publish from the same source. This ensures
        the stable bundle is built fresh (not just copied), so manifest names and
        paths are correct for the stable channel.
    #>
    [CmdletBinding()]
    param()

    Write-Host "Promoting beta builds to stable..." -ForegroundColor Cyan

    $repoRoot = Split-Path $PSScriptRoot -Parent | Split-Path -Parent
    $pluginsPath = Join-Path $repoRoot "plugins"

    # Discover plugins that have beta builds
    $promoted = 0
    foreach ($runtimeName in @('cli', 'vscode')) {
        $betaBuildRoot = Join-Path $pluginsPath "$runtimeName/.build-beta"
        if (-not (Test-Path $betaBuildRoot)) { continue }

        $betaPlugins = Get-ChildItem -Path $betaBuildRoot -Directory
        foreach ($betaPlugin in $betaPlugins) {
            $pluginName = $betaPlugin.Name
            $sourceDir = Join-Path $pluginsPath "$runtimeName/$pluginName"

            if (-not (Test-Path (Join-Path $sourceDir "plugin.json"))) {
                Write-Warning "  Source plugin not found for beta build: $pluginName ($runtimeName)"
                continue
            }

            # Apply -Plugins filter if specified
            if ($Plugins) {
                $pluginList = @()
                foreach ($item in $Plugins) {
                    $pluginList += @($item -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
                }
                $matched = $pluginList | Where-Object { $pluginName -like $_ } | Select-Object -First 1
                if (-not $matched) { continue }
            }

            Write-Host "  [$runtimeName] Promoting $pluginName from beta -> stable" -ForegroundColor Green
            $promoted++
        }
    }

    if ($promoted -eq 0) {
        Write-Host "No beta builds found to promote." -ForegroundColor Yellow
        return
    }

    # Run a standard stable publish (Channel = stable will rebuild from source into .build/)
    $script:Channel = 'stable'
    Publish-Plugins
}

if ($Promote) {
    Promote-BetaToStable
}
else {
    Publish-Plugins
}
