<#
.SYNOPSIS
    Resolves the GitHub Copilot CLI path for COPILOT_CLI_PATH (waza copilot-sdk executor).

.DESCRIPTION
    This is an OPT-IN OVERRIDE tool. waza's default behavior (COPILOT_CLI_PATH unset)
    is to spawn its bundled CLI (v1.0.85 for waza 0.38.7), which is the recommended
    default for eval reproducibility. Use this script only when you need to force a
    specific machine CLI.

    Resolution priority:
      1. $env:COPILOT_CLI_PATH when already usable (explicit user override wins).
      2. First runnable copilot executable on PATH (.exe on Windows; .ps1 and
         extensionless shims are skipped because they are not executable images
         for CreateProcess/Go os/exec, and .cmd launchers are unreliable there).
      3. Known install locations (npm global platform binary).
      4. With -InstallFallback and nothing detected: winget install, trying the
         MSIX package GitHub.Copilot.CLI first, then the official portable
         package GitHub.Copilot, then re-detect.

    Mirrors waza validation (internal/execution/sdkclient.go): the path must exist
    and must not be a directory, else waza errors "COPILOT_CLI_PATH ... is not
    usable". When COPILOT_CLI_PATH ends up unset, waza runs its bundled CLI and
    never falls back to PATH.

    The --version probe is bounded by a 10-second timeout; a hung candidate is
    treated as failed and resolution moves on.

    Emits the resolved path as the only stdout line (warnings are re-emitted on
    stderr at the process boundary, so cross-process capture is safe too):

        $env:COPILOT_CLI_PATH = & skills/waza-cli/scripts/Resolve-CopilotCliPath.ps1

.PARAMETER InstallFallback
    Allow a winget install when no Copilot CLI is detected (Windows only).

.PARAMETER Persist
    Also write the result to the user-level COPILOT_CLI_PATH environment variable.

.PARAMETER SkipProbe
    Skip the `--version` smoke probe of candidate binaries.

.OUTPUTS
    String. Resolved absolute path; nothing (exit 1) when not found.

.EXAMPLE
    pwsh -NoProfile -File Resolve-CopilotCliPath.ps1
#>
[CmdletBinding()]
param(
    [switch]$InstallFallback,
    [switch]$Persist,
    [switch]$SkipProbe
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# $IsWindows only exists on PowerShell 7+; derive it for Windows PowerShell 5.1 too.
$script:OnWindows = ($env:OS -eq 'Windows_NT')

function Test-CopilotCliCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path,
        [switch]$SkipProbe,
        [int]$ProbeTimeoutMs = 10000
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    if (Test-Path -LiteralPath $Path -PathType Container) { return $false }  # waza rejects directories
    if ($SkipProbe) { return $true }

    $proc = $null
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $Path
        $startInfo.Arguments = '--version'
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true

        $proc = [System.Diagnostics.Process]::Start($startInfo)
        if (-not $proc.WaitForExit($ProbeTimeoutMs)) {
            Write-Verbose "Probe timed out after ${ProbeTimeoutMs}ms: $Path"
            try { $proc.Kill() } catch { Write-Verbose "Kill failed: $_" }
            return $false
        }
        $stdout = $proc.StandardOutput.ReadToEnd()
        return ($proc.ExitCode -eq 0 -and ($stdout -match 'Copilot'))
    }
    catch {
        Write-Verbose "Probe failed for ${Path}: $_"
        return $false
    }
    finally {
        if ($proc) { $proc.Dispose() }
    }
}

function Get-KnownCopilotCliPath {
    [CmdletBinding()]
    param()

    $npm = Get-Command npm -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $npm) { return }

    try { $npmRoot = (& $npm.Source root -g 2>$null | Select-Object -First 1) }
    catch { return }
    if ([string]::IsNullOrWhiteSpace($npmRoot)) { return }

    $binary = if ($script:OnWindows) { 'copilot.exe' } else { 'copilot' }
    $pattern = Join-Path $npmRoot "@github/copilot/node_modules/@github/copilot-*/$binary"
    Get-Item -Path $pattern -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
}

function Get-CopilotCliPathCandidate {
    [CmdletBinding()]
    param([switch]$SkipProbe)

    # 1) explicit override
    $override = [Environment]::GetEnvironmentVariable('COPILOT_CLI_PATH')
    if ($override) {
        if (Test-CopilotCliCandidate -Path $override -SkipProbe:$SkipProbe) {
            Write-Verbose "Using existing COPILOT_CLI_PATH: $override"
            return $override
        }
        Write-Warning "COPILOT_CLI_PATH is set but not usable, re-detecting: $override"
    }

    # 2) PATH executables; skip non-native shims on Windows
    foreach ($command in @(Get-Command copilot -CommandType Application -All -ErrorAction SilentlyContinue)) {
        $candidate = $command.Source
        if ($script:OnWindows -and $candidate -notmatch '\.exe$') {
            Write-Verbose "Skipping non-executable shim: $candidate"
            continue
        }
        if (Test-CopilotCliCandidate -Path $candidate -SkipProbe:$SkipProbe) {
            Write-Verbose "Detected on PATH: $candidate"
            return $candidate
        }
    }

    # 3) known install locations
    foreach ($candidate in @(Get-KnownCopilotCliPath)) {
        if (Test-CopilotCliCandidate -Path $candidate -SkipProbe:$SkipProbe) {
            Write-Verbose "Detected in known location: $candidate"
            return $candidate
        }
    }

    return $null
}

function Invoke-WingetInstall {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)

    Write-Warning "Attempting install: winget install -e --id $Id"
    & winget install -e --id $Id --accept-package-agreements --accept-source-agreements 2>&1 |
        ForEach-Object { Write-Verbose $_ }
    return ($LASTEXITCODE -eq 0)
}

function Install-CopilotCliFallback {
    [CmdletBinding()]
    param()

    if (-not $script:OnWindows) {
        Write-Warning 'No Copilot CLI detected. The automatic fallback targets Windows/MSIX; install manually: npm install -g @github/copilot  (or: curl -fsSL https://gh.io/copilot-install | bash)'
        return $false
    }

    # Requested MSIX package first (not yet published in winget; fails cleanly),
    # then the official portable package from github/copilot-cli README.
    foreach ($id in @('GitHub.Copilot.CLI', 'GitHub.Copilot')) {
        try {
            if (Invoke-WingetInstall -Id $id) { return $true }
        }
        catch {
            Write-Verbose "winget install ${id} failed: $_"
        }
    }
    return $false
}

function Resolve-CopilotCliPath {
    [CmdletBinding()]
    param([switch]$InstallFallback, [switch]$SkipProbe)

    $resolved = Get-CopilotCliPathCandidate -SkipProbe:$SkipProbe
    if (-not $resolved -and $InstallFallback) {
        if (Install-CopilotCliFallback) {
            $resolved = Get-CopilotCliPathCandidate -SkipProbe:$SkipProbe
        }
    }
    if (-not $resolved) {
        Write-Warning 'No Copilot CLI found. COPILOT_CLI_PATH stays unset, so waza will use its bundled CLI. Re-run with -InstallFallback to install one.'
        return $null
    }
    return $resolved
}

# Run main logic only when executed as a file; skip when dot-sourced by tests.
if ($MyInvocation.InvocationName -ne '.') {
    # Capture warning records (stream 3) so stdout carries only the path;
    # re-emit warnings on stderr for cross-process capture safety.
    $collected = @(Resolve-CopilotCliPath -InstallFallback:$InstallFallback -SkipProbe:$SkipProbe 3>&1)
    foreach ($item in $collected) {
        if ($item -is [System.Management.Automation.WarningRecord]) {
            [Console]::Error.WriteLine("WARNING: $($item.Message)")
        }
    }
    $result = $collected | Where-Object { $_ -is [string] } | Select-Object -Last 1
    if (-not $result) { exit 1 }

    if ($Persist) {
        [Environment]::SetEnvironmentVariable('COPILOT_CLI_PATH', $result, 'User')
        Write-Verbose "Persisted user-level COPILOT_CLI_PATH: $result"
    }
    Write-Output $result
    exit 0
}
