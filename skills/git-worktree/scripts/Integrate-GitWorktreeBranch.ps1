[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$Branch,

    [string]$BaseBranch = 'develop',

    [ValidateSet('NoFastForward', 'FastForwardOnly', 'Squash')]
    [string]$MergeMode = 'FastForwardOnly',

    [string[]]$ValidationCommand,

    [switch]$SkipFetch,

    [switch]$SkipRebase
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Invoke-Git {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [string]$WorkingDirectory
    )

    $output = if ($WorkingDirectory) {
        & git -C $WorkingDirectory @Arguments 2>&1
    }
    else {
        & git @Arguments 2>&1
    }

    if ($LASTEXITCODE -ne 0) {
        throw (("git {0}{1}{2}") -f ($Arguments -join ' '), [Environment]::NewLine, ($output -join [Environment]::NewLine))
    }

    return $output
}

function Get-RelevantStatusLines {
    $statusLines = Invoke-Git -Arguments @('status', '--porcelain')
    return $statusLines | Where-Object {
        $_ -notmatch '^\?\? \.worktrees/?$' -and $_ -notmatch '^\?\? \.worktrees/'
    }
}

function Get-WorktreeInfo {
    $lines = Invoke-Git -Arguments @('worktree', 'list', '--porcelain')
    $items = @()
    $current = [ordered]@{}

    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            if ($current.Contains('Path')) {
                $items += [pscustomobject]$current
                $current = [ordered]@{}
            }

            continue
        }

        if ($line.StartsWith('worktree ')) {
            $current.Path = $line.Substring(9)
            continue
        }

        if ($line.StartsWith('branch ')) {
            $current.Branch = $line.Substring(7) -replace '^refs/heads/', ''
        }
    }

    if ($current.Contains('Path')) {
        $items += [pscustomobject]$current
    }

    return $items
}

$dirtyLines = Get-RelevantStatusLines
if ($dirtyLines) {
    throw "Primary repo has local changes. Commit, stash, or clean them before integrating.`n$($dirtyLines -join [Environment]::NewLine)"
}

$worktreeInfo = Get-WorktreeInfo | Where-Object { $_.Branch -eq $Branch } | Select-Object -First 1
if (-not $worktreeInfo -and -not $SkipRebase) {
    throw "Branch '$Branch' is not linked to a worktree. Reattach it or rerun with -SkipRebase."
}

if (-not $SkipFetch -and $PSCmdlet.ShouldProcess('origin', 'Fetch latest refs')) {
    Invoke-Git -Arguments @('fetch', '--all', '--prune') | Out-Null
}

if ($PSCmdlet.ShouldProcess($BaseBranch, 'Update base branch from origin')) {
    Invoke-Git -Arguments @('checkout', $BaseBranch) | Out-Null
    Invoke-Git -Arguments @('merge', '--ff-only', "origin/$BaseBranch") | Out-Null
}

if (-not $SkipRebase -and $PSCmdlet.ShouldProcess($Branch, "Rebase onto '$BaseBranch'")) {
    Invoke-Git -Arguments @('rebase', $BaseBranch) -WorkingDirectory $worktreeInfo.Path | Out-Null
}

$mergeArguments = switch ($MergeMode) {
    'NoFastForward' { @('merge', '--no-ff', '--no-edit', $Branch) }
    'FastForwardOnly' { @('merge', '--ff-only', $Branch) }
    'Squash' { @('merge', '--squash', $Branch) }
    default { throw "Unsupported merge mode '$MergeMode'." }
}

if ($PSCmdlet.ShouldProcess($BaseBranch, "Merge '$Branch' with mode '$MergeMode'")) {
    Invoke-Git -Arguments $mergeArguments | Out-Null
}

if ($ValidationCommand) {
    foreach ($command in $ValidationCommand) {
        Write-Host "Running validation: $command"
        Invoke-Expression $command
        if ((-not $?) -or ($LASTEXITCODE -ne 0)) {
            throw "Validation command failed: $command"
        }
    }
}

[pscustomobject]@{
    BaseBranch = $BaseBranch
    Branch = $Branch
    MergeMode = $MergeMode
    WorktreePath = $worktreeInfo.Path
    Rebased = -not $SkipRebase
    Validated = [bool]$ValidationCommand
}