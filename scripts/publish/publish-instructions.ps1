param(
    [Parameter(Mandatory = $false)]
    [string[]]$Instructions,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

function Publish-InstructionsToVSCode {
    <#
    .SYNOPSIS
        Publishes instructions from the project factory to VS Code and VS Code Insiders user prompts directories.

    .DESCRIPTION
        Copies instruction files from the project's instructions/ folder to VS Code's and VS Code Insiders'
        user prompts directories for global availability across all workspaces and devices.

    .PARAMETER Instructions
        Array of instruction names to publish. If empty, publishes all instructions.

    .PARAMETER Force
        Overwrite existing instructions without prompting.

    .EXAMPLE
        Publish-InstructionsToVSCode

        Copies all instructions from project to VS Code user prompts.

    .EXAMPLE
        Publish-InstructionsToVSCode -Instructions "powershell", "claude-skills"

        Copies specific instructions.
    #>

    Write-Host "Publishing instructions to VS Code..." -ForegroundColor Cyan

    $projectInstructionsPath = Join-Path $PSScriptRoot "..\..\instructions"
    $vscodePromptsPaths = @(
        (Join-Path $env:APPDATA "Code\User\prompts"),
        (Join-Path $env:APPDATA "Code - Insiders\User\prompts")
    )

    # Ensure project instructions directory exists
    if (-not (Test-Path $projectInstructionsPath)) {
        throw "Project instructions directory not found: $projectInstructionsPath"
    }

    # Create VS Code prompts directories if they don't exist
    foreach ($path in $vscodePromptsPaths) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            Write-Host "Created VS Code prompts directory: $path" -ForegroundColor Green
        }
    }

    # Get instruction files to publish
    $instructionFiles = Get-ChildItem -Path $projectInstructionsPath -Filter "*.instructions.md"
    if ($Instructions) {
        $instructionFiles = $instructionFiles | Where-Object { ($_.Name -replace '\.instructions\.md$') -in $Instructions }
    }

    if ($instructionFiles.Count -eq 0) {
        Write-Host "No instruction files found to publish." -ForegroundColor Yellow
        return
    }

    Write-Host "Publishing $($instructionFiles.Count) instruction file(s)..." -ForegroundColor Cyan

    foreach ($instructionFile in $instructionFiles) {
        $sourcePath = $instructionFile.FullName

        foreach ($path in $vscodePromptsPaths) {
            $destinationPath = Join-Path $path $instructionFile.Name

            # Check if instruction already exists
            $exists = Test-Path $destinationPath

            if ($exists -and -not $Force) {
                $edition = if ($path -like "*Insiders*") { "Insiders" } else { "Stable" }
                $overwrite = Read-Host "Instruction '$($instructionFile.BaseName)' already exists in VS Code $edition. Overwrite? (y/N)"
                if ($overwrite -notmatch "^[Yy]") {
                    Write-Host "Skipping $($instructionFile.BaseName) for VS Code $edition" -ForegroundColor Yellow
                    continue
                }
            }

            try {
                Copy-Item -Path $sourcePath -Destination $destinationPath -Force
                $edition = if ($path -like "*Insiders*") { "Insiders" } else { "Stable" }
                Write-Host "Published: $($instructionFile.BaseName) to VS Code $edition" -ForegroundColor Green
            }
            catch {
                Write-Error "Failed to publish $($instructionFile.BaseName) to $path : $_"
            }
        }
    }

    Write-Host "Instruction publishing completed." -ForegroundColor Cyan
}

# If script is run directly, execute the function
if ($MyInvocation.InvocationName -like "*publish-instructions.ps1") {
    Publish-InstructionsToVSCode
}