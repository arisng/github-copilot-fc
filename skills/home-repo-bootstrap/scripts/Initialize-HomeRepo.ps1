<#
.SYNOPSIS
  Seed or repair a personal home repo (the Home Repo pattern) in a target folder.
.DESCRIPTION
  Writes the home-repo skeleton into -Path: AGENTS.md, docs/ (coding standards,
  glossary), reports/daily/, scripts/local-ci.ps1, .githooks/pre-commit and
  .gitignore, then initializes git when the folder is not yet a repository and
  sets core.hooksPath=.githooks. It also writes the gitignored per-machine
  reports/daily/daily-report.manifest.json from -WatchedRepo.

  Seed, never sync: any file that already exists is left byte-for-byte intact
  and reported under "skipped". Use -Force to deliberately re-seed a file, for
  example when the home repo's copy was damaged. A teammate's home repo owns its
  copy of every seeded file after the first run.

  Every pointer bullet needs a local path and a well-formed clone URL, because
  scripts/local-ci.ps1 fails a bullet that lacks either half. Pointer paths must
  contain no spaces: local CI extracts them with a whitespace-terminated match.
  When -Repo is omitted, one clearly labelled placeholder bullet is written so a
  fresh home repo still passes its own gate; replace it with real pointers.

  Emits one JSON object on stdout: {path, created, skipped, gitInitialized,
  hooksPath, mode, manifestPath, pointers, nextSteps}. Exit code 1 on invalid
  input or a failed git operation.
.PARAMETER Path
  Target home-repo root. Created when missing.
.PARAMETER GitUser
  Git user name the daily-report tower reports for. Default: the global git
  user.name, else $env:USERNAME.
.PARAMETER Repo
  Zero or more pointer entries in the form "name|path|clone-url" (pipe
  separated, exactly three non-empty fields). The path must be absolute and
  must contain no spaces.
.PARAMETER WatchedRepo
  Zero or more absolute paths of the checkouts the daily-report tower watches.
  Supplying at least one switches the manifest to mode "multi"; otherwise the
  manifest is mode "single" and reports stay in this checkout.
.PARAMETER RemoteUrl
  When given and no origin exists yet, add origin and set -Branch as upstream.
.PARAMETER Branch
  Branch name used when initializing a repository. Default: main.
.PARAMETER Force
  Overwrite files this skill seeds. Untouched by default.
.PARAMETER SkipGitInit
  Write files only; do not initialize git or set core.hooksPath.
.EXAMPLE
  ./Initialize-HomeRepo.ps1 -Path C:\Work\home-repo -GitUser 'Aris Nguyen'
.EXAMPLE
  ./Initialize-HomeRepo.ps1 -Path C:\Work\home-repo -Repo 'copilot-fc|C:\Work\Agents\github-copilot-fc|https://github.com/arisng/github-copilot-fc.git' -WatchedRepo 'C:\Work\Agents\github-copilot-fc'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [string]$GitUser,

    [string[]]$Repo = @(),

    [string[]]$WatchedRepo = @(),

    [string]$RemoteUrl,

    [string]$Branch = 'main',

    [switch]$Force,

    [switch]$SkipGitInit
)

$ErrorActionPreference = 'Stop'

function Write-Fail {
    param([string]$Message)
    Write-Error "home-repo-bootstrap: $Message"
    exit 1
}

# --- validate input -------------------------------------------------------
$root = $Path
if (-not [System.IO.Path]::IsPathRooted($root)) { Write-Fail "Path '$Path' must be an absolute path." }
$root = $root.TrimEnd('\', '/')
if (Test-Path -LiteralPath $root -PathType Leaf) { Write-Fail "Path '$root' is a file; point at a folder." }

$pointers = @()
foreach ($entry in $Repo) {
    if ([string]::IsNullOrWhiteSpace($entry)) { continue }
    $parts = @("$entry".Split('|'))
    if ($parts.Count -ne 3) {
        Write-Fail "Repo entry '$entry' must have exactly three pipe-separated fields: name|path|clone-url."
    }
    $pName = $parts[0].Trim()
    $pPath = $parts[1].Trim()
    $pUrl = $parts[2].Trim()
    foreach ($field in @($pName, $pPath, $pUrl)) {
        if ([string]::IsNullOrWhiteSpace($field)) { Write-Fail "Repo entry '$entry' has an empty field." }
    }
    if (-not [System.IO.Path]::IsPathRooted($pPath)) {
        Write-Fail "Repo entry '$entry': path '$pPath' must be absolute."
    }
    if ($pPath -match '\s') {
        Write-Fail "Repo entry '$entry': path '$pPath' contains a space; local CI reads pointer paths as whitespace-terminated tokens."
    }
    if ($pUrl -notmatch '^(https?://|git@|ssh://|git://)') {
        Write-Fail "Repo entry '$entry': '$pUrl' is not a clone URL."
    }
    $pointers += [ordered]@{ name = $pName; path = $pPath; cloneUrl = $pUrl }
}

$watched = @()
foreach ($w in $WatchedRepo) {
    if ([string]::IsNullOrWhiteSpace($w)) { continue }
    if (-not [System.IO.Path]::IsPathRooted($w)) { Write-Fail "WatchedRepo '$w' must be an absolute path." }
    $watched += $w.Trim().TrimEnd('\', '/')
}
$mode = if ($watched.Count -gt 0) { 'multi' } else { 'single' }

# --- resolve seed sources -------------------------------------------------
$skillRoot = Split-Path -Parent $PSScriptRoot
$assets = Join-Path $skillRoot 'assets'
foreach ($required in @('local-ci.ps1', 'pre-commit.template', 'gitignore.template', 'AGENTS.md.template', 'coding-standards.md', 'glossary.md')) {
    if (-not (Test-Path -LiteralPath (Join-Path $assets $required))) {
        Write-Fail "seed asset '$required' is missing from $assets."
    }
}

if (-not $GitUser) {
    $GitUser = (& git config --global user.name 2>$null)
    if ([string]::IsNullOrWhiteSpace("$GitUser")) { $GitUser = $env:USERNAME }
    if ([string]::IsNullOrWhiteSpace("$GitUser")) { $GitUser = 'developer' }
}

# --- write -----------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $root | Out-Null

$created = [System.Collections.Generic.List[string]]::new()
$skipped = [System.Collections.Generic.List[string]]::new()

function Write-Seed {
    param(
        [string]$RelativePath,
        [string]$Content
    )

    $absolute = Join-Path $root ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $parent = Split-Path -Parent $absolute
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }

    if ((Test-Path -LiteralPath $absolute) -and -not $Force) {
        $skipped.Add($RelativePath)
        return
    }
    Set-Content -LiteralPath $absolute -Value $Content -NoNewline -Encoding utf8
    $created.Add($RelativePath)
}

$placeholder = '- Placeholder repo (replace with your own pointer): C:\path\to\your-repo. Clone from https://github.com/your-org/your-repo.git if missing.'
$bulletLines = if ($pointers.Count -eq 0) {
    $placeholder
}
else {
    ($pointers | ForEach-Object { "- $($_.name): $($_.path). Clone from $($_.cloneUrl) if missing." }) -join "`n"
}

$agentsTemplate = Get-Content -LiteralPath (Join-Path $assets 'AGENTS.md.template') -Raw
$agents = $agentsTemplate.
    Replace('{{GIT_USER}}', $GitUser).
    Replace('{{HOME_REPO_PATH}}', $root).
    Replace('{{POINTER_BULLETS}}', $bulletLines)

Write-Seed 'AGENTS.md' $agents
Write-Seed 'docs/coding-standards.md' (Get-Content -LiteralPath (Join-Path $assets 'coding-standards.md') -Raw)
Write-Seed 'docs/glossary.md' (Get-Content -LiteralPath (Join-Path $assets 'glossary.md') -Raw)
Write-Seed 'scripts/local-ci.ps1' (Get-Content -LiteralPath (Join-Path $assets 'local-ci.ps1') -Raw)
Write-Seed '.githooks/pre-commit' (Get-Content -LiteralPath (Join-Path $assets 'pre-commit.template') -Raw)
Write-Seed '.gitignore' (Get-Content -LiteralPath (Join-Path $assets 'gitignore.template') -Raw)
Write-Seed 'reports/daily/.gitkeep' ''

# --- manifest (per machine, gitignored) -----------------------------------
$manifestPath = Join-Path $root 'reports/daily/daily-report.manifest.json'
$manifestDir = Split-Path -Parent $manifestPath
if (-not (Test-Path -LiteralPath $manifestDir)) { New-Item -ItemType Directory -Force -Path $manifestDir | Out-Null }

$manifest = [ordered]@{ schema = 1; mode = $mode }
if ($mode -eq 'multi') { $manifest.repos = @($watched) }
$manifestJson = ($manifest | ConvertTo-Json -Depth 5) -replace "`r`n", "`n"

$existingManifest = if (Test-Path -LiteralPath $manifestPath) { Get-Content -LiteralPath $manifestPath -Raw } else { $null }
if ($null -ne $existingManifest) {
    $skipped.Add('reports/daily/daily-report.manifest.json')
}
else {
    Set-Content -LiteralPath $manifestPath -Value $manifestJson -NoNewline -Encoding utf8
    $created.Add('reports/daily/daily-report.manifest.json')
}

# --- git ------------------------------------------------------------------
$gitInitialized = $false
$hooksPath = $null
if (-not $SkipGitInit) {
    $inside = (& git -C $root rev-parse --show-toplevel 2>$null)
    if (-not $inside) {
        & git -C $root init -q -b $Branch
        if ($LASTEXITCODE -ne 0) {
            & git -C $root init -q
            if ($LASTEXITCODE -ne 0) { Write-Fail "git init failed in $root." }
            & git -C $root symbolic-ref HEAD "refs/heads/$Branch" | Out-Null
        }
        $gitInitialized = $true
    }

    if ($RemoteUrl) {
        $hasOrigin = (& git -C $root remote get-url origin 2>$null)
        if (-not $hasOrigin) {
            & git -C $root remote add origin $RemoteUrl
            if ($LASTEXITCODE -ne 0) { Write-Fail "git remote add origin failed in $root." }
        }
    }

    # pre-commit only runs when the hooks directory is wired for this clone.
    & git -C $root config core.hooksPath .githooks
    if ($LASTEXITCODE -ne 0) { Write-Fail "git config core.hooksPath failed in $root." }
    $hooksPath = (& git -C $root config --get core.hooksPath)
    if ($hooksPath) { $hooksPath = "$hooksPath".Trim() }

    # POSIX hooks must stay executable on every platform that ships sh.
    $hookFile = Join-Path $root '.githooks/pre-commit'
    if ((Test-Path -LiteralPath $hookFile) -and -not $IsWindows) {
        & chmod +x $hookFile 2>$null
    }
}

# --- report ---------------------------------------------------------------
$nextSteps = [System.Collections.Generic.List[string]]::new()
if ($pointers.Count -eq 0) {
    $nextSteps.Add('Replace the placeholder pointer in AGENTS.md with real "name: path. Clone from url if missing." bullets, then re-run the pre-commit gate.')
}
if ($mode -eq 'single' -and $pointers.Count -gt 0) {
    $nextSteps.Add('To report across several checkouts, re-run with -WatchedRepo for each path (adds multi mode to the manifest).')
}
$nextSteps.Add('Install the shared skills: npx skills add arisng/github-copilot-fc -s daily-report -g -y')
$nextSteps.Add("Verify the bootstrap: pwsh -NoProfile -File `"$($skillRoot -replace '\\', '/')/scripts/Test-HomeRepoBootstrap.ps1`" -Path `"$($root -replace '\\', '/')`"")
$nextSteps.Add('Commit the seed: git add -A; git commit -m "chore(workspace): bootstrap home repo"')

[ordered]@{
    path           = $root
    created        = @($created)
    skipped        = @($skipped)
    gitInitialized = $gitInitialized
    hooksPath      = $hooksPath
    mode           = $mode
    manifestPath   = $manifestPath
    pointers       = @($pointers)
    nextSteps      = @($nextSteps)
} | ConvertTo-Json -Depth 6
exit 0
