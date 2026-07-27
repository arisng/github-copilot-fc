[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory, ParameterSetName = 'ByPath')]
    [string]$WorktreePath,

    [Parameter(Mandatory, ParameterSetName = 'ByBranch')]
    [string]$Branch,

    [string]$BaseBranch = 'main',

    [switch]$DeleteBranch,

    [switch]$Force
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Invoke-Git {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $output = & git @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw (("git {0}{1}{2}") -f ($Arguments -join ' '), [Environment]::NewLine, ($output -join [Environment]::NewLine))
    }

    return $output
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

function Test-MergedIntoBase {
    param(
        [Parameter(Mandatory)][string]$CandidateBranch,
        [Parameter(Mandatory)][string]$TargetBranch
    )

    & git merge-base --is-ancestor $CandidateBranch $TargetBranch 2>$null
    return $LASTEXITCODE -eq 0
}

# ── Resolve worktree from branch name or path ─────────────────────────────
$worktreeList = Get-WorktreeInfo
$byBranch = $null
$byPath = $null

if ($Branch) {
    $byBranch = $worktreeList | Where-Object { $_.Branch -eq $Branch } | Select-Object -First 1
}

if ($WorktreePath) {
    $resolvedPath = [System.IO.Path]::GetFullPath($WorktreePath)
    $byPath = $worktreeList | Where-Object { [System.IO.Path]::GetFullPath($_.Path) -eq $resolvedPath } | Select-Object -First 1
}

$selected = if ($byBranch -and $byPath) {
    if ($byBranch.Path -ne $byPath.Path -or $byBranch.Branch -ne $byPath.Branch) {
        throw 'The supplied -Branch and -WorktreePath refer to different worktrees.'
    }
    $byBranch
}
elseif ($byBranch) {
    $byBranch
}
elseif ($byPath) {
    $byPath
}
else {
    $identifier = if ($Branch) { "branch '$Branch'" } else { "path '$WorktreePath'" }
    throw "No worktree found for $identifier."
}

$resolvedBranch = $selected.Branch
$resolvedWorktreePath = $selected.Path

# ── Verify branch is merged (unless forced) ───────────────────────────────
if ($DeleteBranch -and -not $Force -and -not (Test-MergedIntoBase -CandidateBranch $resolvedBranch -TargetBranch $BaseBranch)) {
    throw "Branch '$resolvedBranch' is not merged into '$BaseBranch'. Re-run with -Force only if you intend to discard it."
}

# ── Remove worktree ──────────────────────────────────────────────────────
$removeArgs = if ($Force) {
    @('worktree', 'remove', '--force', $resolvedWorktreePath)
}
else {
    @('worktree', 'remove', $resolvedWorktreePath)
}

if ($PSCmdlet.ShouldProcess($resolvedWorktreePath, 'Remove linked worktree')) {
    Invoke-Git -Arguments $removeArgs | Out-Null
    Invoke-Git -Arguments @('worktree', 'prune') | Out-Null
}

# ── Delete local branch (optional) ────────────────────────────────────────
if ($DeleteBranch) {
    $deleteArgs = if ($Force) {
        @('branch', '-D', $resolvedBranch)
    }
    else {
        @('branch', '-d', $resolvedBranch)
    }

    if ($PSCmdlet.ShouldProcess($resolvedBranch, 'Delete local branch')) {
        Invoke-Git -Arguments $deleteArgs | Out-Null
    }
}

# ── Output ────────────────────────────────────────────────────────────────
[pscustomobject]@{
    Branch = $resolvedBranch
    WorktreePath = $resolvedWorktreePath
    DeletedBranch = [bool]$DeleteBranch
    Forced = [bool]$Force
}
