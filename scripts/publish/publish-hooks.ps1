param(
    [Parameter(Mandatory = $false)]
    [string[]]$Hooks,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$SkipWSL,

    [Parameter(Mandatory = $false)]
    [ValidateSet('repo-scoped', 'user-level')]
    [string]$Scope = 'repo-scoped',

    [Parameter(Mandatory = $false)]
    [switch]$UserLevel
)

. "$PSScriptRoot/wsl-helpers.ps1"

if ($UserLevel) {
    if ($PSBoundParameters.ContainsKey('Scope') -and $Scope -ne 'user-level') {
        throw "Cannot combine -UserLevel with -Scope '$Scope'. Use -Scope user-level."
    }

    Write-Warning '-UserLevel is retained for backward compatibility. Prefer -Scope user-level.'
    $Scope = 'user-level'
}

function Update-VSCodeHookSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$WorkspaceHookPath,
        [Parameter(Mandatory)][string]$UserHookPath
    )

    $settingsLocations = @(
        @{ Label = 'VS Code Stable'; Path = "$env:APPDATA\Code\User\settings.json" },
        @{ Label = 'VS Code Insiders'; Path = "$env:APPDATA\Code - Insiders\User\settings.json" }
    )

    $updated = 0

    foreach ($loc in $settingsLocations) {
        $settingsPath = $loc.Path
        if (-not (Test-Path $settingsPath)) { continue }

        $rawContent = Get-Content $settingsPath -Raw
        $jsonText = [regex]::Replace($rawContent, '(?m)^\s*//[^\n]*', '')
        $jsonText = [regex]::Replace($jsonText, '(?s)/\*.*?\*/', '')
        $jsonText = [regex]::Replace($jsonText, ',(?=\s*[\}\]])', '')

        try {
            $settings = $jsonText | ConvertFrom-Json
        }
        catch {
            Write-Warning "  Could not parse $($loc.Label) settings.json - skipping: $_"
            continue
        }

        $hookPathsProperty = $settings.PSObject.Properties['chat.hookFilesLocations']
        if ($null -ne $hookPathsProperty -and $hookPathsProperty.Value -is [PSCustomObject]) {
            $hookPaths = $hookPathsProperty.Value
        }
        else {
            $hookPaths = [PSCustomObject]@{}
        }

        Add-Member -InputObject $hookPaths -NotePropertyName $WorkspaceHookPath -NotePropertyValue $true -Force
        Add-Member -InputObject $hookPaths -NotePropertyName $UserHookPath -NotePropertyValue $true -Force
        Add-Member -InputObject $settings -NotePropertyName 'chat.hookFilesLocations' -NotePropertyValue $hookPaths -Force

        $newContent = $settings | ConvertTo-Json -Depth 20
        Set-Content -Path $settingsPath -Value $newContent -Encoding UTF8

        Write-Host "  Updated hook search paths in $($loc.Label)" -ForegroundColor Green
        $updated++
    }

    return $updated
}

function Test-HookLocalCwd {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Cwd
    )

    if ([string]::IsNullOrWhiteSpace($Cwd)) {
        return $false
    }

    $normalized = (($Cwd -replace '\\', '/').Trim()).Trim('/')
    return (
        $normalized -eq 'hooks' -or
        $normalized.StartsWith('hooks/', [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalized -eq '.github/hooks' -or
        $normalized.StartsWith('.github/hooks/', [System.StringComparison]::OrdinalIgnoreCase)
    )
}

function Join-PublishPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RelativePath,
        [switch]$UseWSL
    )

    if ($UseWSL) {
        $normalizedRoot = ($Root -replace '\\', '/').TrimEnd('/')
        $normalizedRelative = ($RelativePath -replace '\\', '/').TrimStart('/')

        if ([string]::IsNullOrWhiteSpace($normalizedRelative)) {
            return $normalizedRoot
        }

        return "$normalizedRoot/$normalizedRelative"
    }

    return Join-Path $Root $RelativePath
}

function Get-TargetDirectoryPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$UseWSL
    )

    if ($UseWSL) {
        $normalizedPath = $Path -replace '\\', '/'
        $lastSeparator = $normalizedPath.LastIndexOf('/')
        if ($lastSeparator -lt 0) {
            return $normalizedPath
        }

        return $normalizedPath.Substring(0, $lastSeparator)
    }

    return Split-Path -Path $Path -Parent
}

function Ensure-PublishDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label,
        [switch]$UseWSL
    )

    if ($UseWSL) {
        Invoke-WSLCommand -Command "mkdir -p '$Path'" -SuppressStderr | Out-Null
        return
    }

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Host "Created $Label directory: $Path" -ForegroundColor Green
    }
}

function Test-PublishPathExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$UseWSL
    )

    if ($UseWSL) {
        return (Invoke-WSLCommand -Command "test -f '$Path' && echo 'exists' || echo 'notfound'" -SuppressStderr) -eq 'exists'
    }

    return Test-Path $Path
}

function Resolve-HookScriptSourcePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$CommandPath,
        [Parameter(Mandatory = $false)][string]$Cwd
    )

    if ([string]::IsNullOrWhiteSpace($CommandPath) -or [System.IO.Path]::IsPathRooted($CommandPath)) {
        return $null
    }

    $repoRootFull = [System.IO.Path]::GetFullPath($RepoRoot)
    $normalizedCommandPath = $CommandPath -replace '\\', '/'
    $resolvedPath = $null

    if ($normalizedCommandPath -match '^\./') {
        $basePath = if ([string]::IsNullOrWhiteSpace($Cwd)) { $repoRootFull } else { Join-Path $repoRootFull $Cwd }
        $resolvedPath = [System.IO.Path]::GetFullPath((Join-Path $basePath $CommandPath.Substring(2)))
    }
    else {
        $resolvedPath = [System.IO.Path]::GetFullPath((Join-Path $repoRootFull $CommandPath))
    }

    if (
        (Test-Path $resolvedPath) -and
        $resolvedPath.StartsWith($repoRootFull, [System.StringComparison]::OrdinalIgnoreCase)
    ) {
        return $resolvedPath
    }

    $fallbackRelative = $null

    if ($normalizedCommandPath.StartsWith('.github/hooks/', [System.StringComparison]::OrdinalIgnoreCase)) {
        $fallbackRelative = $normalizedCommandPath -replace '^[.]github/hooks/', 'hooks/'
    }
    elseif (
        (Test-HookLocalCwd -Cwd $Cwd) -and
        $normalizedCommandPath -match '^(?:\./)?scripts/'
    ) {
        $normalizedCwd = (($Cwd -replace '\\', '/').Trim()).Trim('/')
        if ($normalizedCwd.StartsWith('.github/hooks', [System.StringComparison]::OrdinalIgnoreCase)) {
            $normalizedCwd = "hooks$($normalizedCwd.Substring('.github/hooks'.Length))"
        }

        $fallbackBase = $normalizedCwd.TrimEnd('/')
        $fallbackRelative = "$fallbackBase/$($normalizedCommandPath -replace '^(?:\./)?', '')"
    }

    if ([string]::IsNullOrWhiteSpace($fallbackRelative)) {
        return $null
    }

    $fallbackPath = [System.IO.Path]::GetFullPath(
        (Join-Path $repoRootFull ($fallbackRelative -replace '/', [System.IO.Path]::DirectorySeparatorChar))
    )

    if (
        (Test-Path $fallbackPath) -and
        $fallbackPath.StartsWith($repoRootFull, [System.StringComparison]::OrdinalIgnoreCase)
    ) {
        return $fallbackPath
    }

    return $null
}

function Get-UserLevelScriptRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$SourcePath
    )

    $repoRootFull = [System.IO.Path]::GetFullPath($RepoRoot)
    $sourceFull = [System.IO.Path]::GetFullPath($SourcePath)
    $knownHookRoots = @(
        [System.IO.Path]::GetFullPath((Join-Path $repoRootFull 'hooks')),
        [System.IO.Path]::GetFullPath((Join-Path $repoRootFull '.github\hooks'))
    )

    foreach ($knownHookRoot in $knownHookRoots) {
        if ($sourceFull.StartsWith($knownHookRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            $relativePath = $sourceFull.Substring($knownHookRoot.Length).TrimStart('\', '/')
            if (-not [string]::IsNullOrWhiteSpace($relativePath)) {
                return $relativePath
            }
        }
    }

    $repoRelativePath = [System.IO.Path]::GetRelativePath($repoRootFull, $sourceFull)
    return Join-Path 'repo-scripts' $repoRelativePath
}

function Get-HookManifestRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectHooksPath,
        [Parameter(Mandatory)][System.IO.FileInfo]$HookFile
    )

    $hooksRootFull = [System.IO.Path]::GetFullPath($ProjectHooksPath).TrimEnd('\', '/')
    $hookFull = [System.IO.Path]::GetFullPath($HookFile.FullName)
    $hooksRootPrefix = "$hooksRootFull$([System.IO.Path]::DirectorySeparatorChar)"

    if ($hookFull.StartsWith($hooksRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $hookFull.Substring($hooksRootPrefix.Length)
    }

    throw "Hook manifest '$hookFull' must remain inside $ProjectHooksPath"
}

function Convert-PathForCommandProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AbsolutePath,
        [Parameter(Mandatory)][string]$PropertyName,
        [string]$PosixAbsolutePath
    )

    if ($PropertyName -in @('powershell', 'windows')) {
        return $AbsolutePath
    }

    if (
        -not [string]::IsNullOrWhiteSpace($PosixAbsolutePath) -and
        $PropertyName -in @('bash', 'linux', 'osx')
    ) {
        return $PosixAbsolutePath
    }

    return $AbsolutePath -replace '\\', '/'
}

function Update-HookCommandForUserLevel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$CommandText,
        [Parameter(Mandatory)][string]$DestinationRoot,
        [Parameter(Mandatory)][string]$CommandPropertyName,
        [Parameter(Mandatory = $false)][string]$Cwd,
        [string]$PosixDestinationRoot,
        [switch]$UseWSL
    )

    $pathPattern = '(?<path>(?:\.[\\/]|[A-Za-z0-9_.-]+[\\/])[^"''`\s|;&]+?\.(?:bash|sh|ps1|cmd|bat|py|rb|js|ts|psm1))'
    $scriptReferences = @{}
    $removeCwd = $false

    $updatedCommand = [regex]::Replace($CommandText, $pathPattern, {
            param($match)

            $candidatePath = $match.Groups['path'].Value
            $sourcePath = Resolve-HookScriptSourcePath -RepoRoot $RepoRoot -CommandPath $candidatePath -Cwd $Cwd
            if ($null -eq $sourcePath) {
                return $candidatePath
            }

            $destinationRelativePath = Get-UserLevelScriptRelativePath -RepoRoot $RepoRoot -SourcePath $sourcePath
            $destinationAbsolutePath = Join-PublishPath -Root $DestinationRoot -RelativePath $destinationRelativePath -UseWSL:$UseWSL
            $posixDestinationAbsolutePath = $null
            if (-not [string]::IsNullOrWhiteSpace($PosixDestinationRoot)) {
                $posixDestinationAbsolutePath = Join-PublishPath -Root $PosixDestinationRoot -RelativePath $destinationRelativePath -UseWSL
            }
            $scriptReferences[$sourcePath.ToLowerInvariant()] = [PSCustomObject]@{
                SourcePath = $sourcePath
                DestinationRelativePath = $destinationRelativePath
            }

            $normalizedCandidate = $candidatePath -replace '\\', '/'
            if ((Test-HookLocalCwd -Cwd $Cwd) -and $normalizedCandidate -match '^(?:\./)?scripts/') {
                $removeCwd = $true
            }

            return Convert-PathForCommandProperty `
                -AbsolutePath $destinationAbsolutePath `
                -PropertyName $CommandPropertyName `
                -PosixAbsolutePath $posixDestinationAbsolutePath
        })

    return [PSCustomObject]@{
        CommandText = $updatedCommand
        ScriptReferences = @($scriptReferences.Values)
        RemoveCwd = $removeCwd
    }
}

function Convert-HookFileForUserLevel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$HookFile,
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$DestinationRoot,
        [string]$PosixDestinationRoot,
        [switch]$UseWSL
    )

    $hookConfig = Get-Content -Path $HookFile.FullName -Raw | ConvertFrom-Json -Depth 50
    $scriptReferenceMap = @{}
    $commandProperties = @('bash', 'powershell', 'command', 'windows', 'linux', 'osx')

    foreach ($hookEvent in $hookConfig.hooks.PSObject.Properties) {
        foreach ($hookCommand in @($hookEvent.Value)) {
            $cwdProperty = $hookCommand.PSObject.Properties['cwd']
            $cwd = if ($null -ne $cwdProperty) { [string]$cwdProperty.Value } else { $null }
            $removeCwd = $false

            foreach ($commandPropertyName in $commandProperties) {
                $commandProperty = $hookCommand.PSObject.Properties[$commandPropertyName]
                if ($null -eq $commandProperty -or [string]::IsNullOrWhiteSpace([string]$commandProperty.Value)) {
                    continue
                }

                $updatedCommand = Update-HookCommandForUserLevel `
                    -RepoRoot $RepoRoot `
                    -CommandText ([string]$commandProperty.Value) `
                    -DestinationRoot $DestinationRoot `
                    -CommandPropertyName $commandPropertyName `
                    -Cwd $cwd `
                    -PosixDestinationRoot $PosixDestinationRoot `
                    -UseWSL:$UseWSL

                $commandProperty.Value = $updatedCommand.CommandText

                foreach ($scriptReference in $updatedCommand.ScriptReferences) {
                    $scriptReferenceMap[$scriptReference.SourcePath.ToLowerInvariant()] = $scriptReference
                }

                if ($updatedCommand.RemoveCwd) {
                    $removeCwd = $true
                }
            }

            if ($removeCwd -and $null -ne $cwdProperty) {
                $hookCommand.PSObject.Properties.Remove('cwd')
            }
        }
    }

    return [PSCustomObject]@{
        Content = $hookConfig | ConvertTo-Json -Depth 50
        ScriptReferences = @($scriptReferenceMap.Values)
    }
}

function Write-PublishFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][string]$Content,
        [switch]$UseWSL
    )

    $destinationDirectory = Get-TargetDirectoryPath -Path $DestinationPath -UseWSL:$UseWSL
    Ensure-PublishDirectory -Path $destinationDirectory -Label 'publish target' -UseWSL:$UseWSL

    if ($UseWSL) {
        $temporaryFile = [System.IO.Path]::GetTempFileName()

        try {
            Set-Content -Path $temporaryFile -Value $Content -Encoding UTF8
            if (-not (Copy-ToWSL -Source $temporaryFile -Destination $DestinationPath)) {
                throw "Failed to write '$DestinationPath' to WSL."
            }
        }
        finally {
            Remove-Item $temporaryFile -Force -ErrorAction SilentlyContinue
        }

        return
    }

    Set-Content -Path $DestinationPath -Value $Content -Encoding UTF8
}

function Copy-PublishScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [switch]$UseWSL
    )

    $destinationDirectory = Get-TargetDirectoryPath -Path $DestinationPath -UseWSL:$UseWSL
    Ensure-PublishDirectory -Path $destinationDirectory -Label 'script target' -UseWSL:$UseWSL

    if ($UseWSL) {
        if (-not (Copy-ToWSL -Source $SourcePath -Destination $DestinationPath)) {
            throw "Failed to publish script '$SourcePath' to '$DestinationPath'."
        }

        return
    }

    Copy-Item -Path $SourcePath -Destination $DestinationPath -Force
}

function Publish-HookSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo[]]$HookFiles,
        [Parameter(Mandatory)][string]$ProjectHooksPath,
        [Parameter(Mandatory)][string]$DestinationRoot,
        [Parameter(Mandatory)][string]$Label,
        [switch]$UseWSL
    )

    Ensure-PublishDirectory -Path $DestinationRoot -Label $Label -UseWSL:$UseWSL

    $published = 0
    $skipped = 0

    foreach ($file in $HookFiles) {
        $relativePath = Get-HookManifestRelativePath -ProjectHooksPath $ProjectHooksPath -HookFile $file

        $targetFile = if ($UseWSL) {
            Join-PublishPath -Root $DestinationRoot -RelativePath $file.Name -UseWSL
        }
        else {
            Join-Path $DestinationRoot $file.Name
        }
        $targetDirectory = Get-TargetDirectoryPath -Path $targetFile -UseWSL:$UseWSL
        Ensure-PublishDirectory -Path $targetDirectory -Label 'publish target' -UseWSL:$UseWSL

        if ((Test-PublishPathExists -Path $targetFile -UseWSL:$UseWSL) -and -not $Force) {
            Write-Host "  Skipped (exists): $($file.Name) -> $Label - use -Force to overwrite" -ForegroundColor Yellow
            $skipped++
            continue
        }

        if ($UseWSL) {
            if (Copy-ToWSL -Source $file.FullName -Destination $targetFile) {
                Write-Host "  Published: $($file.Name) -> $Label" -ForegroundColor Green
                $published++
            }
            else {
                Write-Error "  Failed to publish $($file.Name) -> $Label"
            }

            continue
        }

        Copy-Item -Path $file.FullName -Destination $targetFile -Force
        Write-Host "  Published: $($file.Name) -> $Label" -ForegroundColor Green
        $published++
    }

    return [PSCustomObject]@{
        Published = $published
        Skipped = $skipped
        ScriptsPublished = 0
        ScriptsSkipped = 0
    }
}

function Publish-UserLevelHookSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo[]]$HookFiles,
        [Parameter(Mandatory)][string]$ProjectHooksPath,
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$DestinationRoot,
        [Parameter(Mandatory)][string]$Label,
        [string]$PosixDestinationRoot,
        [switch]$UseWSL
    )

    Ensure-PublishDirectory -Path $DestinationRoot -Label $Label -UseWSL:$UseWSL

    $published = 0
    $skipped = 0
    $scriptsPublished = 0
    $scriptsSkipped = 0

    foreach ($file in $HookFiles) {
        $relativePath = Get-HookManifestRelativePath -ProjectHooksPath $ProjectHooksPath -HookFile $file

        $targetFile = Join-PublishPath -Root $DestinationRoot -RelativePath $file.Name -UseWSL:$UseWSL
        if ((Test-PublishPathExists -Path $targetFile -UseWSL:$UseWSL) -and -not $Force) {
            Write-Host "  Skipped (exists): $($file.Name) -> $Label - use -Force to overwrite" -ForegroundColor Yellow
            $skipped++
            continue
        }

        $convertedHook = Convert-HookFileForUserLevel `
            -HookFile $file `
            -RepoRoot $RepoRoot `
            -DestinationRoot $DestinationRoot `
            -PosixDestinationRoot $PosixDestinationRoot `
            -UseWSL:$UseWSL

        foreach ($scriptReference in $convertedHook.ScriptReferences) {
            $scriptTargetPath = Join-PublishPath -Root $DestinationRoot -RelativePath $scriptReference.DestinationRelativePath -UseWSL:$UseWSL
            if ((Test-PublishPathExists -Path $scriptTargetPath -UseWSL:$UseWSL) -and -not $Force) {
                $scriptsSkipped++
                continue
            }

            Copy-PublishScript -SourcePath $scriptReference.SourcePath -DestinationPath $scriptTargetPath -UseWSL:$UseWSL
            $scriptsPublished++
        }

        Write-PublishFile -DestinationPath $targetFile -Content $convertedHook.Content -UseWSL:$UseWSL
        Write-Host "  Published: $($file.Name) -> $Label" -ForegroundColor Green
        $published++
    }

    return [PSCustomObject]@{
        Published = $published
        Skipped = $skipped
        ScriptsPublished = $scriptsPublished
        ScriptsSkipped = $scriptsSkipped
    }
}

function Publish-HooksToWorkspace {
    <#
    .SYNOPSIS
        Publishes agent hook configurations as repo-scoped or user-level hooks.

    .DESCRIPTION
        Copies hook JSON files from the authoring hooks/ folder to one of two targets:
        - `.github/hooks/` for repo-scoped discovery (default)
        - `~/.copilot/hooks/` for user-level discovery when `-Scope user-level` is selected

        User-level publishing also copies referenced hook scripts into the published hook tree,
        rewrites script paths in the published JSON to full paths, updates VS Code's
        `chat.hookFilesLocations`, and mirrors the result into WSL when available.

    .PARAMETER Hooks
        Array or comma-separated string of hook names to publish (without .hooks.json extension).
        If omitted, publishes all hooks found.

    .PARAMETER Force
        Overwrite existing hooks without prompting for confirmation.

    .PARAMETER Scope
        Selects the publish target:
        - `repo-scoped` (default) publishes hooks to `.github/hooks/`
        - `user-level` publishes hooks to `~/.copilot/hooks/` and rewrites referenced scripts

    .PARAMETER UserLevel
        Legacy compatibility switch. Equivalent to `-Scope user-level`.

    .EXAMPLE
        Publish-HooksToWorkspace
        Copies all hook files from hooks/ to .github/hooks/.

    .EXAMPLE
        Publish-HooksToWorkspace -Scope user-level
        Publishes hooks to ~/.copilot/hooks/ and copies referenced scripts into the same tree.

    .EXAMPLE
        Publish-HooksToWorkspace -Hooks "security-policy,format-on-save"
        Publishes only the named hooks using the default repo-scoped target.

    .EXAMPLE
        Publish-HooksToWorkspace -Force
        Overwrites existing hooks in the selected destination.
    #>

    $repoRoot = Split-Path $PSScriptRoot -Parent | Split-Path -Parent
    $projectHooksPath = Join-Path $repoRoot 'hooks'
    $workspaceHooksPath = Join-Path $repoRoot '.github\hooks'
    $windowsUserHooksPath = Join-Path $env:USERPROFILE '.copilot\hooks'
    $wslAvailable = $false
    $wslHome = $null

    if ($Scope -eq 'repo-scoped') {
        Write-Host 'Publishing hooks as repo-scoped manifests to .github/hooks/...' -ForegroundColor Cyan
        Write-Host 'Repo-scoped mode is the default and preserves existing workspace-relative script paths.' -ForegroundColor DarkGray
    }
    else {
        Write-Host 'Publishing hooks as user-level manifests to ~/.copilot/hooks/...' -ForegroundColor Cyan
        Write-Host 'User-level mode copies referenced scripts and rewrites published command paths to full paths.' -ForegroundColor DarkGray
    }

    if ($Scope -eq 'user-level' -and -not $SkipWSL) {
        $wslAvailable = Test-WSLAvailable -WslHome ([ref]$wslHome)
        if ($wslAvailable) {
            Write-Host "WSL detected at home: $wslHome" -ForegroundColor DarkGray
        }
        else {
            Write-Host 'WSL not available, skipping WSL hook publishing' -ForegroundColor Yellow
        }
    }

    if (-not (Test-Path $projectHooksPath)) {
        throw "Project hooks directory not found: $projectHooksPath"
    }

    $hookList = @()
    if ($Hooks) {
        foreach ($hook in $Hooks) {
            $hookList += @($hook -split ',').Trim() | Where-Object { $_ -ne '' }
        }
        $hookList = $hookList | Select-Object -Unique
    }

    $hookFiles = @(Get-ChildItem -Path $projectHooksPath -Filter '*.hooks.json' -File -Recurse | Sort-Object FullName)

    if ($hookList.Count -gt 0) {
        $hookFiles = $hookFiles | Where-Object {
            $base = $_.BaseName -replace '\.hooks$', ''
            $hookList | Where-Object { $base -like $_ } | Select-Object -First 1
        }

        if ($hookFiles.Count -eq 0) {
            Write-Host "Warning: No hooks found matching: $($hookList -join ', ')" -ForegroundColor Yellow
            Write-Host 'Available hooks:' -ForegroundColor Cyan
            Get-ChildItem -Path $projectHooksPath -Filter '*.hooks.json' -File -Recurse |
                ForEach-Object { Write-Host "  - $($_.BaseName -replace '\.hooks$', '')" }
            return
        }
    }

    if ($hookFiles.Count -eq 0) {
        Write-Host "No hook files found in: $projectHooksPath" -ForegroundColor Yellow
        return
    }

    Write-Host "Publishing $($hookFiles.Count) hook(s)" -ForegroundColor Cyan

    if ($Scope -eq 'repo-scoped') {
        $result = Publish-HookSet -HookFiles $hookFiles -ProjectHooksPath $projectHooksPath -DestinationRoot $workspaceHooksPath -Label '.github/hooks'

        Write-Host ''
        Write-Host "Done: hooks $($result.Published) published, $($result.Skipped) skipped" -ForegroundColor Cyan
        return
    }

    $userLevelPosixRoot = if ($wslAvailable) { "$wslHome/.copilot/hooks" } else { $null }

    $windowsResult = Publish-UserLevelHookSet `
        -HookFiles $hookFiles `
        -ProjectHooksPath $projectHooksPath `
        -RepoRoot $repoRoot `
        -DestinationRoot $windowsUserHooksPath `
        -Label '~/.copilot/hooks' `
        -PosixDestinationRoot $userLevelPosixRoot
    $wslResult = [PSCustomObject]@{
        Published = 0
        Skipped = 0
        ScriptsPublished = 0
        ScriptsSkipped = 0
    }

    if ($wslAvailable) {
        $wslResult = Publish-UserLevelHookSet `
            -HookFiles $hookFiles `
            -ProjectHooksPath $projectHooksPath `
            -RepoRoot $repoRoot `
            -DestinationRoot "$wslHome/.copilot/hooks" `
            -Label 'WSL ~/.copilot/hooks' `
            -PosixDestinationRoot "$wslHome/.copilot/hooks" `
            -UseWSL
    }

    Update-VSCodeHookSettings -WorkspaceHookPath '.github/hooks' -UserHookPath '~/.copilot/hooks' | Out-Null

    $published = $windowsResult.Published + $wslResult.Published
    $skipped = $windowsResult.Skipped + $wslResult.Skipped
    $scriptsPublished = $windowsResult.ScriptsPublished + $wslResult.ScriptsPublished
    $scriptsSkipped = $windowsResult.ScriptsSkipped + $wslResult.ScriptsSkipped

    Write-Host ''
    Write-Host "Done: hooks $published published, hooks $skipped skipped, scripts $scriptsPublished published, scripts $scriptsSkipped skipped" -ForegroundColor Cyan
}

if ($MyInvocation.InvocationName -ne '.') {
    Publish-HooksToWorkspace
}
