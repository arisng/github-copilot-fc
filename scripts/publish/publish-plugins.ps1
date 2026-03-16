<#
.SYNOPSIS
    Publishes Copilot plugins to CLI (Windows/WSL) and VS Code environments.

.DESCRIPTION
    Discovers plugin directories under plugins/cli/ and plugins/vscode/, builds a self-contained
    bundle for each, and installs based on the plugin's target runtime:

      - CLI plugins  (plugins/cli/):    installed with `copilot plugin install <local-bundle-path>`
                                        against the prepared workspace bundle
      - VS Code plugins (plugins/vscode/): copied into VS Code's user-data agentPlugins roots
                                          and registered in chat.plugins.paths

    Plugin directory structure:
      plugins/
        cli/           -- Plugins targeting GitHub Copilot CLI runtime
          ralph-v2/    -- plugin.json here
        vscode/        -- Plugins targeting VS Code Copilot runtime
          ralph-v2/    -- plugin.json here

        CLI install flow:
            This publisher builds the prepared runtime bundle under
            `plugins/cli/.build/<plugin-name>/`, then invokes
            `copilot plugin install <local-bundle-path>` on Windows and WSL/Linux.
            Copilot CLI manages the installed payload in its own cache; treat any
            resulting on-disk install path as an implementation detail.

    VS Code install: copies the prepared runtime bundle from `plugins/vscode/.build/<plugin-name>/`
      into each detected VS Code user-data `agentPlugins/<plugin-name>/` root (Stable and/or
      Insiders), then registers the copied path in that installation's user settings.json.
      See: https://code.visualstudio.com/docs/copilot/customization/agent-plugins

    NOTE: The -Environment parameter (windows/wsl/all) applies only to CLI plugins.
    VS Code plugins are always published into Windows user-data folders and registered in
    settings.json regardless of -Environment.

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
    - all:     installs on both Windows and WSL when available; missing WSL support is warned and skipped
    Has no effect on VS Code plugins.
    NOTE: -SkipWSL is deprecated; use -Environment windows instead.

.PARAMETER Force
    Retained for backward compatibility. CLI publishing now reruns `copilot plugin install`
    from the prepared local bundle on every publish, so no explicit uninstall step is required.
    VS Code publish + registration remains idempotent.

.PARAMETER SkipWSL
    DEPRECATED. Use -Environment windows instead. Kept for backward compatibility.
    When used, emits a deprecation warning and sets Environment = 'windows'.

.PARAMETER Channel
    Publishing channel: 'beta' (default) or 'stable'.
    - beta: builds to .build/<name>-beta/, installs the beta bundle via `copilot plugin install`
            for CLI, copies to agentPlugins/<name>-beta/ for VS Code, and does not overwrite stable.
    - stable: standard publish to default locations.

.PARAMETER Promote
    Promotes the current beta build to stable by verifying a beta bundle exists under
    .build/<name>-beta/, then rebuilding and publishing as stable.
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

function Get-VSCodeInstallationLocations {
    [CmdletBinding()]
    param()

    $locations = @(
        [PSCustomObject]@{
            Label = 'VS Code Stable'
            AppDataRoot = Join-Path $env:APPDATA 'Code'
            SettingsPath = Join-Path $env:APPDATA 'Code\User\settings.json'
            AgentPluginsRoot = Join-Path $env:APPDATA 'Code\agentPlugins'
        },
        [PSCustomObject]@{
            Label = 'VS Code Insiders'
            AppDataRoot = Join-Path $env:APPDATA 'Code - Insiders'
            SettingsPath = Join-Path $env:APPDATA 'Code - Insiders\User\settings.json'
            AgentPluginsRoot = Join-Path $env:APPDATA 'Code - Insiders\agentPlugins'
        }
    )

    return @(
        $locations | Where-Object {
            (Test-Path $_.AppDataRoot -PathType Container) -or
            (Test-Path $_.SettingsPath -PathType Leaf) -or
            (Test-Path $_.AgentPluginsRoot -PathType Container)
        }
    )
}

function Test-CopilotPluginDiscovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PluginName,
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
    }
}

function Install-CopilotPluginBundle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BuildPath,
        [Parameter(Mandatory)][string]$PluginName,
        [switch]$UseWSL
    )

    $resolvedBuildPath = [System.IO.Path]::GetFullPath($BuildPath)
    $pluginJsonPath = Join-Path $resolvedBuildPath 'plugin.json'
    if (-not (Test-Path $pluginJsonPath -PathType Leaf)) {
        throw "Built plugin manifest not found: $pluginJsonPath"
    }

    $installOutput = $null
    $installException = $null
    $exitCode = 1

    try {
        if ($UseWSL) {
            $wslBuildPath = Convert-ToWSLPath -Path $resolvedBuildPath
            $installOutput = Invoke-WSLCommand -Command "copilot plugin install '$wslBuildPath' 2>&1" -InitializeNode
        }
        else {
            $installOutput = & copilot plugin install $resolvedBuildPath 2>&1
        }

        $exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    }
    catch {
        $installException = $_
        if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            $exitCode = $LASTEXITCODE
        }
    }

    $commandSucceeded = $exitCode -eq 0
    $discovery = $null
    if ($commandSucceeded) {
        $discovery = Test-CopilotPluginDiscovery -PluginName $PluginName -UseWSL:$UseWSL
    }

    return [PSCustomObject]@{
        InstallSucceeded = $commandSucceeded
        InstallSourcePath = if ($UseWSL) { $wslBuildPath } else { $resolvedBuildPath }
        ExitCode = $exitCode
        InstallOutput = ($installOutput | Out-String).Trim()
        InstallException = if ($null -ne $installException) { $installException.ToString() } else { $null }
        DiscoveryProbeSucceeded = if ($null -ne $discovery) { $discovery.CommandSucceeded } else { $false }
        DiscoveryDetected = if ($null -ne $discovery) { $discovery.Detected } else { $false }
        DiscoveryOutput = if ($null -ne $discovery) { $discovery.Output } else { '' }
    }
}

function Write-CopilotPluginVerificationWarning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PluginName,
        [Parameter(Mandatory)][bool]$DiscoveryProbeSucceeded,
        [Parameter(Mandatory)][bool]$DiscoveryDetected,
        [switch]$UseWSL
    )

    if ($DiscoveryProbeSucceeded -and $DiscoveryDetected) {
        return
    }

    $scopeLabel = if ($UseWSL) { 'WSL' } else { 'Windows' }
    $message = if ($DiscoveryProbeSucceeded) {
        "  $scopeLabel install completed, but `copilot plugin list` did not show '$PluginName'."
    }
    else {
        "  $scopeLabel install completed, but `copilot plugin list` could not be verified for '$PluginName' in this environment."
    }

    Write-Warning $message
}

function Resolve-VSCodePluginRegistrationPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PluginPath,
        [Parameter(Mandatory)][string]$PluginName
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($PluginPath)
    $leaf = Split-Path $resolvedPath -Leaf

    if ($leaf -ieq '.build' -or $leaf -ieq '.build-beta' -or $leaf -ieq 'agentPlugins') {
        return [System.IO.Path]::GetFullPath((Join-Path $resolvedPath $PluginName))
    }

    return $resolvedPath
}

function Get-VSCodePluginRegistrationIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PluginPath
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($PluginPath)
    $containerPath = Split-Path $resolvedPath -Parent
    $containerName = Split-Path $containerPath -Leaf
    $pluginFolderName = Split-Path $resolvedPath -Leaf
    $rootPath = if ([string]::IsNullOrWhiteSpace($containerPath)) { $null } else { Split-Path $containerPath -Parent }

    if (($containerName -ieq '.build' -or $containerName -ieq '.build-beta') -and (Split-Path $rootPath -Leaf) -ieq 'vscode') {
        $effectivePluginName = if ($containerName -ieq '.build-beta' -and $pluginFolderName -notmatch '-beta$') {
            "$pluginFolderName-beta"
        }
        else {
            $pluginFolderName
        }

        return [PSCustomObject]@{
            ResolvedPath = $resolvedPath
            RegistrationRoot = [System.IO.Path]::GetFullPath($containerPath)
            SourcePluginName = $pluginFolderName
            EffectivePluginName = $effectivePluginName
            RegistrationType = 'workspace-build'
        }
    }

    if ($containerName -ieq 'agentPlugins') {
        return [PSCustomObject]@{
            ResolvedPath = $resolvedPath
            RegistrationRoot = [System.IO.Path]::GetFullPath($containerPath)
            SourcePluginName = $pluginFolderName
            EffectivePluginName = $pluginFolderName
            RegistrationType = 'vscode-agentPlugins'
        }
    }

    return [PSCustomObject]@{
        ResolvedPath = $resolvedPath
        RegistrationRoot = if ([string]::IsNullOrWhiteSpace($containerPath)) { $null } else { [System.IO.Path]::GetFullPath($containerPath) }
        SourcePluginName = $pluginFolderName
        EffectivePluginName = $pluginFolderName
        RegistrationType = 'path'
    }
}

function Update-VSCodePluginSettings {
    <#
    .SYNOPSIS
        Publishes VS Code plugin bundles into user-data agentPlugins roots and registers them.

    .DESCRIPTION
        For each detected VS Code installation (Stable and/or Insiders), copies the specified
        plugin bundle into that installation's user-data `agentPlugins/<plugin-name>/` folder,
        then adds or updates the copied path under `chat.plugins.paths` in the matching
        user settings.json file. JSONC comments in settings.json are stripped during parsing;
        the file is rewritten as plain JSON.

        Supports: https://code.visualstudio.com/docs/copilot/customization/agent-plugins

    .PARAMETER PluginPath
        Absolute path to the built plugin bundle directory to publish.

    .PARAMETER PluginName
        Display name for log messages and the published bundle directory name.

    .PARAMETER Enabled
        Whether to enable the plugin. Defaults to $true.

    .OUTPUTS
        [pscustomobject] Publish + registration summary for the detected VS Code installations.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PluginPath,
        [Parameter(Mandatory)][string]$PluginName,
        [bool]$Enabled = $true
    )

    $installLocations = @(Get-VSCodeInstallationLocations)
    $result = [PSCustomObject]@{
        LocationsDiscovered = $installLocations.Count
        Published = 0
        Registered = 0
        Errors = 0
    }

    foreach ($loc in $installLocations) {
        $publishedPluginPath = Join-Path $loc.AgentPluginsRoot $PluginName
        $canonicalPluginPath = Resolve-VSCodePluginRegistrationPath -PluginPath $publishedPluginPath -PluginName $PluginName
        $canonicalRegistration = Get-VSCodePluginRegistrationIdentity -PluginPath $canonicalPluginPath

        try {
            New-Item -Path $loc.AgentPluginsRoot -ItemType Directory -Force | Out-Null
            $copySucceeded = Copy-DirectoryExact -Source $PluginPath -Destination $canonicalPluginPath
            $pluginJsonPath = Join-Path $canonicalPluginPath 'plugin.json'
            if (-not $copySucceeded -or -not (Test-Path $pluginJsonPath -PathType Leaf)) {
                Write-Error "  Failed to publish $PluginName to $($loc.Label) agentPlugins root: $canonicalPluginPath"
                $result.Errors++
                continue
            }

            Write-Host "  Published to $($loc.Label): $PluginName" -ForegroundColor Green
            Write-Host "    Path: $canonicalPluginPath" -ForegroundColor DarkGray
            $result.Published++
        }
        catch {
            Write-Error "  Failed to copy $PluginName into $($loc.Label) agentPlugins root: $_"
            $result.Errors++
            continue
        }

        $settingsDir = Split-Path $loc.SettingsPath -Parent
        New-Item -Path $settingsDir -ItemType Directory -Force | Out-Null

        if (Test-Path $loc.SettingsPath -PathType Leaf) {
            $rawContent = Get-Content $loc.SettingsPath -Raw

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
                Write-Warning "  Could not parse $($loc.Label) settings.json — skipping registration: $_"
                $result.Errors++
                continue
            }
        }
        else {
            $settings = [PSCustomObject]@{}
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
                -not [string]::IsNullOrWhiteSpace($canonicalRegistration.EffectivePluginName) -and
                -not [string]::IsNullOrWhiteSpace($entryRegistration.EffectivePluginName) -and
                $entryRegistration.EffectivePluginName -ieq $canonicalRegistration.EffectivePluginName

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
        Set-Content -Path $loc.SettingsPath -Value $newContent -Encoding UTF8

        Write-Host "  Registered in $($loc.Label): $PluginName" -ForegroundColor Green
        Write-Host "    Settings: $($loc.SettingsPath)" -ForegroundColor DarkGray
        $result.Registered++
    }

    return $result
}

function Publish-Plugins {
    <#
    .SYNOPSIS
        Discovers workspace plugins, bundles them, and installs based on each plugin's runtime:
                    - CLI plugins:    installed with `copilot plugin install <local-bundle-path>` (respects -Environment)
          - VS Code plugins: copied into VS Code user-data agentPlugins roots and registered
                            in the matching chat.plugins.paths user setting

    .DESCRIPTION
        Scans plugins/cli/ and plugins/vscode/ for plugin directories containing plugin.json,
        creates a self-contained .build/ bundle for each (resolving component paths and copying
        artifacts), then installs by runtime:
                    - cli:    runs `copilot plugin install <local-bundle-path>` against the
                              prepared bundle on Windows and/or WSL per -Environment
          - vscode: copies each bundle into the detected VS Code user-data agentPlugins roots
                    (Stable + Insiders), then registers the copied path in the matching
                    chat.plugins.paths setting

    .PARAMETER Plugins
        Array of plugin names to install. Supports comma-separated values and
        wildcard patterns. If omitted, installs all discovered plugins.

    .PARAMETER Runtime
        Filter by runtime ('cli', 'vscode', 'all'). Defaults to outer-scope $Runtime.

    .PARAMETER Force
        Retained for backward compatibility. CLI publishing now reruns `copilot plugin install`
        from the prepared bundle on every publish, so no uninstall step is needed.

    .EXAMPLE
        Publish-Plugins
        Discovers and installs all plugins (CLI + VS Code) from the workspace.

    .EXAMPLE
        Publish-Plugins -Plugins ralph-v2 -Runtime vscode
        Publishes only the 'ralph-v2' VS Code plugin into VS Code agentPlugins roots and
        registers the copied bundle paths in settings.json.

    .EXAMPLE
        Publish-Plugins -Runtime cli -Environment windows -Force
        Reinstalls all selected CLI plugins into the Windows Copilot CLI user configuration.
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

    # Pre-check WSL availability once (only needed for CLI plugins).
    # -Environment all remains best-effort for WSL so Windows-only hosts can still publish.
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
                if ($Environment -eq 'wsl') {
                    throw "WSL not available"
                }
                Write-Host "WSL not available, skipping WSL installs for -Environment all" -ForegroundColor Yellow
            }
        }
        else {
            if ($Environment -eq 'wsl') {
                throw "WSL helpers not found, cannot publish CLI plugins to WSL"
            }
            Write-Host "WSL helpers not found, skipping WSL publishing for -Environment all" -ForegroundColor Yellow
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

        if ($pluginName -eq 'ralph-v2') {
            try {
                $sourceManifest = Get-Content (Join-Path $pluginDir.FullName 'plugin.json') -Raw | ConvertFrom-Json
                $ralphVersionContract = Get-RalphWorkflowVersionContract -PluginDir $pluginDir.FullName -Manifest $sourceManifest
                if ($null -ne $ralphVersionContract) {
                    Write-Host "  Ralph workflow version preflight: $($ralphVersionContract.WorkflowVersion)" -ForegroundColor DarkGray
                    Write-Host "  Ralph source manifest version preflight: $($ralphVersionContract.ManifestVersion)" -ForegroundColor DarkGray
                    Write-Host "  Ralph plugin bundle version preflight: $($ralphVersionContract.BundleVersion) ($($ralphVersionContract.BundleVersionSource))" -ForegroundColor DarkGray
                }
            }
            catch {
                Write-Error "  Ralph workflow version preflight failed for $pluginName`: $_"
                $errors++
                continue
            }
        }

        # Build self-contained bundle
        $buildPath = Build-PluginBundle -PluginDir $pluginDir.FullName -Channel $effectiveChannel
        if (-not $buildPath) {
            Write-Error "  Bundle failed for $pluginName — skipping"
            $errors++
            continue
        }

        # For beta channel, the install name is suffixed
        $installName = if ($effectiveChannel -eq 'beta') { "$pluginName-beta" } else { $pluginName }

        # --- VS Code: publish into user-data agentPlugins + register in settings.json ---
        if ($pluginRuntime -eq 'vscode') {
            $vsCodePublish = Update-VSCodePluginSettings -PluginPath $buildPath -PluginName $installName
            if ($vsCodePublish.Registered -gt 0) {
                $installed++
            }
            elseif ($vsCodePublish.LocationsDiscovered -eq 0) {
                Write-Warning "  No VS Code installations found — $pluginName not published"
            }
            else {
                Write-Error "  Failed to publish/register $pluginName for detected VS Code installations"
            }

            $errors += $vsCodePublish.Errors
            continue
        }

        # --- CLI: Windows official install flow ---
        if ($Environment -eq 'windows' -or $Environment -eq 'all') {
            try {
                $windowsInstall = Install-CopilotPluginBundle -BuildPath $buildPath -PluginName $installName

                if ($windowsInstall.InstallSucceeded) {
                    Write-Host "  Installed via Copilot CLI from: $($windowsInstall.InstallSourcePath)" -ForegroundColor Green
                    if ($windowsInstall.DiscoveryProbeSucceeded -and $windowsInstall.DiscoveryDetected) {
                        Write-Host "  Verified via `copilot plugin list`: $installName" -ForegroundColor DarkGray
                    }
                    else {
                        Write-CopilotPluginVerificationWarning -PluginName $installName -DiscoveryProbeSucceeded $windowsInstall.DiscoveryProbeSucceeded -DiscoveryDetected $windowsInstall.DiscoveryDetected
                    }
                    $installed++
                }
                else {
                    $detail = @($windowsInstall.InstallOutput, $windowsInstall.InstallException) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
                    if ($detail) {
                        Write-Error "  Failed to install $installName via `copilot plugin install` (exit $($windowsInstall.ExitCode)): $detail"
                    }
                    else {
                        Write-Error "  Failed to install $installName via `copilot plugin install` (exit $($windowsInstall.ExitCode))."
                    }
                    $errors++
                }
            }
            catch {
                Write-Error "  Failed to install $installName in the Windows Copilot CLI configuration: $_"
                $errors++
            }
        }

        # --- CLI: WSL official install flow ---
        if ($wslAvailable -and ($Environment -eq 'wsl' -or $Environment -eq 'all')) {
            try {
                $wslInstall = Install-CopilotPluginBundle -BuildPath $buildPath -PluginName $installName -UseWSL

                if ($wslInstall.InstallSucceeded) {
                    Write-Host "  WSL installed via Copilot CLI from: $($wslInstall.InstallSourcePath)" -ForegroundColor Green
                    if ($wslInstall.DiscoveryProbeSucceeded -and $wslInstall.DiscoveryDetected) {
                        Write-Host "  WSL verified via `copilot plugin list`: $installName" -ForegroundColor DarkGray
                    }
                    else {
                        Write-CopilotPluginVerificationWarning -PluginName $installName -DiscoveryProbeSucceeded $wslInstall.DiscoveryProbeSucceeded -DiscoveryDetected $wslInstall.DiscoveryDetected -UseWSL
                    }
                    $installed++
                }
                else {
                    $detail = @($wslInstall.InstallOutput, $wslInstall.InstallException) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
                    if ($detail) {
                        Write-Error "  WSL failed to install $installName via `copilot plugin install` (exit $($wslInstall.ExitCode)): $detail"
                    }
                    else {
                        Write-Error "  WSL failed to install $installName via `copilot plugin install` (exit $($wslInstall.ExitCode))."
                    }
                    $errors++
                }
            }
            catch {
                Write-Error "  WSL failed to install $installName in the Copilot CLI configuration: $_"
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
        Verifies that beta bundles exist under .build/<name>-beta/, then triggers
        a full stable build + publish from the same source. This ensures the stable
        bundle is built fresh, so manifest names and paths are correct.
    #>
    [CmdletBinding()]
    param()

    Write-Host "Promoting beta builds to stable..." -ForegroundColor Cyan

    $repoRoot = Split-Path $PSScriptRoot -Parent | Split-Path -Parent
    $pluginsPath = Join-Path $repoRoot "plugins"

    # Discover plugins that have beta builds under the shared .build root
    $promoted = 0
    foreach ($runtimeName in @('cli', 'vscode')) {
        $betaBuildRoot = Join-Path $pluginsPath "$runtimeName/.build"
        if (-not (Test-Path $betaBuildRoot)) { continue }

        $betaPlugins = Get-ChildItem -Path $betaBuildRoot -Directory | Where-Object { $_.Name -like '*-beta' }
        foreach ($betaPlugin in $betaPlugins) {
            $pluginName = $betaPlugin.Name -replace '-beta$'
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
