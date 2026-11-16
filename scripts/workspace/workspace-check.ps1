<#
.SYNOPSIS
    Local CI: run all workspace quality checks in one command.

.DESCRIPTION
    Aggregates the repo's offline quality gates (local CI only — no cloud workflows):

    1. TOC freshness — regenerates the copilot-vscode-docs documentation TOC to a
       temp file and compares it with assets/toc.md. Fails when the generator is
       broken or the committed TOC is stale vs upstream toc.json. A network
       failure downgrades to a warning so offline pushes still work.
    2. OpenSpec validators — cross-refs, RFC 2119, runtime leaks. Each skips
       cleanly when openspec/specs is absent.
    3. waza check — advisory skill-quality report (exit 2 = known pre-existing
       backlog; reported but non-blocking, because waza gate/run CI gating is
       deferred per instructions/waza-eval.instructions.md). A missing or
       crashing waza CLI fails the check.

    Exits non-zero when any gated check fails. Used by scripts/hooks/pre-push.

.EXAMPLE
    pwsh -NoProfile -File scripts/workspace/workspace-check.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$failures = [System.Collections.Generic.List[string]]::new()

function Write-CheckResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('PASS', 'WARN', 'FAIL', 'SKIP')][string]$Status,
        [Parameter(Mandatory)][string]$Detail
    )
    $icon = @{ PASS = '[PASS]'; WARN = '[WARN]'; FAIL = '[FAIL]'; SKIP = '[SKIP]' }[$Status]
    $color = @{ PASS = 'Green'; WARN = 'Yellow'; FAIL = 'Red'; SKIP = 'Gray' }[$Status]
    Write-Host "$icon $Name - $Detail" -ForegroundColor $color
}

function Test-TocFreshness {
    [CmdletBinding()]
    param()

    $tocScript = Join-Path $repoRoot 'skills/copilot-vscode-docs/scripts/parse_toc.py'
    $tocAsset = Join-Path $repoRoot 'skills/copilot-vscode-docs/assets/toc.md'

    if (-not (Get-Command python3 -ErrorAction SilentlyContinue)) {
        return @{ Status = 'FAIL'; Detail = 'python3 not found on PATH (required to verify the docs TOC)' }
    }

    $tempOut = Join-Path ([System.IO.Path]::GetTempPath()) ("toc-check-" + [guid]::NewGuid().ToString('N') + '.md')
    try {
        & python3 $tocScript --out $tempOut 2>&1 | Out-Null
        $code = $LASTEXITCODE
        if ($code -eq 2) {
            return @{ Status = 'WARN'; Detail = 'upstream toc.json unreachable (network) - freshness unverified this run' }
        }
        if ($code -ne 0) {
            return @{ Status = 'FAIL'; Detail = "TOC regeneration failed (exit $code) - parse_toc.py is broken or upstream toc.json format changed" }
        }

        $new = (Get-Content -Path $tempOut -Raw) -replace "`r`n", "`n"
        $old = if (Test-Path $tocAsset) { (Get-Content -Path $tocAsset -Raw) -replace "`r`n", "`n" } else { '' }
        $linkCount = ([regex]::Matches($new, '(?m)^\s*- \[')).Count
        if ($linkCount -lt 100) {
            return @{ Status = 'FAIL'; Detail = "regenerated TOC has only $linkCount links (expected >= 100) - parser output looks degenerate" }
        }
        if ($new -ne $old) {
            return @{ Status = 'FAIL'; Detail = 'assets/toc.md is stale vs upstream toc.json - run: python3 skills/copilot-vscode-docs/scripts/parse_toc.py && git add skills/copilot-vscode-docs/assets/toc.md' }
        }
        return @{ Status = 'PASS'; Detail = "assets/toc.md matches upstream toc.json ($linkCount links)" }
    }
    finally {
        Remove-Item -Path $tempOut -ErrorAction SilentlyContinue
    }
}

function Test-OpenSpecValidators {
    [CmdletBinding()]
    param()

    $specsRoot = Join-Path $repoRoot 'openspec/specs'
    if (-not (Test-Path $specsRoot)) {
        return @{ Status = 'SKIP'; Detail = "openspec/specs absent - no specs to validate (validators auto-activate when specs return)" }
    }

    $failed = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @('validate-cross-refs', 'validate-rfc2119', 'validate-runtime-leaks')) {
        $script = Join-Path $repoRoot "scripts/openspec/$name.ps1"
        & pwsh -NoProfile -File $script 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $failed.Add("$name (exit $LASTEXITCODE)")
        }
    }
    if ($failed.Count -gt 0) {
        return @{ Status = 'FAIL'; Detail = "validator failures: $($failed -join ', ')" }
    }
    return @{ Status = 'PASS'; Detail = 'all 3 openspec validators passed' }
}

function Invoke-WazaCheck {
    [CmdletBinding()]
    param()

    if (-not (Get-Command waza -ErrorAction SilentlyContinue)) {
        return @{ Status = 'FAIL'; Detail = 'waza CLI not found on PATH - install it (skill-eval tool, see instructions/waza-eval.instructions.md)' }
    }

    $tempOut = Join-Path ([System.IO.Path]::GetTempPath()) ("waza-check-" + [guid]::NewGuid().ToString('N') + '.txt')
    Push-Location $repoRoot
    try {
        & waza check --no-update-check *> $tempOut
        $code = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    try {
        if ($code -eq 0) {
            return @{ Status = 'PASS'; Detail = 'waza check clean' }
        }
        if ($code -eq 2) {
            $findings = (Select-String -Path $tempOut -SimpleMatch -Pattern ([char]0x274C) | Measure-Object).Count
            return @{ Status = 'WARN'; Detail = "waza check reports the known pre-existing backlog ($findings findings, exit 2) - advisory only; run 'waza check' for details" }
        }
        return @{ Status = 'FAIL'; Detail = "waza check crashed (exit $code) - run 'waza check' to see why" }
    }
    finally {
        Remove-Item -Path $tempOut -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Run all checks
# ---------------------------------------------------------------------------
$checks = @(
    @{ Name = 'TOC freshness'; Result = Test-TocFreshness },
    @{ Name = 'OpenSpec validators'; Result = Test-OpenSpecValidators },
    @{ Name = 'waza check (advisory)'; Result = Invoke-WazaCheck }
)

foreach ($check in $checks) {
    Write-CheckResult -Name $check.Name -Status $check.Result.Status -Detail $check.Result.Detail
    if ($check.Result.Status -eq 'FAIL') {
        $failures.Add($check.Name)
    }
}

if ($failures.Count -gt 0) {
    Write-Host "workspace-check: FAILED ($($failures.Count)): $($failures -join ', ')" -ForegroundColor Red
    exit 1
}

Write-Host 'workspace-check: all checks passed' -ForegroundColor Green
exit 0
