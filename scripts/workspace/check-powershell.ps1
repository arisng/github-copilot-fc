<#
.SYNOPSIS
    Static lint for this repo's PowerShell: parse failures and the
    parameter-clobber pattern (a parameter assigned before its first read).

.DESCRIPTION
    Retro 2026-11-21: the gate linted markdown, JSON and ran test suites, but
    never parsed the ~77 .ps1 files it ships - two scripts with real syntax
    errors and two case-insensitive parameter clobbers reached main unnoticed
    (PowerShell variables are case-insensitive, so `$treeMaxIssues = 300`
    silently overwrites a `-TreeMaxIssues 500` argument).

    Rule: in each scope (script or function), a parameter's FIRST occurrence
    in that scope's own body must be a READ. Assignment-first means the
    passed argument was destroyed on entry. Two idioms pass: a read-first
    reassignment (`if ([string]::IsNullOrWhiteSpace($Out)) { $Out = ... }`)
    and a preserve-then-resolve assignment that mentions the argument inside
    its own RHS (`$Repo = Resolve-Thing -Repo $Repo ...`).

    Nested functions are analyzed against their own parameters only.

    Run as a subprocess (the script exits): pwsh -NoProfile -File <this file>

.PARAMETER Path
    File or directory to scan. Default: the repo root.

.EXAMPLE
    pwsh scripts/workspace/check-powershell.ps1
.EXAMPLE
    pwsh scripts/workspace/check-powershell.ps1 -Path skills/issue-tracking
#>
[CmdletBinding()]
param(
    [string]$Path
)

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $Path) { $Path = $repoRoot }

$rootItem = Get-Item -LiteralPath $Path -ErrorAction Stop
$targets = if ($rootItem.PSIsContainer) {
    @(Get-ChildItem -LiteralPath $rootItem.FullName -Recurse -File -Filter '*.ps1' -ErrorAction SilentlyContinue)
}
else {
    @($rootItem)
}
$targets = @($targets | Where-Object { $_.FullName -notmatch '\\node_modules\\|\\\.git\\|\\\.archived\\' })

function Get-RelativeLabel {
    param([string]$FullName)
    if ($FullName.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $FullName.Substring($repoRoot.Length).TrimStart('\', '/')
    }
    return $FullName
}

$findings = New-Object System.Collections.Generic.List[string]

foreach ($file in $targets) {
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    $label = Get-RelativeLabel -FullName $file.FullName

    foreach ($e in $errors) {
        $findings.Add("parse: ${label}:$($e.Extent.StartLineNumber) - $($e.Message)")
    }
    if ($errors.Count -gt 0) { continue }

    # Scopes: the script itself plus every function with a param block.
    $scopes = New-Object System.Collections.Generic.List[object]
    if ($ast.ParamBlock) {
        $scopes.Add(@{ Body = $ast; Params = $ast.ParamBlock; Name = 'script' })
    }
    foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        if ($fn.Body.ParamBlock) {
            $scopes.Add(@{ Body = $fn.Body; Params = $fn.Body.ParamBlock; Name = "function $($fn.Name)" })
        }
    }

    foreach ($scope in $scopes) {
        # Hashtable keys are case-insensitive - matching PowerShell's own rule.
        $paramNames = @{}
        foreach ($p in $scope.Params.Parameters) {
            if ($p.Name.VariablePath.UserPath) { $paramNames[$p.Name.VariablePath.UserPath] = $true }
        }
        if ($paramNames.Count -eq 0) { continue }

        $firstRef = @{}
        $refs = $scope.Body.FindAll({ param($x) $x -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)
        foreach ($v in $refs) {
            if (-not $v.VariablePath) { continue }
            $varName = $v.VariablePath.UserPath
            if ([string]::IsNullOrEmpty($varName)) { continue }
            if (-not $paramNames.ContainsKey($varName)) { continue }

            # Skip references inside nested functions: they bind their own
            # scope, so they cannot clobber this scope's parameter.
            # Skip the parameter declaration itself - it always sorts first
            # and is neither the read nor the write being tested.
            $nested = $false
            $ancestor = $v.Parent
            while ($ancestor -and $ancestor -ne $scope.Body) {
                if ($ancestor -is [System.Management.Automation.Language.FunctionDefinitionAst]) { $nested = $true; break }
                if ($ancestor -is [System.Management.Automation.Language.ParameterAst]) { $nested = $true; break }
                $ancestor = $ancestor.Parent
            }
            if ($nested) { continue }

            $isWrite = ($v.Parent -is [System.Management.Automation.Language.AssignmentStatementAst]) -and
                       ($v.Parent.Left.Extent.StartOffset -eq $v.Extent.StartOffset)
            if ($isWrite) {
                # Preserve-then-resolve idiom: `$X = Resolve-Thing -Input $X`
                # evaluates the passed argument before rebinding it, so it is
                # not an entry-time clobber. Only an assignment whose RHS never
                # mentions the variable destroys the argument.
                $assignment = $v.Parent
                $sameVar = $varName
                $mentions = @($assignment.FindAll({
                        param($x)
                        $x -is [System.Management.Automation.Language.VariableExpressionAst] -and
                        $x.VariablePath -and
                        [string]::Equals($x.VariablePath.UserPath, $sameVar, [System.StringComparison]::OrdinalIgnoreCase)
                    }, $true))
                if ($mentions.Count -gt 1) { $isWrite = $false }
            }
            $key = $varName.ToLowerInvariant()
            if (-not $firstRef.ContainsKey($key)) {
                $firstRef[$key] = [pscustomobject]@{
                    Name    = $varName
                    Line    = $v.Extent.StartLineNumber
                    IsWrite = $isWrite
                }
            }
        }

        foreach ($key in @($firstRef.Keys)) {
            $first = $firstRef[$key]
            if ($first.IsWrite) {
                $where = if ($scope.Name -eq 'script') { 'script' } else { $scope.Name }
                $findings.Add("clobber: ${label}:$($first.Line) - `$$($first.Name) assigned before first read in $where param")
            }
        }
    }
}

if ($findings.Count -eq 0) {
    Write-Output "[PASS] pshlint: $($targets.Count) file(s) parsed, no param-clobber findings"
    exit 0
}
foreach ($f in $findings) { Write-Output "[FAIL] pshlint: $f" }
Write-Output "[FAIL] pshlint: $($findings.Count) finding(s) across $($targets.Count) file(s)"
exit 1
