<#
.SYNOPSIS
  Manifest resolver for the daily-report skill: active mode + watched repo paths.
.DESCRIPTION
  Reads reports/daily/daily-report.manifest.json from the given checkout's
  toplevel (the home-repo, or tower), validates it, and emits JSON:
  {present, manifestPath, mode, homeRepoRoot, repos}. The manifest dictates
  the active mode: 'single' grounds the invoking checkout only, 'multi'
  grounds every path listed in repos (full absolute paths, one per machine).
  An absent manifest is a valid single-mode answer only with -Optional;
  without it a missing manifest fails loudly. A watched path that does not
  exist on this machine comes back with exists=false - a grounding gap the
  report must name - never a hard failure. A path that exists but is not a
  git checkout, a relative or duplicate path, an unknown mode, or an
  unsupported schema value are validation failures and abort loudly.
.EXAMPLE
  .\Get-ReportManifest.ps1 -RepoRoot C:\work\home-repo -Optional
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [switch]$Optional
)

$ErrorActionPreference = 'Stop'

$top = (& git -C $RepoRoot rev-parse --show-toplevel 2>$null)
if (-not $top) { Write-Error "manifest: '$RepoRoot' is not inside a git repository."; exit 1 }
$top = "$top".Trim()
$normTop = $top.Replace('/', '\').TrimEnd('\')

$manifestPath = Join-Path $top 'reports/daily/daily-report.manifest.json'

$emit = {
    param($present, $mode, $repos)
    [ordered]@{
        present      = $present
        manifestPath = $manifestPath
        mode         = $mode
        homeRepoRoot = $top
        repos        = @($repos)
    } | ConvertTo-Json -Depth 5
}

if (-not (Test-Path -LiteralPath $manifestPath)) {
    if (-not $Optional) {
        Write-Error "manifest: not found at $manifestPath. Copy templates/manifest.example.json into place, or pass -Optional for single mode."
        exit 1
    }
    & $emit $false 'single' @()
    exit 0
}

$raw = Get-Content -LiteralPath $manifestPath -Raw
try {
    $m = $raw | ConvertFrom-Json
}
catch {
    Write-Error "manifest: invalid JSON at $manifestPath - $($_.Exception.Message)"
    exit 1
}
if ($null -eq $m -or -not ($m -is [System.Management.Automation.PSCustomObject])) {
    Write-Error "manifest: $manifestPath must contain a JSON object."
    exit 1
}

$props = @($m.PSObject.Properties.Name)
if ('schema' -notin $props) { Write-Error 'manifest: missing required field schema (expected 1).'; exit 1 }
if ($m.schema -is [bool] -or $m.schema -is [string] -or $m.schema -isnot [ValueType]) {
    Write-Error "manifest: schema must be the integer 1, got '$($m.schema)'."
    exit 1
}
if ([double]$m.schema -ne 1) {
    Write-Error "manifest: schema $($m.schema) is not supported (expected 1)."
    exit 1
}
if ('mode' -notin $props) { Write-Error "manifest: missing required field mode ('single' or 'multi')."; exit 1 }
$mode = "$($m.mode)"
if ($mode -notin @('single', 'multi')) {
    Write-Error "manifest: mode '$mode' is not 'single' or 'multi'."
    exit 1
}

if ($mode -eq 'single') {
    # single mode: the invoking checkout grounds and writes; repos is not read.
    & $emit $true 'single' @()
    exit 0
}

if ('repos' -notin $props) { Write-Error 'manifest: multi mode requires the repos field (list of full absolute paths).'; exit 1 }
$entries = @($m.repos)
if ($entries.Count -eq 0) { Write-Error 'manifest: multi mode requires at least one path in repos.'; exit 1 }

$seen = @{}
$resolved = @()
foreach ($entry in $entries) {
    if ($entry -isnot [string] -or [string]::IsNullOrWhiteSpace($entry)) {
        Write-Error 'manifest: repos entries must be non-empty strings holding full absolute paths.'
        exit 1
    }
    $path = "$entry".Trim()
    if (-not [System.IO.Path]::IsPathRooted($path)) {
        Write-Error "manifest: repos entry '$entry' is not a full absolute path."
        exit 1
    }
    $norm = $path.TrimEnd('\', '/')
    $key = $norm.Replace('/', '\').ToLowerInvariant()
    if ($seen.ContainsKey($key)) {
        Write-Error "manifest: duplicate repos entry '$entry'."
        exit 1
    }
    $seen[$key] = $true

    $exists = [bool](Test-Path -LiteralPath $norm)
    $resolvedPath = $norm
    $name = $null
    if ($exists) {
        $innerTop = (& git -C $norm rev-parse --show-toplevel 2>$null)
        if (-not $innerTop) {
            Write-Error "manifest: '$norm' exists but is not a git checkout."
            exit 1
        }
        $resolvedPath = "$innerTop".Trim()
        $url = (& git -C $resolvedPath remote get-url origin 2>$null)
        if ("$url" -match 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?$') {
            $name = "$($Matches.owner)/$($Matches.repo)"
        }
    }
    $resolved += [ordered]@{
        path       = $resolvedPath
        name       = $name
        exists     = $exists
        isHomeRepo = ($resolvedPath.Replace('/', '\').TrimEnd('\') -ieq $normTop)
    }
}

& $emit $true 'multi' $resolved
exit 0
