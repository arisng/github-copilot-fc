<#
.SYNOPSIS
  Validate one commit message against .github/git-scope-constitution.md.
.DESCRIPTION
  Enforces the two mechanical rules the constitution states in prose:
    - the type is an approved, non-deprecated type, and
    - the scope is one the constitution lists for that type.

  This is a guardrail, not a style preference: the constitution already names
  its approved type/scope pairs, so a message outside them is a deterministic
  failure with a deterministic fix. It exists because a commit typed
  `fix(skill): ...` reached main despite the constitution having no `fix` type
  - the gate linted the tree but never the message (retro 2026-11-23).

  Passes through: merge commits, reverts, and fixup/squash! prefixes, which git
  writes itself and no author chooses.

  Reads the message from -MessagePath (the file git passes as $1 to a
  commit-msg hook). Exits 1 with a remediation line naming the approved scopes
  for the offending type. Skips (exit 0) when the constitution is absent, so a
  partial checkout is never bricked.
.PARAMETER MessagePath
  Path to the commit message file. Required.
.PARAMETER ConstitutionPath
  Path to the constitution. Default: <repo>/.github/git-scope-constitution.md,
  resolved from this script's location.
.EXAMPLE
  pwsh -NoProfile -File scripts/workspace/check-commit-message.ps1 -MessagePath .git/COMMIT_EDITMSG
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MessagePath,

    [string]$ConstitutionPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $ConstitutionPath) { $ConstitutionPath = Join-Path $repoRoot '.github/git-scope-constitution.md' }

if (-not (Test-Path -LiteralPath $MessagePath)) {
    Write-Output "commit-msg: [FAIL] message file '$MessagePath' not found"
    exit 1
}
if (-not (Test-Path -LiteralPath $ConstitutionPath)) {
    # No constitution, no contract to enforce.
    Write-Output 'commit-msg: [SKIP] git-scope-constitution.md not found'
    exit 0
}

$firstLine = @(Get-Content -LiteralPath $MessagePath -TotalCount 1)[0]
if ([string]::IsNullOrWhiteSpace($firstLine)) {
    Write-Output 'commit-msg: [FAIL] empty commit message'
    exit 1
}
$subject = $firstLine.Trim()

# Messages git generates itself carry no author choice.
if ($subject -match '^(Merge |Revert "|fixup! |squash! |amend! )') {
    Write-Output "commit-msg: [PASS] generated message ($($subject.Split(' ')[0]))"
    exit 0
}

$match = [regex]::Match($subject, '^([a-z][a-z0-9-]*)\(([^)]+)\):\s*\S')
if (-not $match.Success) {
    Write-Output 'commit-msg: [FAIL] expected "<type>(<scope>): <summary>"'
    Write-Output 'commit-msg: see .github/git-scope-constitution.md -> Scope Naming Conventions'
    exit 1
}
$type = $match.Groups[1].Value
$scope = $match.Groups[2].Value

# Parse the constitution: approved types with the scopes each allows. A type
# whose section says "Deprecated type" is refused even when it lists scopes.
#
# A section heading may name several types at once - constitutions group them
# ("### `feat` and `fix`", "### `chore` and `build`"), and those types share
# every scope listed beneath. Matching only a lone backticked name silently
# under-approves: the grouped sections parse as nothing, so the checker reads
# a fraction of the constitution and rejects legitimate commits (retro
# 2026-11-26). Collect every backticked name on the heading line instead.
$approved = @{}
$deprecated = @{}
$globalScopes = [System.Collections.Generic.List[string]]::new()
$currentTypes = @()
$inSection = $false
foreach ($line in @(Get-Content -LiteralPath $ConstitutionPath)) {
    if ($line -match '^##\s+') {
        $inSection = $line -match '^##\s+Approved Scopes by Commit Type\s*$'
        $currentTypes = @()
        continue
    }
    if (-not $inSection) { continue }
    if ($line -match '^###\s') {
        $currentTypes = @([regex]::Matches($line, '`([a-z][a-z0-9-]*)`') | ForEach-Object { $_.Groups[1].Value })
        foreach ($t in $currentTypes) {
            if (-not $approved.ContainsKey($t)) {
                $approved[$t] = [System.Collections.Generic.List[string]]::new()
            }
        }
        continue
    }
    # A heading may name no type at all (a shared "(all types)" block); its
    # scopes still count, so only type-scoped items depend on $currentTypes.
    if ($line -match 'Deprecated type\.' -and $currentTypes.Count -gt 0) {
        foreach ($t in $currentTypes) { $deprecated[$t] = $true }
    }
    # "(all types)" marks a scope every approved type accepts - attribute
    # scopes (api, ui, i18n) genuinely span types, and forcing them into one
    # grouped section is how a constitution drifts from practice. Collected
    # and applied after the whole file is read so declaration order is free.
    $scopeItem = [regex]::Match($line, '^\s*-\s+`([a-z][a-z0-9-]*)`\s*(:|\()')
    if ($scopeItem.Success) {
        $scopeName = $scopeItem.Groups[1].Value
        if ($line -match '\(all types\)') {
            if ($globalScopes -notcontains $scopeName) { $globalScopes.Add($scopeName) }
        }
        elseif ($currentTypes.Count -gt 0) {
            foreach ($t in $currentTypes) { $approved[$t].Add($scopeName) }
        }
    }
}
foreach ($scopeName in $globalScopes) {
    foreach ($t in $approved.Keys) {
        if ($approved[$t] -notcontains $scopeName) { $approved[$t].Add($scopeName) }
    }
}
foreach ($t in $deprecated.Keys) { $approved.Remove($t) }

if ($approved.Count -eq 0) {
    Write-Output 'commit-msg: [SKIP] no approved types parsed from the constitution'
    exit 0
}

$approvedTypes = @($approved.Keys | Sort-Object)
if (-not $approved.ContainsKey($type)) {
    Write-Output "commit-msg: [FAIL] type '$type' is not approved"
    Write-Output "commit-msg: approved types: $($approvedTypes -join ', ')"
    exit 1
}

$scopes = @($approved[$type])
if ($scopes.Count -eq 0) {
    Write-Output "commit-msg: [FAIL] type '$type' lists no approved scopes in the constitution"
    exit 1
}
if ($scopes -notcontains $scope) {
    Write-Output "commit-msg: [FAIL] scope '$scope' is not approved for type '$type'"
    Write-Output "commit-msg: approved $type scopes: $($scopes -join ', ')"
    exit 1
}

Write-Output "commit-msg: [PASS] $type($scope)"
exit 0
