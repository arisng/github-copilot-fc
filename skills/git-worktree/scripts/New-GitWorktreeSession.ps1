[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$Slug,

    [ValidateSet('feature', 'openspec', 'release', 'hotfix', 'branch')]
    [string]$Mode = 'feature',

    [string]$BaseBranch = 'develop',

    [string]$SessionId,

    [string]$WorktreeRoot = '.worktrees',

    [string]$Branch,

    [string]$WorktreeName,

    [switch]$SyncBase,

    [switch]$Bootstrap
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

function Test-GitRef {
    param([Parameter(Mandatory)][string]$RefName)

    & git show-ref --verify --quiet $RefName 2>$null
    return $LASTEXITCODE -eq 0
}

function Normalize-Token {
    param([Parameter(Mandatory)][string]$Value)

    $normalized = $Value.ToLowerInvariant()
    $normalized = $normalized -replace '[^a-z0-9]+', '-'
    $normalized = $normalized.Trim('-')

    if ([string]::IsNullOrWhiteSpace($normalized)) {
        throw "Value '$Value' does not produce a valid token."
    }

    return $normalized
}

$repoRoot = [string](Invoke-Git -Arguments @('rev-parse', '--show-toplevel') | Select-Object -First 1)
$slugToken = Normalize-Token -Value $Slug
$sessionToken = if ([string]::IsNullOrWhiteSpace($SessionId)) { $null } else { Normalize-Token -Value $SessionId }
$today = Get-Date -Format 'yyMMdd'

function Join-NameParts {
    param([string[]]$Parts)

    return (($Parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join '-')
}

if ($Mode -eq 'branch' -and [string]::IsNullOrWhiteSpace($Branch)) {
    throw 'Specify -Branch when using -Mode branch.'
}

$resolvedBranch = if ($Branch) {
    $Branch
}
else {
    switch ($Mode) {
        'feature' { "feature/$(Join-NameParts -Parts @($today, $slugToken, $sessionToken))" }
        'openspec' { "openspec/$(Join-NameParts -Parts @($today, $slugToken, $sessionToken))" }
        'release' { "release/$slugToken" }
        'hotfix' { "hotfix/$slugToken" }
        'branch' { throw 'Branch mode requires -Branch.' }
        default { throw "Unsupported mode '$Mode'." }
    }
}

$resolvedWorktreeName = if ($WorktreeName) {
    $WorktreeName
}
else {
    $resolvedBranch -replace '[\\/]+', '-'
}

$worktreeRootPath = Join-Path $repoRoot $WorktreeRoot
$worktreePath = Join-Path $worktreeRootPath $resolvedWorktreeName

if (-not (Test-GitRef -RefName "refs/heads/$BaseBranch") -and -not (Test-GitRef -RefName "refs/remotes/origin/$BaseBranch")) {
    throw "Base branch '$BaseBranch' does not exist locally or on origin."
}

if (Test-GitRef -RefName "refs/heads/$resolvedBranch") {
    throw "Branch '$resolvedBranch' already exists."
}

if (Test-Path $worktreePath) {
    throw "Worktree path '$worktreePath' already exists."
}

$startPoint = $BaseBranch

if ($SyncBase) {
    if ($PSCmdlet.ShouldProcess('origin', 'Fetch latest refs')) {
        Invoke-Git -Arguments @('fetch', '--all', '--prune') | Out-Null
    }

    if (-not (Test-GitRef -RefName "refs/remotes/origin/$BaseBranch")) {
        throw "Remote branch 'origin/$BaseBranch' was not found after fetch."
    }

    $startPoint = "origin/$BaseBranch"
}

if ((-not (Test-Path $worktreeRootPath)) -and $PSCmdlet.ShouldProcess($worktreeRootPath, 'Create worktree root directory')) {
    New-Item -ItemType Directory -Path $worktreeRootPath | Out-Null
}

if ($PSCmdlet.ShouldProcess($worktreePath, "Create detached worktree from '$startPoint'")) {
    Invoke-Git -Arguments @('worktree', 'add', '--detach', $worktreePath, $startPoint) | Out-Null
}

if ((Test-Path $worktreePath) -and $PSCmdlet.ShouldProcess($resolvedBranch, "Create branch inside '$worktreePath'")) {
    Invoke-Git -Arguments @('switch', '-c', $resolvedBranch) -WorkingDirectory $worktreePath | Out-Null
}

if ($Bootstrap.IsPresent -and (Test-Path $worktreePath)) {
    if ($PSCmdlet.ShouldProcess($worktreePath, 'Run dotnet restore and dotnet build')) {
        & dotnet restore (Join-Path $worktreePath 'src/FSH.Framework.slnx')
        if ($LASTEXITCODE -ne 0) {
            throw 'dotnet restore failed.'
        }

        & dotnet build (Join-Path $worktreePath 'src/FSH.Framework.slnx')
        if ($LASTEXITCODE -ne 0) {
            throw 'dotnet build failed.'
        }
    }
}

[pscustomobject]@{
    BaseBranch = $BaseBranch
    Branch = $resolvedBranch
    WorktreePath = $worktreePath
    StartPoint = $startPoint
    CreationMode = 'worktree-first'
    Bootstrapped = (($Bootstrap.IsPresent) -and (Test-Path $worktreePath))
}