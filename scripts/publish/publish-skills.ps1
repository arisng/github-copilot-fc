param(
    [Parameter(Mandatory = $false)]
    [string[]]$Skills,

    [Parameter(Mandatory = $false)]
    [ValidateSet('copilot', 'codex', 'claude')]
    [string[]]$Targets = @('copilot'),

    # force mode is now the default.  use -NoForce to opt out when you really
    # want to preserve an existing copy instead of overwriting it.
    [Parameter(Mandatory = $false)]
    [switch]$Force = $true,

    # helper switch allowing caller to disable force explicitly. this is
    # mutually exclusive with -Force but makes the default behaviour easier to
    # reason about: if you run the script without any switches it will
    # overwrite existing skills.
    [Parameter(Mandatory = $false)]
    [switch]$NoForce,

    [Parameter(Mandatory = $false)]
    [switch]$SkipWSL
)

. "$PSScriptRoot/wsl-helpers.ps1"

function Publish-SkillsToPersonal {
    <#
    .SYNOPSIS
        Publishes skills from the workspace to personal skills folders.

    .DESCRIPTION
        Copies skills from the workspace skills/ folder to the user's personal
        skills folders (.claude, .codex, .copilot) for reuse across all projects.
        Automatically detects and publishes to WSL if available.

    .PARAMETER Skills
        Array of skill names to publish. If empty, publishes all skills.

    .PARAMETER Targets
        Personal skill targets to publish to. Defaults to `copilot` only.
        Valid values: `copilot`, `codex`, `claude`.

    .PARAMETER Force
        Overwrite existing skills.  This flag is **on by default**; the script
        will behave as if -Force was passed unless you also specify -NoForce.

    .PARAMETER NoForce
        Prevent overwriting existing skills.  This is the opposite of -Force and
        is provided so that callers can explicitly disable the default behaviour.

    .PARAMETER SkipWSL
        Skip publishing to WSL (Windows-only mode).

    .EXAMPLE
        Publish-SkillsToPersonal

        Copies all skills from the workspace to personal folders (Windows and WSL if available).

    .EXAMPLE
        Publish-SkillsToPersonal -Skills diataxis,beads

        Publishes only the 'diataxis' and 'beads' skills to Copilot.

    .EXAMPLE
        Publish-SkillsToPersonal -Targets copilot,codex,claude

        Publishes skills to all supported personal targets on Windows and WSL.

    .EXAMPLE
        Publish-SkillsToPersonal -Force

        Overwrites existing skills in both Windows and WSL.

    .EXAMPLE
        Publish-SkillsToPersonal -SkipWSL

        Publishes skills to Windows only, skipping WSL.
    #>

    # interpret the combination of Force/NoForce switches
    if ($NoForce) { $Force = $false }

    $targetList = @()
    foreach ($target in $Targets) {
        $targetList += @($target -split ',') | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ -ne '' }
    }
    $targetList = $targetList | Select-Object -Unique

    if ($targetList.Count -eq 0) {
        throw 'At least one publish target must be specified.'
    }

    Write-Host "Publishing skills to personal folders" -ForegroundColor Cyan

    $projectSkillsPath = Join-Path $PSScriptRoot "..\..\skills"
    $windowsTargetMap = [ordered]@{
        copilot = (Join-Path $env:USERPROFILE '.copilot\skills')
        codex   = (Join-Path $env:USERPROFILE '.codex\skills')
        claude  = (Join-Path $env:USERPROFILE '.claude\skills')
    }
    $wslTargetMap = [ordered]@{
        copilot = '.copilot/skills'
        codex   = '.codex/skills'
        claude  = '.claude/skills'
    }

    $personalSkillTargets = @()
    foreach ($target in $targetList) {
        if (-not $windowsTargetMap.Contains($target)) {
            throw "Unsupported publish target: $target"
        }

        $personalSkillTargets += [PSCustomObject]@{
            Name       = $target
            WindowsPath = $windowsTargetMap[$target]
            WslPath    = $wslTargetMap[$target]
        }
    }

    $wslAvailable = $false
    $wslHome = $null

    if (-not $SkipWSL) {
        $wslAvailable = Test-WSLAvailable -WslHome ([ref]$wslHome)
        if ($wslAvailable) {
            Write-Host "WSL detected at home: $wslHome" -ForegroundColor DarkGray
        }
        else {
            Write-Host "WSL not available, skipping WSL publishing" -ForegroundColor Yellow
        }
    }

    # Ensure project skills directory exists
    if (-not (Test-Path $projectSkillsPath)) {
        throw "Project skills directory not found: $projectSkillsPath"
    }

    # Create personal skills directories if they don't exist
    foreach ($target in $personalSkillTargets) {
        if (-not (Test-Path $target.WindowsPath)) {
            New-Item -ItemType Directory -Path $target.WindowsPath -Force | Out-Null
            Write-Host "Created personal skills directory: $($target.WindowsPath)" -ForegroundColor Green
        }
    }

    # Get skills to publish (skip archived skills folder)
    $skillDirs = Get-ChildItem -Path $projectSkillsPath -Directory | Where-Object { $_.Name -ne '.archived' }
    if ($Skills) {
        # normalize comma-separated input and allow patterns
        $skillList = @()
        foreach ($item in $Skills) {
            $skillList += @($item -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        }
        # filter directories by matching any pattern in skillList
        $skillDirs = $skillDirs | Where-Object {
            $dir = $_
            $skillList | Where-Object { $dir.Name -like $_ } | Select-Object -First 1
        }
        if ($skillDirs.Count -eq 0) {
            Write-Host "Warning: No skills found matching: $($skillList -join ', ')" -ForegroundColor Yellow
            Write-Host "Available skills:" -ForegroundColor Cyan
            Get-ChildItem -Path $projectSkillsPath -Directory | Where-Object { $_.Name -ne '.archived' } | ForEach-Object { Write-Host "  - $($_.Name)" }
            return
        }
    }

    Write-Host "Publishing $($skillDirs.Count) skill(s)" -ForegroundColor Cyan

    foreach ($skillDir in $skillDirs) {
        $sourcePath = $skillDir.FullName

        # Skip skill directories marked as plugin-managed
        $markerFile = Join-Path $sourcePath '.plugin-managed'
        if (Test-Path $markerFile) {
            Write-Host "  SKIP (plugin-managed): $($skillDir.Name) — managed via plugin, use publish-plugins.ps1 instead" -ForegroundColor Yellow
            continue
        }

        # Publish to Windows personal folders
        foreach ($target in $personalSkillTargets) {
            $destinationPath = Join-Path $target.WindowsPath $skillDir.Name
            $folder = $target.Name

            # Check if skill already exists
            $exists = Test-Path $destinationPath

            try {
                if ($exists -and -not $Force) {
                    Write-Host "Skipping $($skillDir.Name) for $folder (already exists). Use -Force (default) to overwrite or -NoForce to skip." -ForegroundColor Yellow
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

        # Publish to WSL
        if ($wslAvailable) {
            foreach ($target in $personalSkillTargets) {
                $wslTargetPath = "$wslHome/$($target.WslPath)/$($skillDir.Name)"
                $agent = $target.Name

                try {
                    # Check if skill exists in WSL
                    $existsInWsl = Invoke-WSLCommand -Command "test -d '$wslTargetPath' && echo 'exists' || echo 'notfound'" -SuppressStderr

                    if ($existsInWsl -eq 'exists' -and -not $Force) {
                        Write-Host "Skipping $($skillDir.Name) for WSL/$agent (already exists). Use -Force to overwrite." -ForegroundColor Yellow
                        continue
                    }

                    $copiedToWsl = Copy-ToWSL -Source $sourcePath -Destination $wslTargetPath -Recurse

                    if ($copiedToWsl) {
                        Write-Host "Copied: $($skillDir.Name) to WSL/$agent" -ForegroundColor Green
                    } else {
                        Write-Error "Failed to copy $($skillDir.Name) to WSL/$agent (cp exited with code $LASTEXITCODE)"
                    }
                }
                catch {
                    Write-Error "Failed to publish $($skillDir.Name) to WSL/$agent : $_"
                }
            }
        }
    }

    Write-Host "Skill publishing completed." -ForegroundColor Cyan
    if ($wslAvailable) {
        Write-Host "Published to both Windows and WSL." -ForegroundColor Cyan
    }
    else {
        Write-Host "Published to Windows only (WSL not detected)." -ForegroundColor Cyan
    }
}

# Execute the skills publisher unconditionally; the previous guard prevented
# invocation when the script was called with the `&` operator.
Publish-SkillsToPersonal
