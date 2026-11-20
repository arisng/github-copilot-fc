<#
.SYNOPSIS
    Automated lint suite for the Copilot FC workspace (local CI - no cloud workflows).
.DESCRIPTION
    Runs the repo's lint checks in one command. Two modes:

    -Quick : fast checks only - markdown lint (full scan vs debt baseline)
             plus the cross-file consistency/schema engine. Wired to
             .githooks/pre-commit and `task lint`.

    -UpdateMarkdownBaseline : rewrite scripts/workspace/markdown-debt-baseline.txt
             from the current scan. Run only to accept a reviewed change (or to
             shrink the ratchet after fixing debt); the diff shows every entry.

    (full) : everything -Quick runs, plus the waza advisory report, the
             supply-chain scan, and offline eval preflight. Wired to
             .githooks/pre-push and `task check`.

    Checks (full suite):
    1. Markdown lint - full-repo markdownlint-cli2 scan compared against the
       frozen-debt baseline (scripts/workspace/markdown-debt-baseline.txt):
       debt files pass at their recorded per-file count, and any new file or
       count increase FAILs (so legacy debt never drags a touched file, and no
       file - changed, renamed, or new - can slip in unlinted). An npx that
       cannot bootstrap (offline first run) downgrades to a warning.
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
    6. Skill tests - `python3 -m pytest skills -q`: the pytest suites under
       skills/*/tests (regression tests for skill scripts). Wired here so a red
       suite blocks the push instead of sitting unwired behind `task test`.

    Exits non-zero when any check FAILs. Used by .githooks/pre-commit (-Quick)
    and .githooks/pre-push (full).
.EXAMPLE
    pwsh -NoProfile -File scripts/workspace/workspace-check.ps1 -Quick
#>
[CmdletBinding()]
param(
    # Fast subset for pre-commit: markdown lint + consistency engine only.
    [switch]$Quick,
    # Rewrite the markdown debt baseline from the current scan output; run
    # only to accept a reviewed change (the diff then shows every entry).
    [switch]$UpdateMarkdownBaseline
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
    # Pin the linter: a gate result must not depend on registry drift
    # (retro candidate 5; version drifted mid-session once already).
    $linter = 'markdownlint-cli2@0.24.2'
    $baselinePath = Join-Path $repoRoot 'scripts/workspace' 'markdown-debt-baseline.txt'

    # Probe first: markdownlint-cli2 bootstraps through npx on first use, so an
    # offline environment downgrades to a warning instead of blocking the hook.
    & npx --yes $linter --version *> $null
    if ($LASTEXITCODE -ne 0) {
        return @{ Status = 'WARN'; Detail = 'markdownlint-cli2 unavailable via npx (offline first run?) - markdown lint skipped this run' }
    }

    # Full-repo scan against the committed debt baseline (retro candidates 1+5):
    # every .md the config does not ignore is linted on every run, so rename
    # targets, brand-new files, and untouched files are all covered - the old
    # changed-file enumeration (git diff --diff-filter=ACM, which silently
    # drops R-status renames) is gone entirely. Legacy debt is frozen at a
    # per-file issue count: it never blocks (no touch-it-fix-it drag), while
    # any count increase or any file missing from the baseline FAILs.
    Push-Location $repoRoot
    try {
        $lintOutput = @(& npx --yes $linter "**/*.md" 2>&1)
        $code = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    if ($code -notin 0, 1) {
        return @{ Status = 'FAIL'; Detail = "markdownlint-cli2 crashed (exit $code) - run manually: npx $linter '**/*.md'" }
    }

    # Aggregate `path:line[:col] error RULE/...` output lines to per-file counts.
    $violations = @{}
    $unparsed = 0
    foreach ($line in $lintOutput) {
        $text = "$line"
        if ($text -notmatch ' error ') { continue }
        if ($text -match '^(?<file>[^:]+\.md):\d+(?::\d+)? error ') {
            $file = $Matches.file -replace '\\', '/'
            $violations[$file] = [int]$violations[$file] + 1
        }
        else { $unparsed++ }
    }

    if ($UpdateMarkdownBaseline) {
        $newLines = @(
            '# Markdownlint debt baseline - one "<path>\t<issue-count>" per line: frozen'
            '# legacy debt that workspace-check allows at exactly this count. Any file'
            '# missing from this list must be violation-free; any count increase fails.'
            '# Regenerate only to accept a reviewed change (the diff shows every entry):'
            '#   pwsh -NoProfile -File scripts/workspace/workspace-check.ps1 -UpdateMarkdownBaseline'
        )
        foreach ($path in ($violations.Keys | Sort-Object)) {
            $newLines += "$path`t$($violations[$path])"
        }
        Set-Content -Path $baselinePath -Value $newLines -Encoding utf8NoBOM
        $total = [int]($violations.Values | Measure-Object -Sum).Sum
        return @{ Status = 'PASS'; Detail = "baseline rewritten: $total issue(s) across $($violations.Count) file(s)" }
    }

    if (-not (Test-Path -LiteralPath $baselinePath)) {
        return @{ Status = 'FAIL'; Detail = 'markdown debt baseline missing - run: pwsh -NoProfile -File scripts/workspace/workspace-check.ps1 -UpdateMarkdownBaseline' }
    }
    $baseline = @{}
    foreach ($line in @(Get-Content -LiteralPath $baselinePath)) {
        if ($line -match '^(#|$)') { continue }
        $parts = $line -split "`t"
        if ($parts.Count -eq 2 -and $parts[1] -match '^\d+$') { $baseline[$parts[0]] = [int]$parts[1] }
    }

    $offenders = [System.Collections.Generic.List[string]]::new()
    foreach ($path in $violations.Keys) {
        $count = $violations[$path]
        if (-not $baseline.ContainsKey($path)) {
            $offenders.Add("$path (+$count, new)")
        }
        elseif ($count -gt $baseline[$path]) {
            $offenders.Add("$path ($count > $($baseline[$path]))")
        }
    }
    if ($unparsed -gt 0) {
        $offenders.Add("$unparsed unattributed lint output line(s)")
    }

    $stale = 0
    foreach ($path in $baseline.Keys) {
        if (-not $violations.ContainsKey($path)) { $stale++ }
    }

    $total = if ($violations.Count -gt 0) { [int]($violations.Values | Measure-Object -Sum).Sum } else { 0 }
    if ($offenders.Count -gt 0) {
        $shown = (@($offenders | Select-Object -First 3) -join '; ')
        return @{ Status = 'FAIL'; Detail = "new markdown debt: $shown - fix it (npx $linter <file>), or regenerate the baseline explicitly if the change is intentional" }
    }
    $shrinkHint = if ($stale -gt 0) { "; $stale stale baseline entrie(s) - regenerate to shrink" } else { '' }
    return @{ Status = 'PASS'; Detail = "baseline clean: $total frozen issue(s) across $($violations.Count) debt file(s), 0 new$shrinkHint" }
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

function Test-SkillPester {
    [CmdletBinding()]
    param()

    # Skill Pester suites (skills/**/*.Tests.ps1) are the skill scripts' own
    # guardrail; without this check they never run in any repo gate
    # (task test is pytest-only). Full mode only — the quick pre-commit
    # gate stays fast.
    $testFiles = @(Get-ChildItem -Path (Join-Path $repoRoot 'skills') -Recurse -Filter '*.Tests.ps1' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\\.archived\\' })
    if ($testFiles.Count -eq 0) {
        return @{ Status = 'SKIP'; Detail = 'no skills/**/*.Tests.ps1 found' }
    }
    if (-not (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version.Major -ge 5 })) {
        return @{ Status = 'FAIL'; Detail = 'Pester 5+ not available - Install-Module Pester -Scope CurrentUser' }
    }
    $dirs = @($testFiles | ForEach-Object { $_.DirectoryName } | Sort-Object -Unique)
    try {
        $result = Invoke-Pester -Path $dirs -PassThru -Output None
    }
    catch {
        return @{ Status = 'FAIL'; Detail = "Invoke-Pester failed: $($_.Exception.Message)" }
    }
    if ($result.FailedCount -gt 0) {
        return @{ Status = 'FAIL'; Detail = "$($result.FailedCount) failed / $($result.TotalCount) Pester tests ($($testFiles.Count) file(s) in $($dirs.Count) dir(s))" }
    }
    return @{ Status = 'PASS'; Detail = "$($result.PassedCount) Pester tests green ($($testFiles.Count) file(s) in $($dirs.Count) dir(s))" }
}

function Invoke-SkillTests {
    [CmdletBinding()]
    param()

    # Pytest suites under skills/ (task test): regression tests for skill
    # scripts. Wired into the full gate so a red suite blocks the push -
    # an unwired test suite is silently broken by definition (retro
    # 2026-11-20).
    if (-not (Get-Command python3 -ErrorAction SilentlyContinue)) {
        return @{ Status = 'FAIL'; Detail = 'python3 not found on PATH (required for the skill test suite)' }
    }
    $tempOut = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-tests-" + [guid]::NewGuid().ToString() + '.txt')
    try {
        Push-Location $repoRoot
        try {
            & python3 -m pytest skills -q *> $tempOut
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

    $summary = if ($lines.Count -gt 0) { $lines[$lines.Count - 1] } else { 'pytest produced no output' }
    if ($code -ne 0) {
        $failures = @($lines | Where-Object { $_ -match '^(FAILED|ERROR)' } | Select-Object -First 3) -join ' | '
        if (-not $failures) { $failures = $summary }
        return @{ Status = 'FAIL'; Detail = "skill tests failed - run: python3 -m pytest skills -q ($failures); install with python3 -m pip install pytest if the module is missing" }
    }
    return @{ Status = 'PASS'; Detail = "skill tests pass - $summary" }
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
        @{ Name = 'Eval preflight'; Result = Test-EvalPreflight },
        @{ Name = 'Skill tests'; Result = Invoke-SkillTests },
        @{ Name = 'Skill tests (Pester)'; Result = Test-SkillPester }
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
