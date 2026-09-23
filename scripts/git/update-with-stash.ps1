<#
.SYNOPSIS
    Stashes all local changes, pulls the latest remote commits, then restores the changes.

.DESCRIPTION
    Runs the chain: git stash push -u -> git pull -> git stash pop.
    If the pull fails, the stash is still restored before exiting non-zero,
    so the working tree never remains hidden behind a stash.

.PARAMETER StashMessage
    Optional message attached to the stash entry for easy identification.

.PARAMETER PullArgs
    Optional extra arguments forwarded to git pull (e.g. --rebase, --ff-only).

.EXAMPLE
    ./scripts/git/update-with-stash.ps1

.EXAMPLE
    ./scripts/git/update-with-stash.ps1 -PullArgs '--ff-only'
#>
[CmdletBinding()]
param(
    [string]$StashMessage = 'auto-stash before pull',
    [string[]]$PullArgs = @()
)

$ErrorActionPreference = 'Stop'

function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)

    Write-Host ">> git $($GitArgs -join ' ')" -ForegroundColor Cyan
    git @GitArgs
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArgs -join ' ') failed with exit code $LASTEXITCODE"
    }
}

Push-Location $PSScriptRoot\..\..
try {
    # Only stash if there is something to stash; otherwise pop would fail below.
    $status = git status --porcelain
    if ($LASTEXITCODE -ne 0) { throw "git status failed with exit code $LASTEXITCODE" }
    $hasChanges = [bool]($status | Where-Object { $_ })

    if ($hasChanges) {
        Invoke-Git stash push -u -m $StashMessage
    }
    else {
        Write-Host '>> no local changes to stash' -ForegroundColor Yellow
    }

    try {
        Invoke-Git pull @PullArgs
    }
    catch {
        # Always bring local work back, even when the pull fails.
        if ($hasChanges) {
            Write-Host '>> pull failed, restoring stashed changes' -ForegroundColor Red
            git stash pop
        }
        throw
    }

    if ($hasChanges) {
        Invoke-Git stash pop
    }

    Write-Host '>> stash, pull, and unstash completed' -ForegroundColor Green
}
finally {
    Pop-Location
}
