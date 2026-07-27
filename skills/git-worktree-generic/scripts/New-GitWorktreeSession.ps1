[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$Slug,

    [ValidateSet('feature', 'fix', 'experiment', 'openspec', 'release', 'hotfix', 'branch')]
    [string]$Mode = 'feature',

    [string]$BaseBranch = 'main',

    [string]$Branch,

    [string]$WorktreeRoot = '.worktrees',

    [string]$WorktreeName,

    [string]$SessionId,

    [switch]$SyncBase,

    [string[]]$BootstrapCommand
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

function Join-NameParts {
    param([string[]]$Parts)

    return (($Parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join '-')
}

# ── Resolve repo root ─────────────────────────────────────────────────────
$repoRoot = [string](Invoke-Git -Arguments @('rev-parse', '--show-toplevel') | Select-Object -First 1)

# ── Resolve branch name ───────────────────────────────────────────────────
$slugToken = Normalize-Token -Value $Slug
$sessionToken = if ([string]::IsNullOrWhiteSpace($SessionId)) { $null } else { Normalize-Token -Value $SessionId }
$today = Get-Date -Format 'yyMMdd'

if ($Mode -eq 'branch' -and -not $Branch) {
    throw 'Specify -Branch when using -Mode branch.'
}

$resolvedBranch = if ($Branch) {
    $Branch
}
else {
    switch ($Mode) {
        'feature' { "feature/$(Join-NameParts -Parts @($today, $slugToken, $sessionToken))" }
        'fix' { "fix/$(Join-NameParts -Parts @($today, $slugToken, $sessionToken))" }
        'experiment' { "experiment/$(Join-NameParts -Parts @($today, $slugToken, $sessionToken))" }
        'openspec' { "openspec/$(Join-NameParts -Parts @($today, $slugToken, $sessionToken))" }
        'release' { "release/$slugToken" }
        'hotfix' { "hotfix/$slugToken" }
        'branch' { throw 'Branch mode requires -Branch.' }
        default { throw "Unsupported mode '$Mode'." }
    }
}

# ── Resolve worktree name and path ────────────────────────────────────────
$resolvedWorktreeName = if ($WorktreeName) {
    $WorktreeName
}
else {
    $resolvedBranch -replace '[\\/]+', '-'
}

$worktreeRootPath = Join-Path $repoRoot $WorktreeRoot
$worktreePath = Join-Path $worktreeRootPath $resolvedWorktreeName

# ── Validate prerequisites ────────────────────────────────────────────────
if (-not (Test-GitRef -RefName "refs/heads/$BaseBranch") -and -not (Test-GitRef -RefName "refs/remotes/origin/$BaseBranch")) {
    throw "Base branch '$BaseBranch' does not exist locally or on origin."
}

if (Test-GitRef -RefName "refs/heads/$resolvedBranch") {
    throw "Branch '$resolvedBranch' already exists."
}

if (Test-Path $worktreePath) {
    throw "Worktree path '$worktreePath' already exists."
}

# ── Determine start point ─────────────────────────────────────────────────
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

# ── Create worktree root if needed ────────────────────────────────────────
if ((-not (Test-Path $worktreeRootPath)) -and $PSCmdlet.ShouldProcess($worktreeRootPath, 'Create worktree root directory')) {
    New-Item -ItemType Directory -Path $worktreeRootPath | Out-Null
}

# ── Create detached worktree ──────────────────────────────────────────────
if ($PSCmdlet.ShouldProcess($worktreePath, "Create detached worktree from '$startPoint'")) {
    Invoke-Git -Arguments @('worktree', 'add', '--detach', $worktreePath, $startPoint) | Out-Null
}

# ── Create branch inside worktree ─────────────────────────────────────────
if ((Test-Path $worktreePath) -and $PSCmdlet.ShouldProcess($resolvedBranch, "Create branch inside '$worktreePath'")) {
    Invoke-Git -Arguments @('switch', '-c', $resolvedBranch) -WorkingDirectory $worktreePath | Out-Null
}

# ── Bootstrap (optional post-creation commands) ───────────────────────────
$bootstrapped = $false
if ($BootstrapCommand -and (Test-Path $worktreePath)) {
    if ($PSCmdlet.ShouldProcess($worktreePath, 'Run bootstrap commands')) {
        Push-Location $worktreePath
        try {
            foreach ($cmd in $BootstrapCommand) {
                Write-Host "→ Running: $cmd" -ForegroundColor Cyan
                $output = Invoke-Expression $cmd
                if ($LASTEXITCODE -ne 0) {
                    throw "Bootstrap command failed (exit $LASTEXITCODE): $cmd"
                }
            }
            $bootstrapped = $true
        }
        finally {
            Pop-Location
        }
    }
}

# ── Output ────────────────────────────────────────────────────────────────
[pscustomobject]@{
    BaseBranch = $BaseBranch
    Branch = $resolvedBranch
    WorktreePath = $worktreePath
    StartPoint = $startPoint
    CreationMode = 'worktree-first'
    Bootstrapped = $bootstrapped
}
