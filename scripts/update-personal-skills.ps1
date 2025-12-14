param(
    [Parameter(Mandatory = $false)]
    [switch]$CheckOnly,

    [Parameter(Mandatory = $false)]
    [string[]]$Skills
)

function Update-PersonalSkills {

    $projectSkillsPath = Join-Path $PSScriptRoot "..\skills"
    $personalSkillsPath = Join-Path $env:USERPROFILE ".claude\skills"

    # Ensure directories exist
    if (-not (Test-Path $projectSkillsPath)) {
        throw "Project skills directory not found: $projectSkillsPath"
    }
    if (-not (Test-Path $personalSkillsPath)) {
        Write-Host "No personal skills directory found. Run Publish-SkillsToPersonal first." -ForegroundColor Yellow
        return
    }

    # Get skills to check
    $personalSkillDirs = Get-ChildItem -Path $personalSkillsPath -Directory
    if ($Skills) {
        $personalSkillDirs = $personalSkillDirs | Where-Object { $_.Name -in $Skills }
    }

    $updatesAvailable = @()
    $updatesApplied = @()

    foreach ($personalSkillDir in $personalSkillDirs) {
        $skillName = $personalSkillDir.Name
        $projectSkillPath = Join-Path $projectSkillsPath $skillName
        $personalSkillPath = $personalSkillDir.FullName

        if (-not (Test-Path $projectSkillPath)) {
            Write-Host "Project skill '$skillName' no longer exists in factory." -ForegroundColor Yellow
            continue
        }

        # Compare modification times
        $projectModified = (Get-Item $projectSkillPath).LastWriteTime
        $personalModified = (Get-Item $personalSkillPath).LastWriteTime

        if ($projectModified -gt $personalModified) {
            $updatesAvailable += $skillName

            if (-not $CheckOnly) {
                try {
                    # Remove old version
                    Remove-Item -Path $personalSkillPath -Recurse -Force

                    # Copy new version
                    Copy-Item -Path $projectSkillPath -Destination $personalSkillPath -Recurse -Force

                    $updatesApplied += $skillName
                    Write-Host "Updated: $skillName" -ForegroundColor Green
                }
                catch {
                    Write-Error "Failed to update $skillName`: $_"
                }
            }
        }
    }

    # Summary
    if ($CheckOnly) {
        if ($updatesAvailable.Count -gt 0) {
            Write-Host "`nUpdates available for $($updatesAvailable.Count) skill(s):" -ForegroundColor Cyan
            $updatesAvailable | ForEach-Object { Write-Host "  - $_" -ForegroundColor White }
        } else {
            Write-Host "`nAll skills are up to date." -ForegroundColor Green
        }
    } else {
        if ($updatesApplied.Count -gt 0) {
            Write-Host "`nSuccessfully updated $($updatesApplied.Count) skill(s)." -ForegroundColor Green
        } else {
            Write-Host "`nNo skills needed updating." -ForegroundColor Green
        }
    }
}

# If script is run directly, execute the function
if ($MyInvocation.InvocationName -like "*update-personal-skills.ps1") {
    Update-PersonalSkills
}