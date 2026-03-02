<#
.SYNOPSIS
    Shared WSL utility functions for publish scripts.

.DESCRIPTION
    Provides reusable functions for WSL detection, path conversion,
    and file/directory operations. Designed to be dot-sourced from
    other publish scripts via:

        . "$PSScriptRoot/wsl-helpers.ps1"

    Extracted from proven patterns in publish-skills.ps1 and
    publish-agents.ps1 to prevent copy-paste drift.
#>

function Test-WSLAvailable {
    <#
    .SYNOPSIS
        Tests whether WSL is available and returns the WSL home directory.

    .DESCRIPTION
        Attempts to invoke 'wsl bash -c "echo $HOME"' and checks the exit code.
        Returns $true if WSL is reachable, $false otherwise.

    .PARAMETER WslHome
        Reference variable that receives the WSL home directory path
        (e.g. '/home/user') when WSL is available.

    .OUTPUTS
        [bool] $true if WSL is available, $false otherwise.

    .EXAMPLE
        $wslHome = $null
        if (Test-WSLAvailable -WslHome ([ref]$wslHome)) {
            Write-Host "WSL home: $wslHome"
        }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [ref]$WslHome
    )

    try {
        $home = wsl bash -c 'echo $HOME' 2>$null
        if ($home -and $LASTEXITCODE -eq 0) {
            if ($WslHome) {
                $WslHome.Value = $home
            }
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
}

function Convert-ToWSLPath {
    <#
    .SYNOPSIS
        Converts a Windows path to a WSL mount path.

    .DESCRIPTION
        Transforms a Windows-style path (e.g. 'C:\Users\foo\bar') into
        the equivalent WSL mount path (e.g. '/mnt/c/Users/foo/bar').
        Handles any drive letter, not just C:.

    .PARAMETER Path
        The Windows path to convert.

    .OUTPUTS
        [string] The WSL-compatible mount path.

    .EXAMPLE
        Convert-ToWSLPath -Path 'D:\Projects\my-app'
        # Returns: /mnt/d/Projects/my-app
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $forwardSlashed = $Path -replace '\\', '/'
    return [regex]::Replace($forwardSlashed, '^([A-Za-z]):', {
        param($m)
        "/mnt/" + $m.Groups[1].Value.ToLower()
    })
}

function Copy-ToWSL {
    <#
    .SYNOPSIS
        Copies a file or directory from Windows to a WSL target path.

    .DESCRIPTION
        Creates the parent directory in WSL if needed, then copies the
        source to the target using 'wsl bash -c "cp"'. Supports both
        file and recursive directory copies via the -Recurse switch.
        Writes a warning on failure instead of throwing a terminating error.

    .PARAMETER Source
        The Windows source path to copy from.

    .PARAMETER Destination
        The WSL target path to copy to.

    .PARAMETER Recurse
        Use recursive copy (cp -r) for directories.

    .EXAMPLE
        Copy-ToWSL -Source 'C:\skills\diataxis' -Destination '/home/user/.copilot/skills/diataxis' -Recurse

    .EXAMPLE
        Copy-ToWSL -Source 'C:\agents\meta.agent.md' -Destination '/home/user/.copilot/agents/meta.agent.md'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination,

        [Parameter(Mandatory = $false)]
        [switch]$Recurse
    )

    $wslSource = Convert-ToWSLPath -Path $Source
    $parentDir = $Destination -replace '/[^/]+$', ''
    $cpFlag = if ($Recurse) { "-r" } else { "" }
    $testFlag = if ($Recurse) { "-d" } else { "-f" }

    try {
        # Create parent directory if needed
        wsl bash -c "mkdir -p '$parentDir'" 2>$null

        # Check if target already exists
        $exists = wsl bash -c "test $testFlag '$Destination' && echo 'exists' || echo 'notfound'" 2>$null

        # Remove existing target if present
        if ($exists -eq 'exists') {
            $rmFlag = if ($Recurse) { "-rf" } else { "-f" }
            wsl bash -c "rm $rmFlag '$Destination'" 2>$null
        }

        # Copy source to destination
        wsl bash -c "cp $cpFlag '$wslSource' '$Destination'"

        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Copy to WSL failed for '$Destination' (cp exited with code $LASTEXITCODE)"
            return $false
        }
        return $true
    }
    catch {
        Write-Warning "Copy to WSL failed for '$Destination': $_"
        return $false
    }
}

function Remove-FromWSL {
    <#
    .SYNOPSIS
        Removes a file or directory from WSL.

    .DESCRIPTION
        Deletes the specified path in WSL using 'wsl bash -c "rm"'.
        Supports recursive removal for directories via the -Recurse switch.
        Writes a warning on failure instead of throwing a terminating error.

    .PARAMETER Path
        The WSL path to remove.

    .PARAMETER Recurse
        Use recursive removal (rm -rf) for directories.

    .EXAMPLE
        Remove-FromWSL -Path '/home/user/.copilot/skills/diataxis' -Recurse

    .EXAMPLE
        Remove-FromWSL -Path '/home/user/.copilot/agents/meta.agent.md'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [switch]$Recurse
    )

    $rmFlag = if ($Recurse) { "-rf" } else { "-f" }

    try {
        wsl bash -c "rm $rmFlag '$Path'" 2>$null

        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Remove from WSL failed for '$Path' (rm exited with code $LASTEXITCODE)"
            return $false
        }
        return $true
    }
    catch {
        Write-Warning "Remove from WSL failed for '$Path': $_"
        return $false
    }
}
