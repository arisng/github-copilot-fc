param(
    [Parameter(Mandatory = $false)]
    [string[]]$Skills,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

function Publish-SkillsToPersonal {
    <#
    .SYNOPSIS
        Publishes skills from the workspace to personal skills folders.

    .DESCRIPTION
        Copies skills from the workspace skills/ folder to the user's personal
        skills folders (.claude, .codex, .copilot) for reuse across all projects.

    .PARAMETER Skills
        Array of skill names to publish. If empty, publishes all skills.

    .PARAMETER Force
        Overwrite existing skills.

    .EXAMPLE
        Publish-SkillsToPersonal

        Copies all skills from the workspace to personal folders.
    #>

    Write-Host "Publishing skills to personal folders" -ForegroundColor Cyan

    $projectSkillsPath = Join-Path $PSScriptRoot "..\..\skills"
    $personalSkillsPaths = @(
        (Join-Path $env:USERPROFILE ".claude\skills"),
        (Join-Path $env:USERPROFILE ".codex\skills"),
        (Join-Path $env:USERPROFILE ".copilot\skills")
    )

    # Ensure project skills directory exists
    if (-not (Test-Path $projectSkillsPath)) {
        throw "Project skills directory not found: $projectSkillsPath"
    }

    # Create personal skills directories if they don't exist
    foreach ($path in $personalSkillsPaths) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            Write-Host "Created personal skills directory: $path" -ForegroundColor Green
        }
    }

    # Get skills to publish
    $skillDirs = Get-ChildItem -Path $projectSkillsPath -Directory
    if ($Skills) {
        $skillDirs = $skillDirs | Where-Object { $_.Name -in $Skills }
    }

    if ($skillDirs.Count -eq 0) {
        Write-Host "No skills found to publish." -ForegroundColor Yellow
        return
    }

    Write-Host "Publishing $($skillDirs.Count) skill(s)" -ForegroundColor Cyan

    foreach ($skillDir in $skillDirs) {
        $sourcePath = $skillDir.FullName

        foreach ($path in $personalSkillsPaths) {
            $destinationPath = Join-Path $path $skillDir.Name
            $folder = Split-Path (Split-Path $path -Parent) -Leaf

            # Check if skill already exists
            $exists = Test-Path $destinationPath

            try {
                if ($exists -and -not $Force) {
                    Write-Host "Skipping $($skillDir.Name) for $folder (already exists). Use -Force to overwrite." -ForegroundColor Yellow
                    continue
                }

                if ($exists) { Remove-Item -Path $destinationPath -Recurse -Force }
                Copy-Item -Path $sourcePath -Destination $destinationPath -Recurse -Force
                Write-Host "Copied: $($skillDir.Name) to $folder" -ForegroundColor Green
            }
            catch {
                Write-Error "Failed to publish $($skillDir.Name) to $folder : $_"
            }
        }
    }

    Write-Host "Skill publishing completed." -ForegroundColor Cyan
}

# If script is run directly, execute the function
if ($MyInvocation.InvocationName -like "*publish-skills.ps1") {
    Publish-SkillsToPersonal
}