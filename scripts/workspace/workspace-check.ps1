<#
.SYNOPSIS
    Automated lint suite for the Copilot FC workspace (local CI - no cloud workflows).
.DESCRIPTION
    Runs the repo's lint checks in one command. Two modes:

    -Quick : fast checks only - markdown lint over changed .md files plus the
             cross-file consistency/schema engine. Wired to .githooks/pre-commit
             and `task lint`.

    (full) : everything -Quick runs, plus the waza advisory report, the
             supply-chain scan, and offline eval preflight. Wired to
             .githooks/pre-push and `task check`.

    Checks (full suite):
    1. Markdown lint - markdownlint-cli2 over the .md files changed in the
       working tree or pending on the branch (a ratchet: touch it, fix it).
       An npx that cannot bootstrap (offline first run) downgrades to a warning.
    2. Consistency - scripts/workspace/check-consistency.ps1: jsonschema
       validation of plugin/skill/marketplace/instruction frontmatter against
       schemas/ (validate-manifests.py), cross-file rules (skill dir<->name,
       body budgets, agent name uniqueness, EMBED marker resolution, no -beta
       identity in source), skills-catalog freshness, issues-index freshness,
       and marketplace parity via the shipped verifier once an index exists.
    3. waza check (advisory) - skill-quality report (exit 2 = known pre-existing
       backlog; reported as WARN, never blocking: waza gate/run CI gating stays
       deferred per instructions/waza-eval.instructions.md). A missing or
       crashing waza CLI fails the check.
    4. Supply chain - scripts/workspace/check-supply-chain.py: flags
       shell-install pipes, insecure plaintext links, un-SRI'd CDN script tags,
       and link domains outside scripts/workspace/known-domains.txt
       (warn-first; --strict is the future ratchet target).
    5. Eval preflight - `waza preflight` over every evals/*/eval.yaml: offline
       schema/inventory validation against waza's embedded authoritative schema
       (no execution - waza gate/run stays deferred). Schema/configuration
       errors FAIL; resource.file fixture debt WARNs.

    Exits non-zero when any check FAILs. Used by .githooks/pre-commit (-Quick)
    and .githooks/pre-push (full).
.EXAMPLE
    pwsh -NoProfile -File scripts/workspace/workspace-check.ps1 -Quick
#>
[CmdletBinding()]
param(
    # Fast subset for pre-commit: markdown lint + consistency engine only.
    [switch]$Quick
)

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
        # not yet on the upstream - the set a push would carry.
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
    $denyPattern = '(^|/)(node_modules|\.archived|\.build|\.playwright-cli|\.issues|workshops)(/|$)|^evals/[^/]+/(fixtures|results)/|^docs/blazor-agui/'
    $files = @($changed | Sort-Object -Unique | Where-Object { $_ -notmatch $denyPattern } | Where-Object { Test-Path -LiteralPath (Join-Path $repoRoot $_) })
    if ($files.Count -eq 0) {
        return @{ Status = 'SKIP'; Detail = 'no changed .md files' }
    }

    # Probe first: markdownlint-cli2 bootstraps through npx on first use, so an
    # offline environment downgrades to a warning instead of blocking the hook.
    & npx --yes markdownlint-cli2 --version *> $null
    if ($LASTEXITCODE -ne 0) {
        return @{ Status = 'WARN'; Detail = 'markdownlint-cli2 unavailable via npx (offline first run?) - markdown lint skipped this run' }
    }

    # Wrap in @(): a pipeline yielding one path returns a scalar string, and
    # splatting a string enumerates its characters as separate arguments.
    $rel = @($files | ForEach-Object { $_ -replace '\\', '/' })
    Push-Location $repoRoot
    try {
        $lintOutput = & npx --yes markdownlint-cli2 @rel 2>&1
        $code = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    # Native stdout is part of the function's return stream - echo it via the
    # host so the returned value stays a single hashtable.
    if ($lintOutput) {
        Write-Host (($lintOutput | Out-String).TrimEnd())
    }
    if ($code -eq 0) {
        return @{ Status = 'PASS'; Detail = "$($files.Count) changed .md file(s) lint clean" }
    }
    return @{ Status = 'FAIL'; Detail = "markdownlint violations in changed .md files (exit $code) - run 'npx --yes markdownlint-cli2 <file>' for details" }
}

function Test-Consistency {
    [CmdletBinding()]
    param()

    $checker = Join-Path $repoRoot 'scripts/workspace/check-consistency.ps1'
    if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        return @{ Status = 'FAIL'; Detail = 'pwsh not found on PATH (required to run the consistency checker)' }
    }
    $tempOut = Join-Path ([System.IO.Path]::GetTempPath()) ("consistency-" + [guid]::NewGuid().ToString() + '.txt')
    try {
        # Child process on purpose: the checker ends with `exit`, which would
        # otherwise take this gate down with it.
        & pwsh -NoProfile -File $checker *> $tempOut
        $code = $LASTEXITCODE
        $lines = @(Get-Content -Path $tempOut -ErrorAction SilentlyContinue)
    }
    finally {
        Remove-Item -Path $tempOut -ErrorAction SilentlyContinue
    }

    $summary = if ($lines.Count -gt 0) { $lines[$lines.Count - 1] } else { 'checker produced no output' }
    if ($code -eq 0) {
        $warns = @($lines | Where-Object { $_ -match '^\[WARN\]' })
        if ($warns.Count -gt 0) {
            return @{ Status = 'WARN'; Detail = "$($warns.Count) consistency warning(s), ratchet-pending: $($warns[0] -replace '^\[WARN\] ', '')" }
        }
        return @{ Status = 'PASS'; Detail = $summary }
    }
    if ($code -eq 2) {
        return @{ Status = 'FAIL'; Detail = 'consistency checker: required tooling missing (python3/jsonschema/PyYAML)' }
    }
    $failLines = @($lines | Where-Object { $_ -match '^\[FAIL\]' })
    $shown = (@($failLines | Select-Object -First 3) -join ' | ')
    return @{ Status = 'FAIL'; Detail = "consistency checker found $($failLines.Count) failure(s): $shown - run: pwsh -NoProfile -File scripts/workspace/check-consistency.ps1" }
}

function Invoke-WazaCheck {
    [CmdletBinding()]
    param()

    if (-not (Get-Command waza -ErrorAction SilentlyContinue)) {
        return @{ Status = 'FAIL'; Detail = 'waza CLI not found on PATH - install it (skill-eval tool, see instructions/waza-eval.instructions.md)' }
    }

    $tempOut = Join-Path ([System.IO.Path]::GetTempPath()) ("waza-check-" + [guid]::NewGuid().ToString() + '.txt')
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

function Test-SupplyChain {
    [CmdletBinding()]
    param()

    $checker = Join-Path $repoRoot 'scripts/workspace/check-supply-chain.py'
    if (-not (Get-Command python3 -ErrorAction SilentlyContinue)) {
        return @{ Status = 'FAIL'; Detail = 'python3 not found on PATH (required for the supply-chain check)' }
    }
    $tempOut = Join-Path ([System.IO.Path]::GetTempPath()) ("supply-chain-" + [guid]::NewGuid().ToString() + '.txt')
    try {
        # Default mode exits 0 even with warnings (warn-first); nonzero means
        # the tool itself broke (git listing failure) or --strict leaked in.
        & python3 $checker *> $tempOut
        $code = $LASTEXITCODE
        $lines = @(Get-Content -Path $tempOut -ErrorAction SilentlyContinue)
    }
    finally {
        Remove-Item -Path $tempOut -ErrorAction SilentlyContinue
    }

    $summary = if ($lines.Count -gt 0) { $lines[$lines.Count - 1] } else { 'checker produced no output' }
    if ($code -ne 0) {
        return @{ Status = 'FAIL'; Detail = "supply-chain checker crashed (exit $code): $summary" }
    }
    $warns = @($lines | Where-Object { $_ -match '^\[WARN\]' })
    if ($warns.Count -gt 0) {
        return @{ Status = 'WARN'; Detail = "$($warns.Count) supply-chain warning(s), ratchet-pending: $($warns[0] -replace '^\[WARN\] ', '')" }
    }
    return @{ Status = 'PASS'; Detail = $summary }
}

function Test-EvalPreflight {
    [CmdletBinding()]
    param()

    # Classification per instructions/waza-eval.instructions.md triage order:
    #   schema/configuration errors -> FAIL (a corrupt eval.yaml must fail),
    #   resource.file / other [error] -> WARN (fixture/path debt: fixture-class
    #   triage before any content edit, never a gate blocker for unrelated work).
    if (-not (Get-Command waza -ErrorAction SilentlyContinue)) {
        return @{ Status = 'FAIL'; Detail = 'waza CLI not found on PATH - install it (see instructions/waza-eval.instructions.md)' }
    }
    $evalFiles = @(Get-ChildItem -Path (Join-Path $repoRoot 'evals') -Filter 'eval.yaml' -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\\.archived\\' } |
        Sort-Object FullName)
    if ($evalFiles.Count -eq 0) {
        return @{ Status = 'SKIP'; Detail = 'no evals/*/eval.yaml found' }
    }

    $structural = [System.Collections.Generic.List[string]]::new()
    $debt = [System.Collections.Generic.List[string]]::new()
    foreach ($file in $evalFiles) {
        $short = $file.Directory.Name
        $tempOut = Join-Path ([System.IO.Path]::GetTempPath()) ("preflight-" + [guid]::NewGuid().ToString() + '.txt')
        try {
            Push-Location $repoRoot
            try {
                & waza preflight $file.FullName *> $tempOut
                $code = $LASTEXITCODE
            }
            finally {
                Pop-Location
            }
            $lines = @(Get-Content -Path $tempOut -ErrorAction SilentlyContinue)
        }
        finally {
            Remove-Item -Path $tempOut -ErrorAction SilentlyContinue
        }
        if ($code -eq 0) { continue }
        $output = $lines -join "`n"
        if ($output -match 'invalid eval\.(schema|configuration)') {
            $structural.Add($short)
        }
        else {
            $debt.Add($short)
        }
    }
    if ($structural.Count -gt 0) {
        return @{ Status = 'FAIL'; Detail = "waza preflight schema/configuration failure in: $($structural -join ', ') - corrupt eval.yaml; run: waza preflight evals/<name>/eval.yaml" }
    }
    if ($debt.Count -gt 0) {
        return @{ Status = 'WARN'; Detail = "$($debt.Count) eval(s) with resource.file/fixture debt (ratchet-pending, fixture-class triage): $($debt -join ', ')" }
    }
    return @{ Status = 'PASS'; Detail = "$($evalFiles.Count) eval(s) pass offline waza preflight" }
}

# --- Run -------------------------------------------------------------------
$checks = @(
    @{ Name = 'Markdown lint'; Result = Test-MarkdownLint },
    @{ Name = 'Consistency'; Result = Test-Consistency }
)
if (-not $Quick) {
    $checks += @(
        @{ Name = 'waza check (advisory)'; Result = Invoke-WazaCheck },
        @{ Name = 'Supply chain'; Result = Test-SupplyChain },
        @{ Name = 'Eval preflight'; Result = Test-EvalPreflight }
    )
}

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

$mode = if ($Quick) { ' (quick)' } else { '' }
Write-Host "workspace-check$mode : all checks passed" -ForegroundColor Green
exit 0
