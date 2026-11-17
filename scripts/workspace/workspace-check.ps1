<#
.SYNOPSIS
    Local CI: run all workspace quality checks in one command.

.DESCRIPTION
    Aggregates the repo's quality gates (local CI only — no cloud workflows):

    1. TOC freshness — regenerates the copilot-vscode-docs documentation TOC to a
       temp file and compares it with assets/toc.md. Fails when the generator is
       broken or the committed TOC is stale vs upstream toc.json. A network
       failure downgrades to a warning so offline pushes still work.
    2. waza check — advisory skill-quality report (exit 2 = known pre-existing
       backlog; reported but non-blocking, because waza gate/run CI gating is
       deferred per instructions/waza-eval.instructions.md). A missing or
       crashing waza CLI fails the check.
    3. Skill pytest — `python3 -m pytest skills -q` over every skills/*/tests suite.
    4. Markdown lint — markdownlint-cli2 over the .md files changed in the working
       tree or pending on the branch (a ratchet: touch it, fix it). An npx that
       cannot bootstrap (offline first run) downgrades to a warning.

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

function Test-SkillPytest {
    [CmdletBinding()]
    param()

    if (-not (Get-Command python3 -ErrorAction SilentlyContinue)) {
        return @{ Status = 'FAIL'; Detail = 'python3 not found on PATH (required to run skill tests)' }
    }

    $tempOut = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-pytest-" + [guid]::NewGuid().ToString() + '.txt')
    Push-Location $repoRoot
    try {
        & python3 -m pytest skills -q *> $tempOut
        $code = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    try {
        if ($code -eq 0) {
            $summary = (Get-Content -Path $tempOut -Tail 1)
            return @{ Status = 'PASS'; Detail = "skill pytest clean ($summary)" }
        }
        if ($code -eq 5) {
            return @{ Status = 'SKIP'; Detail = 'no skill tests collected' }
        }
        return @{ Status = 'FAIL'; Detail = "skill pytest failed (exit $code) - run 'python3 -m pytest skills -q' (missing pytest? python3 -m pip install pytest)" }
    }
    finally {
        Remove-Item -Path $tempOut -ErrorAction SilentlyContinue
    }
}

function Test-MarkdownLint {
    [CmdletBinding()]
    param()

    if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
        return @{ Status = 'FAIL'; Detail = 'npx not found on PATH (required for markdown lint)' }
    }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        return @{ Status = 'FAIL'; Detail = 'git not found on PATH (needed to find changed .md files)' }
    }

    $changed = [System.Collections.Generic.List[string]]::new()
    Push-Location $repoRoot
    try {
        # Working tree (staged + unstaged), untracked files, and branch commits
        # not yet on the upstream — the set a push would carry.
        foreach ($line in @(& git diff --name-only --diff-filter=ACM HEAD -- '*.md')) {
            if ($line) { $changed.Add($line.Trim()) }
        }
        foreach ($line in @(& git ls-files --others --exclude-standard -- '*.md')) {
            if ($line) { $changed.Add($line.Trim()) }
        }
        $null = & git rev-parse --abbrev-ref '--symbolic-full-name' '@{upstream}' 2>$null
        if ($LASTEXITCODE -eq 0) {
            foreach ($line in @(& git diff --name-only --diff-filter=ACM '@{upstream}...HEAD' -- '*.md')) {
                if ($line) { $changed.Add($line.Trim()) }
            }
        }
    }
    finally {
        Pop-Location
    }

    # Defense in depth: drop paths the markdownlint config ignores, so they are
    # never handed to the linter as explicit inputs.
    $denyPattern = '(^|/)(node_modules|\.archived|\.build|\.playwright-cli|\.ralph-sessions|\.issues|workshops)(/|$)|^scripts/test/\.artifacts/|^evals/[^/]+/(fixtures|results)/'
    $files = @($changed | Sort-Object -Unique | Where-Object { $_ -notmatch $denyPattern } | Where-Object { Test-Path -LiteralPath (Join-Path $repoRoot $_) })
    if ($files.Count -eq 0) {
        return @{ Status = 'SKIP'; Detail = 'no changed .md files' }
    }

    # Probe first: markdownlint-cli2 bootstraps through npx on first use, so an
    # offline environment downgrades to a warning instead of blocking the push.
    & npx --yes markdownlint-cli2 --version *> $null
    if ($LASTEXITCODE -ne 0) {
        return @{ Status = 'WARN'; Detail = 'markdownlint-cli2 unavailable via npx (offline first run?) - markdown lint skipped this run' }
    }

    $rel = $files | ForEach-Object { $_ -replace '\\', '/' }
    Push-Location $repoRoot
    try {
        $lintOutput = & npx --yes markdownlint-cli2 @rel 2>&1
        $code = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    # Native stdout is part of the function's return stream — echo it via the
    # host so the returned value stays a single hashtable.
    if ($lintOutput) {
        Write-Host (($lintOutput | Out-String).TrimEnd())
    }
    if ($code -eq 0) {
        return @{ Status = 'PASS'; Detail = "$($files.Count) changed .md file(s) lint clean" }
    }
    return @{ Status = 'FAIL'; Detail = "markdownlint violations in changed .md files (exit $code) - run 'npx --yes markdownlint-cli2 <file>' for details" }
}

# ---------------------------------------------------------------------------
# Run all checks
# ---------------------------------------------------------------------------
$checks = @(
    @{ Name = 'TOC freshness'; Result = Test-TocFreshness },
    @{ Name = 'waza check (advisory)'; Result = Invoke-WazaCheck },
    @{ Name = 'Skill pytest'; Result = Test-SkillPytest },
    @{ Name = 'Markdown lint'; Result = Test-MarkdownLint }
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
