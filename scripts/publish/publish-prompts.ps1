param(
    [Parameter(Mandatory = $false)]
    [string]$Prompts,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)


function Publish-PromptsToVSCode {
    <#
    .SYNOPSIS
        Publishes prompts from the project factory to VS Code and VS Code Insiders user prompts directories.

    .DESCRIPTION
        Copies prompt files from the project's prompts/ folder to VS Code's and VS Code Insiders'
        user prompts directories for global availability across all workspaces and devices.

    .PARAMETER Prompts
        Array of prompt names to publish. If empty, publishes all prompts.

    .PARAMETER Force
        Overwrite existing prompts without prompting.

    .EXAMPLE
        Publish-PromptsToVSCode

        Copies all prompts from project to VS Code user prompts.

    .EXAMPLE
        Publish-PromptsToVSCode -Prompts "changelog conventional-commit"

        Copies specific prompts.
    #>

    Write-Host "Publishing prompts to VS Code..." -ForegroundColor Cyan
    Write-Output "Publishing prompts to VS Code..."

    $projectPromptsPath = Join-Path $PSScriptRoot "..\..\prompts"
    $vscodePromptsPaths = @(
        (Join-Path $env:APPDATA "Code\User\prompts"),
        (Join-Path $env:APPDATA "Code - Insiders\User\prompts")
    )

    # Ensure project prompts directory exists
    if (-not (Test-Path $projectPromptsPath)) {
        throw "Project prompts directory not found: $projectPromptsPath"
    }

    # Create VS Code prompts directories if they don't exist
    foreach ($path in $vscodePromptsPaths) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            Write-Host "Created VS Code prompts directory: $path" -ForegroundColor Green
        }
    }

    # Get prompt files to publish
    $promptFiles = Get-ChildItem -Path $projectPromptsPath -Filter "*.prompt.md"
    $promptNames = $Prompts -split ' ' | Where-Object { $_.Trim() }
    if ($promptNames) {
        $promptFiles = $promptFiles | Where-Object {
            $baseName = $_.Name -replace '\.prompt\.md$'
            $promptNames | Where-Object { $baseName -like $_ } | Select-Object -First 1
        }
    }

    if ($promptFiles.Count -eq 0) {
        Write-Host "No prompt files found to publish." -ForegroundColor Yellow
        return
    }

    Write-Host "Publishing $($promptFiles.Count) prompt file(s)..." -ForegroundColor Cyan
    Write-Output "Publishing $($promptFiles.Count) prompt file(s)..."

    foreach ($promptFile in $promptFiles) {
        $sourcePath = $promptFile.FullName

        foreach ($path in $vscodePromptsPaths) {
            $destinationPath = Join-Path $path $promptFile.Name

            # Check if prompt already exists
            $exists = Test-Path $destinationPath

            if ($exists -and -not $Force) {
                $edition = if ($path -like "*Insiders*") { "Insiders" } else { "Stable" }
                    $msg = "Prompt '$($promptFile.BaseName)' already exists in VS Code $edition. Overwrite? (y/N)"
                    Write-Host $msg -ForegroundColor Yellow
                    Write-Output $msg
                    $overwrite = Read-Host "Prompt '$($promptFile.BaseName)' already exists in VS Code $edition. Overwrite? (y/N)"
                    if ($overwrite -notmatch "^[Yy]") {
                        $skipMsg = "Skipping $($promptFile.BaseName) for VS Code $edition"
                        Write-Host $skipMsg -ForegroundColor Yellow
                        Write-Output $skipMsg
                        continue
                    }
                }

            try {
                Copy-Item -Path $sourcePath -Destination $destinationPath -Force
                $edition = if ($path -like "*Insiders*") { "Insiders" } else { "Stable" }
                $msg = "Published: $($promptFile.BaseName) to VS Code $edition"
                Write-Host $msg -ForegroundColor Green
                Write-Output $msg
            }
            catch {
                Write-Error "Failed to publish $($promptFile.BaseName) to $path : $_"
            }
        }
    }

    Write-Host "Prompt publishing completed." -ForegroundColor Cyan
    Write-Output "Prompt publishing completed."
}

# Execute the main function when the script is loaded/executed.
# Previously we protected this call with a check on $MyInvocation.InvocationName,
# but when the script is invoked via the `&` operator (as the wrapper does) the
# invocation name becomes simply "&" and the guard prevented the function from
# running.  Unconditionally calling the function preserves intuitive behaviour in
# all invocation scenarios.
Publish-PromptsToVSCode
