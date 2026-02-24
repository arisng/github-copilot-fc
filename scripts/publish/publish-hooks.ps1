param(
    [Parameter(Mandatory = $false)]
    [string[]]$Hooks,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

function Publish-HooksToWorkspace {
    <#
    .SYNOPSIS
        Publishes agent hook configurations to .github/hooks/ for VS Code discovery.

    .DESCRIPTION
        Copies hook JSON files from the authoring hooks/ folder to .github/hooks/
        where VS Code searches for workspace-level hook configurations.

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

    Write-Host "Publishing hooks to .github/hooks/..." -ForegroundColor Cyan

    $repoRoot = Split-Path $PSScriptRoot -Parent | Split-Path -Parent
    $projectHooksPath = Join-Path $repoRoot "hooks"
    $targetHooksPath = Join-Path $repoRoot ".github\hooks"

    # Ensure project hooks directory exists
    if (-not (Test-Path $projectHooksPath)) {
        throw "Project hooks directory not found: $projectHooksPath"
    }

    # Create target directory if it doesn't exist
    if (-not (Test-Path $targetHooksPath)) {
        New-Item -ItemType Directory -Path $targetHooksPath -Force | Out-Null
        Write-Host "Created .github/hooks/ directory" -ForegroundColor Green
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

    $published = 0
    $skipped = 0

    foreach ($file in $hookFiles) {
        $targetFile = Join-Path $targetHooksPath $file.Name

        if ((Test-Path $targetFile) -and -not $Force) {
            Write-Host "  Skipped (exists): $($file.Name) — use -Force to overwrite" -ForegroundColor Yellow
            $skipped++
            continue
        }

        Copy-Item -Path $file.FullName -Destination $targetFile -Force
        Write-Host "  Published: $($file.Name)" -ForegroundColor Green
        $published++
    }

    Write-Host ""
    Write-Host "Done: $published published, $skipped skipped" -ForegroundColor Cyan
}

Publish-HooksToWorkspace
