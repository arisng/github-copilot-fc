param(
    [Parameter(Mandatory = $false)]
    [string[]]$Prompts,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

function Publish-PromptsToVSCode {
    <#
    .SYNOPSIS
        Publishes prompts from the project factory to VS Code user prompts directory.

    .DESCRIPTION
        Copies prompt files from the project's prompts/ folder to VS Code's user prompts
        directory for global availability across all workspaces and devices.

    .PARAMETER Prompts
        Array of prompt names to publish. If empty, publishes all prompts.

    .PARAMETER Force
        Overwrite existing prompts without prompting.

    .EXAMPLE
        Publish-PromptsToVSCode

        Copies all prompts from project to VS Code user prompts.

    .EXAMPLE
        Publish-PromptsToVSCode -Prompts "changelog", "conventional-commit"

        Copies specific prompts.
    #>

    Write-Host "Publishing prompts to VS Code..." -ForegroundColor Cyan

    $projectPromptsPath = Join-Path $PSScriptRoot "..\prompts"
    $vscodePromptsPath = Join-Path $env:APPDATA "Code\User\prompts"

    # Ensure project prompts directory exists
    if (-not (Test-Path $projectPromptsPath)) {
        throw "Project prompts directory not found: $projectPromptsPath"
    }

    # Create VS Code prompts directory if it doesn't exist
    if (-not (Test-Path $vscodePromptsPath)) {
        New-Item -ItemType Directory -Path $vscodePromptsPath -Force | Out-Null
        Write-Host "Created VS Code prompts directory: $vscodePromptsPath" -ForegroundColor Green
    }

    # Get prompt files to publish
    $promptFiles = Get-ChildItem -Path $projectPromptsPath -Filter "*.prompt.md"
    if ($Prompts) {
        $promptFiles = $promptFiles | Where-Object { ($_.Name -replace '\.prompt\.md$') -in $Prompts }
    }

    if ($promptFiles.Count -eq 0) {
        Write-Host "No prompt files found to publish." -ForegroundColor Yellow
        return
    }

    Write-Host "Publishing $($promptFiles.Count) prompt file(s)..." -ForegroundColor Cyan

    foreach ($promptFile in $promptFiles) {
        $sourcePath = $promptFile.FullName
        $destinationPath = Join-Path $vscodePromptsPath $promptFile.Name

        # Check if prompt already exists
        $exists = Test-Path $destinationPath

        if ($exists -and -not $Force) {
            $overwrite = Read-Host "Prompt '$($promptFile.BaseName)' already exists. Overwrite? (y/N)"
            if ($overwrite -notmatch "^[Yy]") {
                Write-Host "Skipping $($promptFile.BaseName)" -ForegroundColor Yellow
                continue
            }
        }

        try {
            Copy-Item -Path $sourcePath -Destination $destinationPath -Force
            Write-Host "Published: $($promptFile.BaseName)" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to publish $($promptFile.BaseName): $_"
        }
    }

    Write-Host "Prompt publishing completed." -ForegroundColor Cyan
}

# If script is run directly, execute the function
if ($MyInvocation.InvocationName -like "*publish-prompts.ps1") {
    Publish-PromptsToVSCode
}