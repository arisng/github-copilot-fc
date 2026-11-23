<#
.SYNOPSIS
    Automated lint suite for the Copilot FC workspace (the gate for the local
    git hooks and for the ci workflow).
.DESCRIPTION
    Runs the repo's lint checks in one command. Three modes:

    -Quick : fast checks only - markdown lint (full scan vs debt baseline),
             the cross-file consistency/schema engine, and the PowerShell
             lint. Wired to .githooks/pre-commit and `task lint`.

    -SkipAdvisoryWaza : full suite minus the advisory waza check (~21 s,
             never blocks). Wired to .githooks/pre-push so pushes stay fast;
             `task check` and CI keep it for full coverage.

    -UpdateMarkdownBaseline : rewrite scripts/workspace/markdown-debt-baseline.txt
             from the current scan. Run only to accept a reviewed change (or to
             shrink the ratchet after fixing debt); the diff shows every entry.

    (full) : everything -Quick runs, plus waza pin parity, the waza advisory
             report, the supply-chain scan, offline eval preflight, and both
             skill test suites (pytest + Pester). Wired to `task check` and
             .github/workflows/ci.yml. Every result line carries the check's
             elapsed seconds.

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
    3. PowerShell lint - scripts/workspace/check-powershell.ps1 over every
       shipped .ps1: parse failures, the param-clobber pattern (an argument
       overwritten before its first read), and cross-platform portability
       rules (command-position .exe invocations; $env:TEMP in *.Tests.ps1) -
       the Windows-only spellings that passed the local lane while failing
       ubuntu-latest (retro 2026-11-21).
    4. waza pin parity - a stamped local waza release must equal the exact
       pin in .github/workflows/ci.yml: preflight classification is
       version-sensitive (0.39.0 passed an eval 0.40.1 rejects), so drift
       between lanes silently changes the verdict. A 'dev' build (go
       install at the pin - what CI itself runs) passes.
    5. waza check (advisory) - skill-quality report (exit 2 = known pre-existing
       backlog; reported as WARN, never blocking: waza gate/run CI gating stays
       deferred per instructions/waza-eval.instructions.md). A missing or
       crashing waza CLI fails the check.
    6. Supply chain - scripts/workspace/check-supply-chain.py: flags
       shell-install pipes, insecure plaintext links, un-SRI'd CDN script tags,
       and link domains outside scripts/workspace/known-domains.txt
       (warn-first; --strict is the future ratchet target).
    7. Eval preflight - `waza preflight` over every evals/*/eval.yaml: offline
       schema/inventory validation against waza's embedded authoritative schema
       (no execution - waza gate/run stays deferred). Schema/configuration
       errors FAIL; resource.file fixture debt WARNs.
    8. Skill tests - `python3 -m pytest skills -q`: the pytest suites under
       skills/*/tests (regression tests for skill scripts). Wired here so a red
       suite blocks the push instead of sitting unwired behind `task test`.
    9. Skill tests (Pester) - Invoke-Pester over skills/ and scripts/
       (*.Tests.ps1). A FAIL detail names the failing test paths, because a
       count alone hid that the failures were one suite (retro 2026-11-21).

    Exits non-zero when any check FAILs. Used by .githooks/pre-commit (-Quick),
    .githooks/pre-push (-SkipAdvisoryWaza), and task check / CI (full).
.EXAMPLE
    pwsh -NoProfile -File scripts/workspace/workspace-check.ps1 -Quick
#>
[CmdletBinding()]
param(
    # Fast subset for pre-commit: markdown lint + consistency engine only.
    [switch]$Quick,
    # Skip the advisory waza check only (~21 s, exit 2 is a tolerated WARN):
    # pre-push passes this so the push gate keeps enforcement minus the
    # slowest non-blocking check; task check / CI still run it.
    [switch]$SkipAdvisoryWaza,
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
        [Parameter(Mandatory)][string]$Detail,
        # Elapsed seconds for this check; negative omits the timing suffix.
        [double]$Seconds = -1
    )
    $icon = @{ PASS = '[PASS]'; WARN = '[WARN]'; FAIL = '[FAIL]'; SKIP = '[SKIP]' }[$Status]
    $color = @{ PASS = 'Green'; WARN = 'Yellow'; FAIL = 'Red'; SKIP = 'Gray' }[$Status]
    $elapsed = if ($Seconds -ge 0) { ' ({0:N1}s)' -f $Seconds } else { '' }
    Write-Host "$icon $Name$elapsed - $Detail" -ForegroundColor $color
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

function Test-WazaPin {
    [CmdletBinding()]
    param()

    # Version parity with the cloud lane (retro 2026-11-21): preflight
    # classification is version-sensitive - release 0.39.0 passed an eval
    # that 0.40.1 rejects - so a stamped local release must equal the exact
    # pin CI installs. A 'dev' build (go install @ the pin, which is what CI
    # itself runs) carries the pin's content without a stamped version and
    # passes; only a stamped mismatch means drift.
    if (-not (Get-Command waza -ErrorAction SilentlyContinue)) {
        return @{ Status = 'FAIL'; Detail = 'waza CLI not found on PATH - install the release pinned in .github/workflows/ci.yml (see instructions/waza-eval.instructions.md)' }
    }
    $ciText = Get-Content -Raw -LiteralPath (Join-Path $repoRoot '.github' 'workflows' 'ci.yml') -ErrorAction SilentlyContinue
    if ($ciText -notmatch 'microsoft/waza/cmd/waza@(v\d+\.\d+\.\d+)') {
        return @{ Status = 'FAIL'; Detail = 'waza pin not found in .github/workflows/ci.yml (expected: go install github.com/microsoft/waza/cmd/waza@vX.Y.Z)' }
    }
    $pin = $Matches[1]
    $versionText = ((& waza --version 2>&1) | Out-String).Trim()
    if ($versionText -notmatch '(\d+\.\d+\.\d+)') {
        return @{ Status = 'PASS'; Detail = "waza dev build - content from go install @ $pin (no stamped version)" }
    }
    $local = "v$($Matches[1])"
    if ($local -ne $pin) {
        return @{ Status = 'FAIL'; Detail = "waza version drift: local $local vs CI pin $pin - install the pinned release (microsoft/waza releases)" }
    }
    return @{ Status = 'PASS'; Detail = "waza $local matches the CI pin" }
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

    # Skill Pester suites (skills/**/*.Tests.ps1) plus the gate's own suites
    # (scripts/**/*.Tests.ps1) are the scripts' own guardrail; without this
    # check they never run in any repo gate
    # (task test is pytest-only). Full mode only — the quick pre-commit
    # gate stays fast.
    $scanRoots = @((Join-Path $repoRoot 'skills'), (Join-Path $repoRoot 'scripts'))
    $testFiles = @($scanRoots | ForEach-Object {
            Get-ChildItem -Path $_ -Recurse -Filter '*.Tests.ps1' -File -ErrorAction SilentlyContinue
        } |
        Where-Object { $_.FullName -notmatch '\\\.archived\\' })
    if ($testFiles.Count -eq 0) {
        return @{ Status = 'SKIP'; Detail = 'no skills/**/*.Tests.ps1 found' }
    }
    if (-not (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version.Major -ge 5 })) {
        return @{ Status = 'FAIL'; Detail = 'Pester 5+ not available - Install-Module Pester -Scope CurrentUser' }
    }
    $dirs = @($testFiles | ForEach-Object { $_.DirectoryName } | Sort-Object -Unique)
    try {
        # Redirect warning (3) and information (6) streams: test code under
        # test writes Write-Information/Write-Warning noise (daily-report
        # evidence blocks, stale-COPILOT_CLI_PATH warnings) that otherwise
        # leaks into git-hook output and reads as push failure (retro 2026-11-21).
        $result = Invoke-Pester -Path $dirs -PassThru -Output None 3>$null 6>$null
    }
    catch {
        return @{ Status = 'FAIL'; Detail = "Invoke-Pester failed: $($_.Exception.Message)" }
    }
    if ($result.FailedCount -gt 0) {
        # Name the failures: a count alone hid that they were all one suite
        # and cost a Linux container round-trip to localize (retro 2026-11-21).
        $names = @($result.Failed | Select-Object -First 4 | ForEach-Object { $_.ExpandedPath })
        $more = if ($result.FailedCount -gt 4) { "; +$($result.FailedCount - 4) more" } else { '' }
        return @{ Status = 'FAIL'; Detail = "$($result.FailedCount) failed / $($result.TotalCount) Pester tests ($($testFiles.Count) file(s) in $($dirs.Count) dir(s)): $($names -join '; ')$more" }
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
            # --tb=line puts the assertion message on the failure's own line.
            # Without it the gate printed only the node id, so a flake and a
            # real regression looked identical and the only safe response was a
            # full re-run (retro 2026-11-23).
            & python3 -m pytest skills -q --tb=line *> $tempOut
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
        # Name the failing test AND why: the traceback line carries the
        # assertion text that separates a flake from a regression.
        $failedNames = @($lines | Where-Object { $_ -match '^FAILED|^ERROR' } | Select-Object -First 3)
        $traceLines = @($lines | Where-Object { $_ -match '^[A-Za-z]:[\\/].*:\d+:' } | Select-Object -First 3)
        $detail = (@($failedNames) + @($traceLines) | Where-Object { $_ }) -join ' | '
        if (-not $detail) { $detail = $summary }
        return @{ Status = 'FAIL'; Detail = "skill tests failed - run: python3 -m pytest skills -q ($detail); install with python3 -m pip install pytest if the module is missing" }
    }
    return @{ Status = 'PASS'; Detail = "skill tests pass - $summary" }
}

function Test-PowerShellLint {
    [CmdletBinding()]
    param()

    # Static analysis over every *.ps1 the repo ships (retro 2026-11-21):
    # parse failures plus the param-clobber pattern (an argument overwritten
    # before its first read) - two speckit scripts had shipped unparseable
    # and two clobbers reached main, both without any gate catching them.
    $lintScript = Join-Path $repoRoot 'scripts' 'workspace' 'check-powershell.ps1'
    if (-not (Test-Path $lintScript)) {
        return @{ Status = 'FAIL'; Detail = 'missing scripts/workspace/check-powershell.ps1' }
    }
    # Subprocess: the linter exits with a code, which would take this host down.
    $psExe = (Get-Process -Id $PID).Path
    $out = @(& $psExe -NoProfile -File $lintScript 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE -eq 0) {
        $detail = ($out | Select-Object -Last 1) -replace '^\[PASS\] pshlint: ', ''
        return @{ Status = 'PASS'; Detail = $detail }
    }
    $first = @($out | Where-Object { $_ -match '^\[FAIL\]' } | Select-Object -First 2) -join ' | '
    if (-not $first) { $first = ($out -join ' | ') }
    return @{ Status = 'FAIL'; Detail = "$first - run: pwsh scripts/workspace/check-powershell.ps1" }
}

# --- Run -------------------------------------------------------------------
# Checks are scriptblocks so each can be timed as it runs (retro 2026-11-21:
# the gate reported verdicts but never durations, hiding that the advisory
# waza check alone cost ~21 s of every push).
$checks = @(
    @{ Name = 'Markdown lint'; Action = { Test-MarkdownLint } },
    @{ Name = 'Consistency'; Action = { Test-Consistency } },
    @{ Name = 'PowerShell lint'; Action = { Test-PowerShellLint } }
)
if (-not $Quick) {
    $checks += @{ Name = 'waza pin parity'; Action = { Test-WazaPin } }
    if (-not $SkipAdvisoryWaza) {
        $checks += @{ Name = 'waza check (advisory)'; Action = { Invoke-WazaCheck } }
    }
    $checks += @(
        @{ Name = 'Supply chain'; Action = { Test-SupplyChain } },
        @{ Name = 'Eval preflight'; Action = { Test-EvalPreflight } },
        @{ Name = 'Skill tests'; Action = { Invoke-SkillTests } },
        @{ Name = 'Skill tests (Pester)'; Action = { Test-SkillPester } }
    )
}

$gateTimer = [System.Diagnostics.Stopwatch]::StartNew()
foreach ($check in $checks) {
    $checkTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $result = & $check.Action
    $checkTimer.Stop()
    Write-CheckResult -Name $check.Name -Status $result.Status -Detail $result.Detail -Seconds $checkTimer.Elapsed.TotalSeconds
    if ($result.Status -eq 'FAIL') {
        $failures.Add($check.Name)
    }
}
$gateTimer.Stop()

if ($failures.Count -gt 0) {
    Write-Host "workspace-check: FAILED ($($failures.Count)): $($failures -join ', ') ($([math]::Round($gateTimer.Elapsed.TotalSeconds,1))s)" -ForegroundColor Red
    exit 1
}

$mode = if ($Quick) { ' (quick)' } elseif ($SkipAdvisoryWaza) { ' (push)' } else { '' }
Write-Host "workspace-check$mode : all checks passed in $([math]::Round($gateTimer.Elapsed.TotalSeconds,1))s" -ForegroundColor Green
exit 0
