param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Copy', 'Link', 'Sync')]
    [string]$Method,

    [Parameter(Mandatory = $false)]
    [string[]]$Skills,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

function Publish-SkillsToPersonal {
    <#
    .SYNOPSIS
        Publishes skills from the project factory to personal skills folder.

    .DESCRIPTION
        Copies or links skills from the project's .claude/skills/ folder to the user's personal
        ~/.claude/skills/ folder for reuse across all projects.

    .PARAMETER Method
        The publishing method: 'Copy', 'Link', or 'Sync'

    .PARAMETER Skills
        Array of skill names to publish. If empty, publishes all skills.

    .PARAMETER Force
        Overwrite existing skills without prompting.

    .EXAMPLE
        Publish-SkillsToPersonal -Method Copy

        Copies all skills from project to personal folder.

    .EXAMPLE
        Publish-SkillsToPersonal -Method Link -Skills "git-committer", "issue-writer"

        Creates symbolic links for specific skills.
    #>

    Write-Host "Script started with Method: $Method" -ForegroundColor Cyan

    $projectSkillsPath = Join-Path $PSScriptRoot "..\.claude\skills"
    $personalSkillsPath = Join-Path $env:USERPROFILE ".claude\skills"

    # Ensure project skills directory exists
    if (-not (Test-Path $projectSkillsPath)) {
        throw "Project skills directory not found: $projectSkillsPath"
    }

    # Create personal skills directory if it doesn't exist
    if (-not (Test-Path $personalSkillsPath)) {
        New-Item -ItemType Directory -Path $personalSkillsPath -Force | Out-Null
        Write-Host "Created personal skills directory: $personalSkillsPath" -ForegroundColor Green
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

    Write-Host "Publishing $($skillDirs.Count) skill(s) using method: $Method" -ForegroundColor Cyan

    foreach ($skillDir in $skillDirs) {
        $sourcePath = $skillDir.FullName
        $destinationPath = Join-Path $personalSkillsPath $skillDir.Name

        # Check if skill already exists
        $exists = Test-Path $destinationPath

        if ($exists -and -not $Force) {
            $overwrite = Read-Host "Skill '$($skillDir.Name)' already exists. Overwrite? (y/N)"
            if ($overwrite -notmatch "^[Yy]") {
                Write-Host "Skipping $($skillDir.Name)" -ForegroundColor Yellow
                continue
            }
        }

        try {
            switch ($Method) {
                'Copy' {
                    if ($exists) { Remove-Item -Path $destinationPath -Recurse -Force }
                    Copy-Item -Path $sourcePath -Destination $destinationPath -Recurse -Force
                    Write-Host "Copied: $($skillDir.Name)" -ForegroundColor Green
                }
                'Link' {
                    if ($exists) { Remove-Item -Path $destinationPath -Force }
                    # Create symbolic link (requires admin privileges on Windows)
                    $target = $sourcePath
                    $link = $destinationPath
                    New-Item -ItemType SymbolicLink -Path $link -Target $target -Force | Out-Null
                    Write-Host "Linked: $($skillDir.Name)" -ForegroundColor Green
                }
                'Sync' {
                    # Use robocopy for incremental sync
                    $robocopyArgs = @(
                        "`"$sourcePath`"",
                        "`"$destinationPath`"",
                        "/MIR",  # Mirror directory tree
                        "/NJH",  # No job header
                        "/NJS"   # No job summary
                    )
                    $result = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -NoNewWindow -Wait -PassThru
                    if ($result.ExitCode -le 3) { # Robocopy exit codes: 0-3 are success
                        Write-Host "Synced: $($skillDir.Name)" -ForegroundColor Green
                    } else {
                        Write-Warning "Sync failed for $($skillDir.Name) (Exit code: $($result.ExitCode))"
                    }
                }
            }
        }
        catch {
            Write-Error "Failed to publish $($skillDir.Name): $_"
        }
    }

    Write-Host "Skill publishing completed." -ForegroundColor Cyan
}

# If script is run directly, execute the function
if ($MyInvocation.InvocationName -like "*publish-skills.ps1") {
    Publish-SkillsToPersonal
}