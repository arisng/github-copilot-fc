<#
.SYNOPSIS
    Run the skill Pester suites in a Linux container - the ubuntu-latest
    parity lane for the local gate.
.DESCRIPTION
    Retro 2026-11-21: `task check` lints on the Windows host while CI runs
    ubuntu-latest, so Windows-only assumptions in the suites (sqlite3.exe,
    $env:TEMP, fixture repos without a git identity) passed the local gate
    and failed 32/145 Pester tests in CI. This task runs the same Pester
    scan workspace-check.ps1 runs, inside a Linux container, so the local
    lane covers what the cloud lane executes.

    Two roles, one file:
      host (Windows/macOS): launches docker with the repo mounted at /repo
        and a named volume persisting installed Pester modules.
      container (Linux): installs git + sqlite3 (the suites shell out to
        both), installs Pester when the module volume is empty, runs the
        suites, prints failing test names, exits non-zero on failure.

    Needs docker, a network fetch on first run (image pull + Pester), and
    the repo checked out; without docker the task fails with a pointer
    rather than skipping, because asking for the Linux lane and silently
    not running it would read as a green.
.EXAMPLE
    task check:linux
.EXAMPLE
    pwsh -NoProfile -File scripts/workspace/linux-pester.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$image = 'mcr.microsoft.com/powershell:7.4-ubuntu-22.04'
$moduleVolume = 'fc-pwsh-modules'

if ($IsLinux) {
    # --- container role ---------------------------------------------------
    $mounted = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    if (-not (Test-Path (Join-Path $mounted 'skills'))) {
        Write-Output '[FAIL] linux-pester: repo mount missing - expected /repo with a skills/ directory'
        exit 1
    }

    # The suites shell out to git (fixtures init repositories), sqlite3
    # (daily-report fixtures) and python3 (export-copilot-transcript.py);
    # the powershell image ships none of them.
    & apt-get update -qq 2>$null
    & apt-get install -y -qq git sqlite3 python3 2>$null | Out-Null
    foreach ($tool in 'git', 'sqlite3', 'python3') {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            Write-Output "[FAIL] linux-pester: $tool unavailable in the container (apt-get install failed?)"
            exit 1
        }
    }

    # Copy out of the mount and normalize to LF: a Windows worktree is CRLF
    # (core.autocrlf) while CI checks out the index's LF, and the transcript
    # tests are line-ending sensitive on Linux. The mounted worktree stays
    # untouched; the copy is what ubuntu-latest would see.
    $repoRoot = '/tmp/linux-pester-repo'
    if (Test-Path $repoRoot) { Remove-Item -Recurse -Force $repoRoot }
    New-Item -ItemType Directory -Path $repoRoot | Out-Null
    Get-ChildItem -LiteralPath $mounted -Force | Copy-Item -Destination $repoRoot -Recurse -Force
    Get-ChildItem -LiteralPath $repoRoot -Recurse -File |
        Where-Object { $_.Extension -in '.ps1', '.psm1', '.psd1' } |
        ForEach-Object {
            $text = [IO.File]::ReadAllText($_.FullName)
            if ($text.Contains("`r`n")) { [IO.File]::WriteAllText($_.FullName, ($text -replace "`r`n", "`n")) }
        }

    if (-not (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version.Major -ge 5 })) {
        Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck
    }

    Push-Location $repoRoot
    try {
        # -Force + separator-agnostic exclude: mirrors what the gate's linter
        # and the Windows lane see (dot-directories are skipped on Linux
        # without -Force), so both lanes scan the same test set.
        $testFiles = @(Get-ChildItem -Path 'skills', 'scripts' -Recurse -Force -Filter '*.Tests.ps1' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '[/\\]\.archived[/\\]' })
        $dirs = @($testFiles | ForEach-Object { $_.DirectoryName } | Sort-Object -Unique)
        Write-Output "[....] linux-pester: $($testFiles.Count) test file(s) in $($dirs.Count) dir(s), Linux container"
        $result = Invoke-Pester -Path $dirs -PassThru -Output Normal 3>$null 6>$null
    }
    finally {
        Pop-Location
    }
    if ($result.FailedCount -gt 0) {
        $result.Failed | ForEach-Object {
            Write-Output "[FAIL] linux-pester: $($_.ExpandedPath)"
            @($_.ErrorRecord | Out-String) -join '' -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 5 |
                ForEach-Object { Write-Output "       $($_.Trim())" }
        }
        Write-Output "[FAIL] linux-pester: $($result.FailedCount) failed / $($result.TotalCount) Pester tests on Linux"
        exit 1
    }
    Write-Output "[PASS] linux-pester: $($result.PassedCount) Pester tests green on Linux"
    exit 0
}

# --- host role -----------------------------------------------------------
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Output '[FAIL] linux-pester: docker not found on PATH - the Linux lane needs a container runtime (Docker Desktop or engine)'
    exit 1
}
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$mount = "$($repoRoot.Replace('\', '/')):/repo"
Write-Output "[....] linux-pester: running $image (first run pulls the image)"
& docker run --rm `
    -v $mount `
    -v "${moduleVolume}:/root/.local/share/powershell/Modules" `
    $image pwsh -NoProfile -File /repo/scripts/workspace/linux-pester.ps1
exit $LASTEXITCODE
