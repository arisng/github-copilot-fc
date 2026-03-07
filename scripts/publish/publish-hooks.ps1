param(
    [Parameter(Mandatory = $false)]
    [string[]]$Hooks,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$SkipWSL
)

. "$PSScriptRoot/wsl-helpers.ps1"

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
            Write-Warning "  Could not parse $($loc.Label) settings.json — skipping: $_"
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

function Publish-HookSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo[]]$HookFiles,
        [Parameter(Mandatory)][string]$DestinationRoot,
        [Parameter(Mandatory)][string]$Label,
        [switch]$UseWSL
    )

    if ($UseWSL) {
        Invoke-WSLCommand -Command "mkdir -p '$DestinationRoot'" -SuppressStderr | Out-Null
    }
    elseif (-not (Test-Path $DestinationRoot)) {
        New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
        Write-Host "Created $Label directory: $DestinationRoot" -ForegroundColor Green
    }

    $published = 0
    $skipped = 0

    foreach ($file in $HookFiles) {
        if ($UseWSL) {
            $targetFile = "$DestinationRoot/$($file.Name)"
            $exists = Invoke-WSLCommand -Command "test -f '$targetFile' && echo 'exists' || echo 'notfound'" -SuppressStderr

            if ($exists -eq 'exists' -and -not $Force) {
                Write-Host "  Skipped (exists): $($file.Name) -> $Label — use -Force to overwrite" -ForegroundColor Yellow
                $skipped++
                continue
            }

            if (Copy-ToWSL -Source $file.FullName -Destination $targetFile) {
                Write-Host "  Published: $($file.Name) -> $Label" -ForegroundColor Green
                $published++
            }
            else {
                Write-Error "  Failed to publish $($file.Name) -> $Label"
            }

            continue
        }

        $targetFile = Join-Path $DestinationRoot $file.Name
        if ((Test-Path $targetFile) -and -not $Force) {
            Write-Host "  Skipped (exists): $($file.Name) -> $Label — use -Force to overwrite" -ForegroundColor Yellow
            $skipped++
            continue
        }

        Copy-Item -Path $file.FullName -Destination $targetFile -Force
        Write-Host "  Published: $($file.Name) -> $Label" -ForegroundColor Green
        $published++
    }

    return [PSCustomObject]@{ Published = $published; Skipped = $skipped }
}

function Publish-HooksToWorkspace {
    <#
    .SYNOPSIS
        Publishes agent hook configurations to workspace and personal Copilot hook folders.

    .DESCRIPTION
        Copies hook JSON files from the authoring hooks/ folder to:
        - `.github/hooks/` for workspace-level discovery
        - `~/.copilot/hooks/` on Windows for personal Copilot hook storage and VS Code discovery
        - `~/.copilot/hooks/` inside WSL when available
        Also ensures VS Code's `chat.hookFilesLocations` includes both `.github/hooks`
        and `~/.copilot/hooks`.

    .PARAMETER Hooks
        Array or comma-separated string of hook names to publish (without .hooks.json extension).
        If omitted, publishes all hooks found.

    .PARAMETER Force
        Overwrite existing hooks without prompting for confirmation.

    .EXAMPLE
        Publish-HooksToWorkspace
        Copies all hook files from hooks/ to .github/hooks/.

    .EXAMPLE
        Publish-HooksToWorkspace -Hooks "security-policy,format-on-save"
        Publishes only the named hooks.

    .EXAMPLE
        Publish-HooksToWorkspace -Force
        Overwrites existing hooks in .github/hooks/.
    #>

    Write-Host "Publishing hooks to workspace and Copilot user hook folders..." -ForegroundColor Cyan
    Write-Host "Workspace hooks remain published to .github/hooks for repository-level Copilot discovery." -ForegroundColor DarkGray

    $repoRoot = Split-Path $PSScriptRoot -Parent | Split-Path -Parent
    $projectHooksPath = Join-Path $repoRoot "hooks"
    $workspaceHooksPath = Join-Path $repoRoot '.github\hooks'
    $windowsUserHooksPath = Join-Path $env:USERPROFILE '.copilot\hooks'
    $wslAvailable = $false
    $wslHome = $null

    if (-not $SkipWSL) {
        $wslAvailable = Test-WSLAvailable -WslHome ([ref]$wslHome)
        if ($wslAvailable) {
            Write-Host "WSL detected at home: $wslHome" -ForegroundColor DarkGray
        }
        else {
            Write-Host 'WSL not available, skipping WSL hook publishing' -ForegroundColor Yellow
        }
    }

    # Ensure project hooks directory exists
    if (-not (Test-Path $projectHooksPath)) {
        throw "Project hooks directory not found: $projectHooksPath"
    }

    # Normalize hook names: handle both comma-separated strings and arrays
    $hookList = @()
    if ($Hooks) {
        foreach ($hook in $Hooks) {
            $hookList += @($hook -split ',').Trim() | Where-Object { $_ -ne '' }
        }
        $hookList = $hookList | Select-Object -Unique
    }

    # Get hook files to publish (*.hooks.json and *.json)
    $hookFiles = @(Get-ChildItem -Path $projectHooksPath -Filter "*.json" -File)

    if ($hookList.Count -gt 0) {
        $hookFiles = $hookFiles | Where-Object {
            $base = $_.BaseName -replace '\.hooks$', ''
            $hookList | Where-Object { $base -like $_ } | Select-Object -First 1
        }

        if ($hookFiles.Count -eq 0) {
            Write-Host "Warning: No hooks found matching: $($hookList -join ', ')" -ForegroundColor Yellow
            Write-Host "Available hooks:" -ForegroundColor Cyan
            Get-ChildItem -Path $projectHooksPath -Filter "*.json" -File |
                ForEach-Object { Write-Host "  - $($_.BaseName -replace '\.hooks$', '')" }
            return
        }
    }

    if ($hookFiles.Count -eq 0) {
        Write-Host "No hook files found in: $projectHooksPath" -ForegroundColor Yellow
        return
    }

    Write-Host "Publishing $($hookFiles.Count) hook(s)" -ForegroundColor Cyan

    $workspaceResult = Publish-HookSet -HookFiles $hookFiles -DestinationRoot $workspaceHooksPath -Label '.github/hooks'
    $windowsResult = Publish-HookSet -HookFiles $hookFiles -DestinationRoot $windowsUserHooksPath -Label '~/.copilot/hooks'

    $wslResult = [PSCustomObject]@{ Published = 0; Skipped = 0 }
    if ($wslAvailable) {
        $wslResult = Publish-HookSet -HookFiles $hookFiles -DestinationRoot "$wslHome/.copilot/hooks" -Label 'WSL ~/.copilot/hooks' -UseWSL
    }

    Update-VSCodeHookSettings -WorkspaceHookPath '.github/hooks' -UserHookPath '~/.copilot/hooks' | Out-Null

    $published = $workspaceResult.Published + $windowsResult.Published + $wslResult.Published
    $skipped = $workspaceResult.Skipped + $windowsResult.Skipped + $wslResult.Skipped

    Write-Host ""
    Write-Host "Done: $published published, $skipped skipped" -ForegroundColor Cyan
}

Publish-HooksToWorkspace
