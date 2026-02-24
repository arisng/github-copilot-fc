param(
    [Parameter(Mandatory = $false)]
    $Toolsets,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

function Publish-ToolsetsToVSCode {
    <#
    .SYNOPSIS
        Publishes toolsets from the workspace to VS Code user toolsets directories.

    .DESCRIPTION
        Copies toolsets from the workspace toolsets/ folder to VS Code's and VS Code Insiders'
        user toolsets directories for global availability.

    .PARAMETER Toolsets
        Array of toolset names to publish. If empty, publishes all toolsets.

    .PARAMETER Force
        Overwrite existing toolsets.

    .EXAMPLE
        Publish-ToolsetsToVSCode

        Copies all toolsets from the workspace to VS Code directories.
    #>

    Write-Host "Publishing toolsets to VS Code..." -ForegroundColor Cyan

    $projectToolsetsPath = Join-Path $PSScriptRoot "..\..\toolsets"
    $vscodeToolsetsPaths = @(
        (Join-Path $env:APPDATA "Code\User\prompts"),
        (Join-Path $env:APPDATA "Code - Insiders\User\prompts")
    )

    # Ensure project toolsets directory exists
    if (-not (Test-Path $projectToolsetsPath)) {
        throw "Project toolsets directory not found: $projectToolsetsPath"
    }

    # Create VS Code toolsets directories if they don't exist
    foreach ($path in $vscodeToolsetsPaths) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            Write-Host "Created VS Code toolsets directory: $path" -ForegroundColor Green
        }
    }

    # Get toolsets to publish
    $toolsetFiles = Get-ChildItem -Path $projectToolsetsPath -Filter "*.toolsets.jsonc"
    $jsoncFiles = Get-ChildItem -Path $projectToolsetsPath -Filter "*.jsonc"
    $toolsetFiles = $toolsetFiles + $jsoncFiles | Where-Object { $_.Extension -eq '.jsonc' }
    if ($Toolsets) {
        # normalize list (comma-separated support)
        $tsList = @()
        foreach ($item in $Toolsets) {
            $tsList += @($item -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        }
        $toolsetFiles = $toolsetFiles | Where-Object {
            $base = $_.BaseName -replace '\.toolsets$',''
            $tsList | Where-Object { $base -like $_ } | Select-Object -First 1
        }
        if ($toolsetFiles.Count -eq 0) {
            Write-Host "Warning: No toolsets found matching: $($tsList -join ', ')" -ForegroundColor Yellow
            Write-Host "Available toolsets:" -ForegroundColor Cyan
            Get-ChildItem -Path $projectToolsetsPath -Filter "*.jsonc" | 
                ForEach-Object { Write-Host "  - $($_.BaseName -replace '\.toolsets$','')" }
            return
        }
    }

    if ($toolsetFiles.Count -eq 0) {
        Write-Host "No toolsets found to publish." -ForegroundColor Yellow
        return
    }

    Write-Host "Publishing $($toolsetFiles.Count) toolset(s)" -ForegroundColor Cyan

    foreach ($toolsetFile in $toolsetFiles) {
        $sourcePath = $toolsetFile.FullName

        foreach ($path in $vscodeToolsetsPaths) {
            $destinationPath = Join-Path $path $toolsetFile.Name
            $edition = if ($path -like "*Insiders*") { "Insiders" } else { "Stable" }

            # Check if toolset already exists
            $exists = Test-Path $destinationPath

            try {
                if ($exists -and -not $Force) {
                    Write-Host "Skipping $($toolsetFile.Name) for VS Code $edition (already exists). Use -Force to overwrite." -ForegroundColor Yellow
                    continue
                }

                if ($exists) { Remove-Item -Path $destinationPath -Force }
                Copy-Item -Path $sourcePath -Destination $destinationPath -Force
                Write-Host "Copied: $($toolsetFile.Name) to VS Code $edition" -ForegroundColor Green
            }
            catch {
                Write-Error "Failed to publish $($toolsetFile.Name) to VS Code $edition : $_"
            }
        }
    }

    Write-Host "Toolset publishing completed." -ForegroundColor Cyan
}

# Execute the function unconditionally; guards caused the helper to be skipped when
# invoked via `&` in the wrapper.
Publish-ToolsetsToVSCode
