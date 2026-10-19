<#
.SYNOPSIS
    Offline tests for the triage-backlog scripts (taxonomy gate, bootstrap, report).

.DESCRIPTION
    Nothing here touches the network or GitHub. `gh` is replaced by an in-scope
    function stub that returns the same compact JSON the real CLI prints and sets
    $LASTEXITCODE explicitly - that is how the failure paths (auth, network) are
    exercised exactly as the scripts see them: a native command that exits
    non-zero writes nothing to stdout and throws nothing.

    Dependency-free on purpose (no Pester): the skill is published to machines
    that may not have it installed.

    Run: pwsh -NoProfile -File ./scripts/tests/test-triage.ps1
#>

$ErrorActionPreference = 'Stop'

$script:ScriptsDir    = Split-Path -Parent $PSScriptRoot
$script:QueuePath     = Join-Path $script:ScriptsDir 'triage-queue.ps1'
$script:SignalsPath   = Join-Path $script:ScriptsDir 'triage-signals.ps1'
$script:BootstrapPath = Join-Path $script:ScriptsDir 'triage-bootstrap.ps1'
$script:ReportPath    = Join-Path $script:ScriptsDir 'triage-report.ps1'
$script:HelpersPath   = Join-Path $script:ScriptsDir 'triage-helpers.ps1'

# Dot-sourced up front (not only before the helper unit tests) so the pure helper
# functions are available to every section, including the ones that call them.
. $script:HelpersPath

$script:AllRequired = @('needs-triage', 'blocked', 'owner-decision', 'priority:P0', 'priority:P1', 'priority:P2', 'priority:P3')

$pass = 0
$fail = 0

# Config discovery is relative to the current directory; run from an empty temp dir
# so no stray triage.json can leak into the expectations.
$work = Join-Path ([System.IO.Path]::GetTempPath()) "triage-tests-$PID"
New-Item -ItemType Directory -Force -Path $work | Out-Null
Push-Location $work

function Write-Pass { param([string]$Name) Write-Host "  PASS: $Name" -ForegroundColor Green; $script:pass++ }
function Write-Fail {
    param([string]$Name, [string]$Detail)
    Write-Host "  FAIL: $Name" -ForegroundColor Red
    if ($Detail) { Write-Host "    $Detail" -ForegroundColor Red }
    $script:fail++
}
function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail)
    if ($Condition) { Write-Pass $Name } else { Write-Fail $Name $Detail }
}
function Assert-Match {
    param([string]$Name, [string]$Pattern, [string]$Text)
    if ($Text -match $Pattern) { Write-Pass $Name } else { Write-Fail $Name "pattern '$Pattern' not found in: $Text" }
}
function Assert-NotMatch {
    param([string]$Name, [string]$Pattern, [string]$Text)
    if ($Text -notmatch $Pattern) { Write-Pass $Name } else { Write-Fail $Name "pattern '$Pattern' unexpectedly found in: $Text" }
}
function Assert-Equal {
    param([string]$Name, $Expected, $Actual)
    if ("$Expected" -eq "$Actual") { Write-Pass $Name } else { Write-Fail $Name "expected '$Expected', got '$Actual'" }
}

# --- gh stub ------------------------------------------------------------------

function Reset-GhStub {
    $global:GhLabels        = @()
    $global:GhLabelListExit = 0
    $global:GhCreateExit    = 0
    $global:GhIssueListExit = 0
    $global:GhCreated       = @()
    $global:GhCalls         = @()
    $global:GhIssues        = @(
        [pscustomobject]@{
            number    = 11
            title     = 'Intake fails on CSV with BOM'
            state     = 'OPEN'
            createdAt = '2026-09-01T00:00:00Z'
            body      = "### Priority`nP1`n### Area`narea:ingest"
            labels    = @([pscustomobject]@{ name = 'needs-triage' })
        }
        [pscustomobject]@{
            number    = 12
            title     = 'Add S3 sink connector'
            state     = 'OPEN'
            createdAt = '2026-09-20T00:00:00Z'
            body      = "### Priority`nP3"
            labels    = @([pscustomobject]@{ name = 'needs-triage' }, [pscustomobject]@{ name = 'priority:P2' })
        }
    )
}

# The stub speaks JSON text (not objects) because that is what the real CLI writes
# to stdout, and the scripts parse it with ConvertFrom-Json.
function global:gh {
    $all = @($args)
    $global:GhCalls += , ($all -join ' ')
    $sub = if ($all.Count -ge 2) { "$($all[0]) $($all[1])" } else { "$($all -join ' ')" }
    switch ($sub) {
        'label list' {
            $global:LASTEXITCODE = $global:GhLabelListExit
            if ($global:GhLabelListExit -ne 0) { return }
            return (ConvertTo-Json -InputObject @($global:GhLabels | ForEach-Object { [pscustomobject]@{ name = $_ } }) -Depth 3 -Compress)
        }
        'label create' {
            $global:LASTEXITCODE = $global:GhCreateExit
            if ($global:GhCreateExit -eq 0) { $global:GhCreated += $all[2] }
            return
        }
        'issue list' {
            $global:LASTEXITCODE = $global:GhIssueListExit
            if ($global:GhIssueListExit -ne 0) { return }
            return (ConvertTo-Json -InputObject @($global:GhIssues) -Depth 6 -Compress)
        }
        default {
            $global:LASTEXITCODE = 1
            return
        }
    }
}

# --- helpers ------------------------------------------------------------------

function Invoke-Skill {
    <# Run a skill script in-session, capturing host output + warnings and any throw. #>
    param([Parameter(Mandatory)][string]$Script, [hashtable]$Parameters = @{})
    $out = ''
    $threw = $false
    $message = ''
    try { $out = (& $Script @Parameters 3>&1 6>&1 | Out-String) }
    catch { $threw = $true; $message = "$_" }
    return [pscustomobject]@{ Output = $out; Threw = $threw; Message = $message }
}

function Write-CustomConfig {
    param([string]$Path)
    @'
{
  "repo": "acme/widgets",
  "needs_triage": "status/triage",
  "blocked": "kind/blocked",
  "owner_decision": "kind/owner",
  "priority_levels": [
    { "code": "P0", "label": "sev/critical", "meaning": "Emergency" },
    { "code": "P1", "label": "sev/high", "meaning": "This cycle" }
  ]
}
'@ | Set-Content -Path $Path -Encoding utf8
}

function New-GatedSignals {
    param([string]$Path)
    $global:GhLabels = $script:AllRequired
    $null = Invoke-Skill -Script $script:SignalsPath -Parameters @{ Repo = 'acme/widgets'; Json = $true; OutFile = $Path }
    return (Get-Content $Path -Raw | ConvertFrom-Json)
}

Reset-GhStub

try {

    Write-Host "`n=== triage-backlog tests ===" -ForegroundColor Cyan

    Write-Host "`nTaxonomy gate: triage-queue.ps1" -ForegroundColor Yellow
    Reset-GhStub
    $r = Invoke-Skill -Script $script:QueuePath -Parameters @{ Repo = 'acme/widgets' }
    Assert-True 'fails when the repo has no taxonomy labels' $r.Threw "no throw: $($r.Output)"
    Assert-Match 'names every required label' 'gate FAILED' $r.Message
    foreach ($label in $script:AllRequired) { Assert-Match "lists '$label'" ([regex]::Escape($label)) $r.Message }
    Assert-Match 'offers the bootstrap recovery step' 'triage-bootstrap\.ps1' $r.Message

    Reset-GhStub
    $global:GhLabels = $script:AllRequired
    $r = Invoke-Skill -Script $script:QueuePath -Parameters @{ Repo = 'acme/widgets' }
    Assert-True 'renders the queue when every required label exists' (-not $r.Threw) $r.Message
    Assert-Match 'shows the queued issues' 'Triage queue: 2 issue' $r.Output
    Assert-Match 'shows issue titles' 'Intake fails on CSV with BOM' $r.Output

    Reset-GhStub
    $global:GhLabelListExit = 1
    $r = Invoke-Skill -Script $script:QueuePath -Parameters @{ Repo = 'acme/widgets' }
    Assert-True 'aborts when gh label list fails' $r.Threw "no throw: $($r.Output)"
    Assert-Match 'says the gate cannot run blind' 'cannot run blind' $r.Message
    Assert-NotMatch 'does not misreport the failure as missing labels' 'required labels missing' $r.Message

    Reset-GhStub
    $r = Invoke-Skill -Script $script:QueuePath -Parameters @{ Repo = 'acme/widgets'; NoLabelCheck = $true }
    Assert-Match 'warns when -NoLabelCheck skips the gate' 'gate skipped via -NoLabelCheck' $r.Output
    Assert-Match 'still renders with -NoLabelCheck' 'Triage queue: 2 issue' $r.Output

    Reset-GhStub
    $config = Join-Path $work 'custom.json'
    Write-CustomConfig -Path $config
    $r = Invoke-Skill -Script $script:QueuePath -Parameters @{ Repo = 'acme/widgets'; Config = $config }
    Assert-Match 'reports the labels the resolved config needs' 'sev/critical' $r.Message
    Assert-Match 'carries -Config into the recovery command' ([regex]::Escape("-Config '$config'")) $r.Message

    Write-Host "`nTaxonomy gate: triage-signals.ps1" -ForegroundColor Yellow
    Reset-GhStub
    $r = Invoke-Skill -Script $script:SignalsPath -Parameters @{ Repo = 'acme/widgets'; Json = $true }
    Assert-True 'aborts when required labels are missing' $r.Threw "no throw: $($r.Output)"
    Assert-Match 'uses the same gate message' 'gate FAILED' $r.Message

    Reset-GhStub
    $global:GhLabelListExit = 1
    $r = Invoke-Skill -Script $script:SignalsPath -Parameters @{ Repo = 'acme/widgets'; Json = $true }
    Assert-True 'aborts when gh label list fails' $r.Threw "no throw: $($r.Output)"
    Assert-Match 'says the gate cannot run blind' 'cannot run blind' $r.Message

    Reset-GhStub
    $global:GhLabels = $script:AllRequired
    $global:GhIssueListExit = 1
    $r = Invoke-Skill -Script $script:SignalsPath -Parameters @{ Repo = 'acme/widgets'; Json = $true }
    Assert-True 'aborts when gh issue list fails' $r.Threw "no throw: $($r.Output)"
    Assert-Match 'reports the issue-list failure' 'gh issue list failed' $r.Message

    Reset-GhStub
    $gated = Join-Path $work 'gated.json'
    $p = New-GatedSignals -Path $gated
    Assert-Equal 'gated payload is schema v3' 3 $p.schema_version
    Assert-Equal 'gated payload records label_check=passed' 'passed' $p.taxonomy.label_check
    Assert-Equal 'gated payload has no missing labels' 0 @($p.taxonomy.missing_labels).Count
    Assert-Equal 'gated payload carries the queue' 2 @($p.queue).Count

    Reset-GhStub
    $skipped = Join-Path $work 'skipped.json'
    $null = Invoke-Skill -Script $script:SignalsPath -Parameters @{ Repo = 'acme/widgets'; Json = $true; OutFile = $skipped; NoLabelCheck = $true }
    $sp = Get-Content $skipped -Raw | ConvertFrom-Json
    Assert-Equal 'gate-skipped payload records label_check=skipped' 'skipped' $sp.taxonomy.label_check
    Assert-Equal 'gate-skipped payload still reports no missing labels' 0 @($sp.taxonomy.missing_labels).Count

    Write-Host "`ntriage-report.ps1 guards the cache it renders" -ForegroundColor Yellow
    Reset-GhStub
    $v2 = Join-Path $work 'v2.json'
    $p = New-GatedSignals -Path $v2
    $p.schema_version = 2
    ($p | ConvertTo-Json -Depth 8) | Set-Content -Path $v2 -Encoding utf8
    $r = Invoke-Skill -Script $script:ReportPath -Parameters @{ SignalsFile = $v2; OutFile = (Join-Path $work 'v2.html') }
    Assert-True 'refuses a pre-v3 cache' $r.Threw "no throw: $($r.Output)"
    Assert-Match 'names the expected schema' 'expects v3' $r.Message

    Reset-GhStub
    $skipCache = Join-Path $work 'skipped.json'
    $null = Invoke-Skill -Script $script:SignalsPath -Parameters @{ Repo = 'acme/widgets'; Json = $true; OutFile = $skipCache; NoLabelCheck = $true }
    $r = Invoke-Skill -Script $script:ReportPath -Parameters @{ SignalsFile = $skipCache; OutFile = (Join-Path $work 'skipped.html') }
    Assert-True 'refuses a cache whose taxonomy gate was skipped' $r.Threw "no throw: $($r.Output)"
    Assert-Match 'explains the skip' 'gate skipped' $r.Message
    Assert-True 'writes no HTML for a skipped cache' (-not (Test-Path (Join-Path $work 'skipped.html')))

    Reset-GhStub
    $missingCache = Join-Path $work 'missing.json'
    $p = New-GatedSignals -Path $missingCache
    $p.taxonomy.missing_labels = @('owner-decision')
    ($p | ConvertTo-Json -Depth 8) | Set-Content -Path $missingCache -Encoding utf8
    $r = Invoke-Skill -Script $script:ReportPath -Parameters @{ SignalsFile = $missingCache; OutFile = (Join-Path $work 'missing.html') }
    Assert-True 'refuses a cache with missing taxonomy labels' $r.Threw "no throw: $($r.Output)"
    Assert-Match 'names the missing labels' 'missing taxonomy labels' $r.Message

    Reset-GhStub
    $goodCache = Join-Path $work 'good.json'
    $goodHtml = Join-Path $work 'good.html'
    $null = New-GatedSignals -Path $goodCache
    $r = Invoke-Skill -Script $script:ReportPath -Parameters @{ SignalsFile = $goodCache; OutFile = $goodHtml }
    Assert-True 'renders a gated v3 cache' (-not $r.Threw) $r.Message
    Assert-True 'writes the report file' (Test-Path $goodHtml)
    Assert-Match 'emits the report body' 'Triage Report' (Get-Content $goodHtml -Raw)

    Write-Host "`ntriage-report.ps1 stamps the header in local time" -ForegroundColor Yellow
    Reset-GhStub
    $tzCache = Join-Path $work 'tz.json'
    $tzHtml = Join-Path $work 'tz.html'
    $p = New-GatedSignals -Path $tzCache
    $p.generated_at = '2026-10-10T15:41:41Z'
    ($p | ConvertTo-Json -Depth 8) | Set-Content -Path $tzCache -Encoding utf8
    $r = Invoke-Skill -Script $script:ReportPath -Parameters @{ SignalsFile = $tzCache; OutFile = $tzHtml }
    Assert-True 'renders a cache with a known generated_at' (-not $r.Threw) $r.Message
    $tzHtmlText = Get-Content $tzHtml -Raw
    $expectedLocal = ([datetimeoffset]::Parse('2026-10-10T15:41:41Z')).ToLocalTime().ToString('yyyy-MM-ddTHH:mm:ssK')
    Assert-Match 'shows the generated stamp in local time' ([regex]::Escape($expectedLocal)) $tzHtmlText
    Assert-Match 'stamps the header with an explicit UTC offset' 'generated <span title="[^"]+">\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}</span>' $tzHtmlText
    Assert-Match 'keeps the UTC instant in the tooltip' 'title="2026-10-10T15:41:41Z \(UTC\)"' $tzHtmlText
    Assert-NotMatch 'does not print the bare UTC stamp as the visible time' 'generated <span[^>]*>2026-10-10T15:41:41Z' $tzHtmlText

    Write-Host "`ntriage-report.ps1 canonical output location" -ForegroundColor Yellow
    Reset-GhStub
    # Explicit -OutFile/-SignalsFile always win (covered above); here the defaults
    # must resolve without them: <repo-root>/.github/triage-backlog/ - ONE location,
    # self-ignoring, in every repo.
    $workRoot = $work
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $top = (& git -C $work rev-parse --show-toplevel 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $top) { $workRoot = $top }
    }
    $r = Invoke-Skill -Script $script:ReportPath -Parameters @{ SignalsFile = $goodCache }
    $canonicalDir = Join-Path $workRoot '.github\triage-backlog'
    $defaultHtml = Join-Path $canonicalDir 'triage-report.html'
    Assert-True 'defaults resolve without explicit paths' ((-not $r.Threw) -and (Test-Path $defaultHtml)) "$($r.Message)$($r.Output)"
    $ignoreFile = Join-Path $canonicalDir '.gitignore'
    Assert-True 'writes a nested .gitignore into the artifact dir' (Test-Path $ignoreFile) $r.Output
    Assert-Match 'the nested .gitignore ignores everything' '(?m)^\*$' (Get-Content $ignoreFile -Raw)

    if (Get-Command git -ErrorAction SilentlyContinue) {
        $gitRepo = Join-Path $work 'git-repo'
        New-Item -ItemType Directory -Force -Path $gitRepo | Out-Null
        git -C $gitRepo init -q
        Push-Location $gitRepo
        try { $r = Invoke-Skill -Script $script:ReportPath -Parameters @{ SignalsFile = $goodCache } }
        finally { Pop-Location }
        $expectedGit = Join-Path $gitRepo '.github\triage-backlog\triage-report.html'
        Assert-True 'writes to <repo-root>/.github/triage-backlog inside a checkout' ((-not $r.Threw) -and (Test-Path $expectedGit)) "$($r.Message)$($r.Output)"
        $null = (& git -C $gitRepo check-ignore -q -- $expectedGit 2>$null)
        Assert-True 'the artifact is git-ignored' ($LASTEXITCODE -eq 0) $r.Output
        Assert-Equal 'git status stays clean (nothing committable)' '' ((& git -C $gitRepo status --porcelain | Out-String).Trim())
    } else {
        Write-Host "  SKIP: git not installed; checkout-root default untested" -ForegroundColor Yellow
    }

    # `output_dir` is deprecated: no longer honored, only reconciled from.
    $global:GhLabels = $script:AllRequired
    $cfgRepo = Join-Path $work 'cfg-repo'
    New-Item -ItemType Directory -Force -Path $cfgRepo | Out-Null
    if (Get-Command git -ErrorAction SilentlyContinue) { git -C $cfgRepo init -q }
    $legacyDir = Join-Path $cfgRepo 'legacy-board'
    New-Item -ItemType Directory -Force -Path $legacyDir | Out-Null
    Set-Content -Path (Join-Path $legacyDir 'triage-report.html') -Value '<html>legacy</html>'
    @{ repo = 'acme/widgets'; output_dir = 'legacy-board' } | ConvertTo-Json |
        Set-Content -Path (Join-Path $cfgRepo '.triage.json') -Encoding utf8
    Push-Location $cfgRepo
    try { $r = Invoke-Skill -Script $script:ReportPath -Parameters @{} }
    finally { Pop-Location }
    $cfgExpected = Join-Path $cfgRepo '.github\triage-backlog\triage-report.html'
    Assert-True 'output_dir no longer redirects the output' ((-not $r.Threw) -and (Test-Path $cfgExpected)) "$($r.Message)$($r.Output)"
    Assert-Match 'warns that output_dir is deprecated' "output_dir' is deprecated" $r.Output
    Assert-True 'reconciles the deprecated output_dir' (-not (Test-Path (Join-Path $legacyDir 'triage-report.html'))) $r.Output
    Assert-Match 'prunes the emptied deprecated dir' 'Removed empty deprecated dir' $r.Output
    Assert-True 'the emptied deprecated dir is gone' (-not (Test-Path $legacyDir)) $r.Output

    Write-Host "`ntriage-report.ps1 reconciles deprecated artifact locations" -ForegroundColor Yellow
    Reset-GhStub
    $global:GhLabels = $script:AllRequired
    $migRepo = Join-Path $work 'mig-repo'
    New-Item -ItemType Directory -Force -Path $migRepo | Out-Null
    $hasGit = [bool](Get-Command git -ErrorAction SilentlyContinue)
    if ($hasGit) { git -C $migRepo init -q }
    # A repo-local config so the report can resolve the target repo without an
    # origin remote (the migration run generates the signals itself).
    @{ repo = 'acme/widgets' } | ConvertTo-Json | Set-Content -Path (Join-Path $migRepo '.triage.json') -Encoding utf8
    $migGitDir = if ($hasGit) { (& git -C $migRepo rev-parse --path-format=absolute --git-dir 2>$null | Out-String).Trim() } else { $null }
    $legacyDirs = @()
    if ($migGitDir) { $legacyDirs += (Join-Path $migGitDir 'triage-backlog') }  # previous default
    $legacyDirs += (Join-Path $migRepo '.github\backlog-triage')               # pre-rename opt-in
    $legacyDirs += (Join-Path $migRepo 'cache')                                # legacy non-git fallback
    foreach ($d in $legacyDirs) {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
        Set-Content -Path (Join-Path $d 'triage-report.html') -Value '<html>legacy</html>'
    }
    Push-Location $migRepo
    try { $r = Invoke-Skill -Script $script:ReportPath -Parameters @{} }
    finally { Pop-Location }
    $migCanonical = Join-Path $migRepo '.github\triage-backlog'
    Assert-True 'renders into the canonical dir' ((-not $r.Threw) -and (Test-Path (Join-Path $migCanonical 'triage-report.html'))) "$($r.Message)$($r.Output)"
    Assert-Match 'reports what it reconciled' 'Reconciled:' $r.Output
    # The canonical copy is authoritative, so only the FIRST (most recent) source is
    # moved; the redundant copies are reported as skipped and left in place rather
    # than overwriting the artifact that just landed.
    $movedFrom = @($legacyDirs | Where-Object { -not (Test-Path (Join-Path $_ 'triage-report.html')) })
    Assert-Equal 'moves exactly one artifact (the most recent source wins)' 1 $movedFrom.Count
    Assert-Equal 'the most recent source is the one moved' $legacyDirs[0] $movedFrom[0]
    Assert-Match 'reports the redundant copies as skipped' 'Skipped:' $r.Output
    foreach ($d in @($legacyDirs | Where-Object { $_ -ne $movedFrom[0] })) {
        Assert-True "leaves the redundant copy in $([System.IO.Path]::GetFileName($d))" (Test-Path (Join-Path $d 'triage-report.html')) $r.Output
    }
    Assert-NotMatch 'prunes nothing here (no emptied dir outside the git dir)' 'Removed empty deprecated dir' $r.Output
    Assert-True 'leaves the emptied dir under the git dir in place' ((-not $migGitDir) -or (Test-Path (Join-Path $migGitDir 'triage-backlog'))) $r.Output

    Push-Location $migRepo
    try { $r = Invoke-Skill -Script $script:ReportPath -Parameters @{ SignalsFile = $goodCache } }
    finally { Pop-Location }
    Assert-NotMatch 'is idempotent: nothing left to reconcile' 'Reconciled:' $r.Output

    $nrRepo = Join-Path $work 'noreconcile-repo'
    New-Item -ItemType Directory -Force -Path $nrRepo | Out-Null
    $nrOld = Join-Path $nrRepo '.github\backlog-triage'
    New-Item -ItemType Directory -Force -Path $nrOld | Out-Null
    Set-Content -Path (Join-Path $nrOld 'triage-report.html') -Value '<html>legacy</html>'
    Push-Location $nrRepo
    try { $r = Invoke-Skill -Script $script:ReportPath -Parameters @{ NoReconcile = $true } }
    finally { Pop-Location }
    Assert-True '-NoReconcile leaves the deprecated artifact in place' (Test-Path (Join-Path $nrOld 'triage-report.html')) $r.Output
    Assert-NotMatch '-NoReconcile reports nothing' 'Reconciled:' $r.Output

    Write-Host "`ntriage-report.ps1 hard rules for repo mutation" -ForegroundColor Yellow

    # The canonical copy is authoritative: a stale deprecated payload never wins.
    $global:GhLabels = $script:AllRequired
    $owRepo = Join-Path $work 'overwrite-repo'
    New-Item -ItemType Directory -Force -Path $owRepo | Out-Null
    $owCanonical = Join-Path $owRepo '.github\triage-backlog'
    New-Item -ItemType Directory -Force -Path $owCanonical | Out-Null
    Copy-Item -LiteralPath $goodCache -Destination (Join-Path $owCanonical 'triage-signals.json') -Force
    $owOld = Join-Path $owRepo '.github\backlog-triage'
    New-Item -ItemType Directory -Force -Path $owOld | Out-Null
    @{ schema_version = 99; repo = 'acme/widgets'; taxonomy = @{ label_check = 'passed'; missing_labels = @() } } |
        ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $owOld 'triage-signals.json') -Encoding utf8
    Push-Location $owRepo
    try { $r = Invoke-Skill -Script $script:ReportPath -Parameters @{} }
    finally { Pop-Location }
    Assert-Equal 'the stale deprecated payload is skipped, not moved' ((Get-Content $goodCache -Raw).Trim()) ((Get-Content (Join-Path $owCanonical 'triage-signals.json') -Raw).Trim())
    Assert-Match 'reports the skip' 'Skipped:' $r.Output
    Assert-True 'leaves the stale deprecated copy in place' (Test-Path (Join-Path $owOld 'triage-signals.json')) $r.Output

    # A hand-written file that merely shares an artifact filename is never moved.
    $trRepo = Join-Path $work 'tracked-repo'
    New-Item -ItemType Directory -Force -Path $trRepo | Out-Null
    git -C $trRepo init -q
    $trDoc = Join-Path $trRepo 'docs'
    New-Item -ItemType Directory -Force -Path $trDoc | Out-Null
    Set-Content -Path (Join-Path $trDoc 'triage-report.html') -Value '<html>hand-written doc</html>'
    git -C $trRepo add -- 'docs/triage-report.html' 2>$null
    git -C $trRepo -c user.name=t -c user.email=t@t commit -q -m init 2>$null
    $trDst = Join-Path $trRepo '.github\triage-backlog'
    # NOTE: do not wrap the call in @() - member enumeration on a 1-element array
    # returns $null for an empty-array property, and @($null).Count is 1.
    $trRecon = Invoke-TriageArtifactReconcile -CanonicalDir $trDst -DeprecatedDirs @($trDoc) -RepoRoot $trRepo
    Assert-Equal 'refuses to move a tracked file' 0 @($trRecon.moved).Count
    Assert-Equal 'reports exactly one skip' 1 @($trRecon.skipped).Count
    Assert-Match 'says why' 'tracked by git' (($trRecon.skipped | ForEach-Object { $_.reason }) -join ' ')
    Assert-True 'the hand-written file survives' (Test-Path (Join-Path $trDoc 'triage-report.html'))
    Assert-True 'it is still committed' ($null -ne (git -C $trRepo ls-files -- 'docs/triage-report.html'))
    Assert-True 'creates no destination dir' (-not (Test-Path $trDst))

    # git owns the tree under the git dir; an empty dir there is never removed.
    $gdRepo = Join-Path $work 'gitdir-prune-repo'
    New-Item -ItemType Directory -Force -Path $gdRepo | Out-Null
    git -C $gdRepo init -q
    $gdDir = (& git -C $gdRepo rev-parse --path-format=absolute --git-dir 2>$null | Out-String).Trim()
    $gdOld = Join-Path $gdDir 'triage-backlog'
    New-Item -ItemType Directory -Force -Path $gdOld | Out-Null
    Set-Content -Path (Join-Path $gdOld 'triage-report.html') -Value '<html/>'
    $gdDst = Join-Path $gdRepo '.github\triage-backlog'
    $gdRecon = Invoke-TriageArtifactReconcile -CanonicalDir $gdDst -DeprecatedDirs @($gdOld) -RepoRoot $gdRepo
    Assert-Equal 'moves the artifact out of the git dir' 1 @($gdRecon.moved).Count
    Assert-True 'leaves the empty dir under the git dir in place' (Test-Path $gdOld)

    # A failed move warns and continues; migration never aborts a run.
    $mfRepo = Join-Path $work 'movefail-repo'
    New-Item -ItemType Directory -Force -Path $mfRepo | Out-Null
    $mfBlock = Join-Path $mfRepo 'blocker'
    Set-Content -Path $mfBlock -Value 'a file where a directory is expected'
    $mfSrc = Join-Path $mfRepo 'cache'
    New-Item -ItemType Directory -Force -Path $mfSrc | Out-Null
    Set-Content -Path (Join-Path $mfSrc 'triage-report.html') -Value '<html/>'
    $mfDst = Join-Path $mfRepo 'blocker\triage-backlog'
    $mfRecon = Invoke-TriageArtifactReconcile -CanonicalDir $mfDst -DeprecatedDirs @($mfSrc) -RepoRoot $mfRepo
    Assert-Equal 'reports the failed move as a skip' 1 @($mfRecon.skipped).Count
    Assert-Match 'names the failure' 'move failed' (($mfRecon.skipped | ForEach-Object { $_.reason }) -join ' ')

    # A hand-written nested .gitignore is appended to, never clobbered.
    $apDir = Join-Path $work 'append-probe'
    New-Item -ItemType Directory -Force -Path $apDir | Out-Null
    Set-Content -Path (Join-Path $apDir '.gitignore') -Value "# mine`n!keep.txt"
    $null = Initialize-TriageArtifactDir -Path $apDir
    $apText = Get-Content (Join-Path $apDir '.gitignore') -Raw
    Assert-Match 'keeps the user rules' '!keep.txt' $apText
    Assert-Match 'appends the enforcement' '(?m)^\*$' $apText
    $null = Initialize-TriageArtifactDir -Path $apDir
    Assert-Equal 'is idempotent once it ignores everything' $apText (Get-Content (Join-Path $apDir '.gitignore') -Raw)

    # A file sitting where the artifact dir should be fails clearly.
    $lfRepo = Join-Path $work 'leaf-repo'
    New-Item -ItemType Directory -Force -Path (Join-Path $lfRepo '.github') | Out-Null
    $lfBlock = Join-Path $lfRepo '.github\triage-backlog'
    Set-Content -Path $lfBlock -Value 'i am a file'
    $threw = $false; $lfMsg = ''
    try { $null = Initialize-TriageArtifactDir -Path $lfBlock } catch { $threw = $true; $lfMsg = "$_" }
    Assert-True 'a file at the artifact path throws clearly' $threw
    Assert-Match 'says what is wrong' 'file already exists' $lfMsg

    Write-Host "`ntriage-signals.ps1 makes the canonical dir self-ignoring" -ForegroundColor Yellow
    $sigRepo = Join-Path $work 'signals-ignore-repo'
    New-Item -ItemType Directory -Force -Path $sigRepo | Out-Null
    git -C $sigRepo init -q
    $global:GhLabels = $script:AllRequired
    Push-Location $sigRepo
    try { $null = Invoke-Skill -Script $script:SignalsPath -Parameters @{ Repo = 'acme/widgets'; Json = $true; OutFile = '.github\triage-backlog\triage-signals.json' } }
    finally { Pop-Location }
    $sigIgnore = Join-Path $sigRepo '.github\triage-backlog\.gitignore'
    Assert-True 'writes the payload where the docs say to' (Test-Path (Join-Path $sigRepo '.github\triage-backlog\triage-signals.json'))
    Assert-True 'makes the canonical dir self-ignoring' (Test-Path $sigIgnore)
    Assert-Match 'the nested .gitignore ignores everything' '(?m)^\*$' (Get-Content $sigIgnore -Raw)
    $null = (& git -C $sigRepo check-ignore -q -- (Join-Path $sigRepo '.github\triage-backlog\triage-signals.json') 2>$null)
    Assert-True 'git confirms the payload is ignored' ($LASTEXITCODE -eq 0)

    # A missing -Config must not break a run that passed explicit paths.
    $lzRepo = Join-Path $work 'lazy-config-repo'
    New-Item -ItemType Directory -Force -Path $lzRepo | Out-Null
    Push-Location $lzRepo
    try { $r = Invoke-Skill -Script $script:ReportPath -Parameters @{ SignalsFile = $goodCache; OutFile = (Join-Path $lzRepo 'out.html'); Config = (Join-Path $work 'does-not-exist.json') } }
    finally { Pop-Location }
    Assert-True 'a missing -Config does not break an explicit-path run' ((-not $r.Threw) -and (Test-Path (Join-Path $lzRepo 'out.html'))) "$($r.Message)$($r.Output)"

    # The output_dir deprecation is surfaced by the queue/signals entry points too.
    $depCfg = Join-Path $work 'dep.json'
    @{ repo = 'acme/widgets'; output_dir = 'docs' } | ConvertTo-Json | Set-Content -Path $depCfg -Encoding utf8
    $depTax = @(Resolve-Taxonomy -Config (Get-Content $depCfg -Raw | ConvertFrom-Json) 3>&1)
    $depWarn = @($depTax | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { $_.Message })
    Assert-Match 'Resolve-Taxonomy surfaces the output_dir deprecation' "output_dir' is deprecated" ($depWarn -join ' ')

    Write-Host "`ntriage-bootstrap.ps1" -ForegroundColor Yellow
    Reset-GhStub
    $global:GhLabels = @('needs-triage')
    $r = Invoke-Skill -Script $script:BootstrapPath -Parameters @{ Repo = 'acme/widgets' }
    Assert-True 'creates the missing labels' (-not $r.Threw) $r.Message
    Assert-Equal 'creates exactly the missing ones' 'blocked,owner-decision,priority:P0,priority:P1,priority:P2,priority:P3' ($global:GhCreated -join ',')

    Reset-GhStub
    $global:GhLabels = $script:AllRequired
    $r = Invoke-Skill -Script $script:BootstrapPath -Parameters @{ Repo = 'acme/widgets' }
    Assert-Equal 'is idempotent: creates nothing when all labels exist' 0 $global:GhCreated.Count
    Assert-Match 'says the gate already passes' 'already passes' $r.Output

    Reset-GhStub
    $global:GhLabelListExit = 1
    $r = Invoke-Skill -Script $script:BootstrapPath -Parameters @{ Repo = 'acme/widgets' }
    Assert-True 'aborts when gh label list fails' $r.Threw "no throw: $($r.Output)"
    Assert-Match 'says the gate cannot run blind' 'cannot run blind' $r.Message
    Assert-Equal 'creates nothing after a failed label list' 0 $global:GhCreated.Count

    Reset-GhStub
    $r = Invoke-Skill -Script $script:BootstrapPath -Parameters @{ Repo = 'acme/widgets'; DryRun = $true }
    Assert-Equal 'creates nothing with -DryRun' 0 $global:GhCreated.Count
    Assert-Match 'previews the gh commands' '\[dry-run\]' $r.Output

    Reset-GhStub
    $global:GhCreateExit = 1
    $r = Invoke-Skill -Script $script:BootstrapPath -Parameters @{ Repo = 'acme/widgets' }
    Assert-True 'surfaces a failing gh label create' $r.Threw "no throw: $($r.Output)"
    Assert-Match 'names the failed label' 'gh label create failed' $r.Message

    Reset-GhStub
    $global:GhLabels = $script:AllRequired
    $example = Join-Path $work 'example.json'
    $r = Invoke-Skill -Script $script:BootstrapPath -Parameters @{ Repo = 'acme/widgets'; WriteExampleConfig = $example }
    Assert-True 'writes an example config even when nothing is missing' (Test-Path $example) $r.Output
    $written = Get-Content $example -Raw | ConvertFrom-Json
    Assert-Equal 'example config carries the repo' 'acme/widgets' $written.repo
    Assert-Equal 'example config carries the priority axis' 4 @($written.priority_levels).Count

    Reset-GhStub
    $dryExample = Join-Path $work 'dry-example.json'
    $r = Invoke-Skill -Script $script:BootstrapPath -Parameters @{ Repo = 'acme/widgets'; DryRun = $true; WriteExampleConfig = $dryExample }
    Assert-True 'writes no file with -DryRun' (-not (Test-Path $dryExample))
    Assert-Match 'prints the config instead' 'would write' $r.Output

    Reset-GhStub
    $config = Join-Path $work 'custom.json'
    Write-CustomConfig -Path $config
    $r = Invoke-Skill -Script $script:QueuePath -Parameters @{ Repo = 'acme/widgets'; Config = $config }
    Assert-True 'gate fails before the recovery' $r.Threw "no throw: $($r.Output)"
    $null = Invoke-Skill -Script $script:BootstrapPath -Parameters @{ Repo = 'acme/widgets'; Config = $config }
    Assert-Equal 'recovery creates the mapped labels' 'kind/blocked,kind/owner,sev/critical,sev/high,status/triage' ($global:GhCreated -join ',')
    $global:GhLabels = $global:GhCreated
    $r = Invoke-Skill -Script $script:QueuePath -Parameters @{ Repo = 'acme/widgets'; Config = $config }
    Assert-True 'the gate passes after the recovery' (-not $r.Threw) $r.Message
    Assert-Match 'the queue uses the mapped label' "carries 'status/triage'" $r.Output

    Write-Host "`ntaxonomy helpers" -ForegroundColor Yellow
    . $script:HelpersPath
    $tax = Resolve-Taxonomy
    $required = @(Get-TriageRequiredLabels -Taxonomy $tax | ForEach-Object { $_.name })
    # bootstrap sorts by name; the gate keeps taxonomy order - compare as sets.
    Assert-Equal 'bootstrap requires exactly the labels the gate checks' (($script:AllRequired | Sort-Object) -join ',') (($required | Sort-Object) -join ',')
    $checked = Resolve-Taxonomy -ExistingLabels @()
    Assert-Equal 'the gate checks exactly those labels' ($script:AllRequired -join ',') (@($checked.missing_labels) -join ',')

    $disabled = Resolve-Taxonomy -Config (@{ owner_decision = $null; blocked = ''; area_prefix = 'area:' } | ConvertTo-Json | ConvertFrom-Json)
    $disabledRequired = @(Get-TriageRequiredLabels -Taxonomy $disabled | ForEach-Object { $_.name })
    Assert-Equal 'disabled concepts drop out of the required set' 'needs-triage,priority:P0,priority:P1,priority:P2,priority:P3' ($disabledRequired -join ',')

    # `repo` and `output_dir` are caller-consumed keys: silently skipped by the
    # taxonomy merge; anything else unrecognized must still warn (typo safety).
    $cap = @(Merge-Taxonomy -Base (Get-DefaultTaxonomy) -Overlay ([pscustomobject]@{ repo = 'acme/widgets'; output_dir = '.github/triage-backlog' }) 3>&1)
    $mergeWarnings = @($cap | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    Assert-Equal 'repo/output_dir cause no unknown-key warning' 0 $mergeWarnings.Count
    $cap = @(Merge-Taxonomy -Base (Get-DefaultTaxonomy) -Overlay ([pscustomobject]@{ typo_key = 'x' }) 3>&1)
    $mergeWarnings = @($cap | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    Assert-Match 'a genuinely unknown key still warns' 'typo_key' (($mergeWarnings | ForEach-Object { $_.Message }) -join ' ')

    Write-Host "`nartifact location helpers" -ForegroundColor Yellow
    Assert-Equal 'canonical dir is <repo-root>/.github/triage-backlog' (Join-Path $work '.github\triage-backlog') (Get-TriageCanonicalOutputDir -RepoRoot $work)

    $dep = @(Get-TriageDeprecatedOutputDirs -RepoRoot $work -GitDir (Join-Path $work '.git') -ConfigOutputDir 'legacy-board')
    Assert-Equal 'lists every deprecated location' 5 $dep.Count
    Assert-True 'includes the previous git-dir default' ($dep -contains (Join-Path $work '.git\triage-backlog')) ($dep -join '; ')
    Assert-True 'includes the pre-rename git-dir default' ($dep -contains (Join-Path $work '.git\backlog-triage')) ($dep -join '; ')
    Assert-True 'includes the pre-rename .github opt-in' ($dep -contains (Join-Path $work '.github\backlog-triage')) ($dep -join '; ')
    Assert-True 'includes the legacy ./cache fallback' ($dep -contains (Join-Path $work 'cache')) ($dep -join '; ')
    Assert-True 'includes the deprecated config output_dir' ($dep -contains (Join-Path $work 'legacy-board')) ($dep -join '; ')
    $dedup = @(Get-TriageDeprecatedOutputDirs -RepoRoot $work -GitDir $null -ConfigOutputDir '.github/backlog-triage')
    Assert-Equal 'dedupes a config output_dir that repeats a known location' 2 $dedup.Count

    $initDir = Join-Path $work 'init-probe'
    $null = Initialize-TriageArtifactDir -Path $initDir
    $initIgnore = Join-Path $initDir '.gitignore'
    Assert-True 'creates the dir and its .gitignore' (Test-Path $initIgnore)
    Assert-Match 'the created .gitignore ignores everything' '(?m)^\*$' (Get-Content $initIgnore -Raw)
    Set-Content -Path $initIgnore -Value "# custom`n*`n!keep.txt"
    $custom = Get-Content $initIgnore -Raw
    $null = Initialize-TriageArtifactDir -Path $initDir
    Assert-Equal 'respects a custom .gitignore that already ignores' $custom (Get-Content $initIgnore -Raw)
    Set-Content -Path $initIgnore -Value 'not-ignoring'
    $null = Initialize-TriageArtifactDir -Path $initDir
    Assert-Match 're-enforces a .gitignore that stopped ignoring' '(?m)^\*$' (Get-Content $initIgnore -Raw)

    $whatIfSrc = Join-Path $work 'whatif-src'
    New-Item -ItemType Directory -Force -Path $whatIfSrc | Out-Null
    Set-Content -Path (Join-Path $whatIfSrc 'triage-report.html') -Value '<html/>'
    $whatIfDst = Join-Path $work 'whatif-dst'
    $dry = Invoke-TriageArtifactReconcile -CanonicalDir $whatIfDst -DeprecatedDirs @($whatIfSrc) -WhatIf
    Assert-Equal '-WhatIf reports the move' 1 @($dry.moved).Count
    Assert-True '-WhatIf moves nothing' (Test-Path (Join-Path $whatIfSrc 'triage-report.html'))
    Assert-True '-WhatIf creates no destination' (-not (Test-Path $whatIfDst))

    Reset-GhStub
    $global:GhLabels = @('a', 'b')
    Assert-Equal 'reads the repo labels from gh output' 'a,b' (@(Get-TriageRepoLabels -Repo 'acme/widgets') -join ',')
    $global:GhLabels = @()
    Assert-Equal 'a genuinely empty label set is not an error' 0 @(Get-TriageRepoLabels -Repo 'acme/widgets').Count
    $global:GhLabelListExit = 1
    $threw = $false
    $message = ''
    try { $null = Get-TriageRepoLabels -Repo 'acme/widgets' } catch { $threw = $true; $message = "$_" }
    Assert-True 'a failed gh label list throws' $threw 'no throw'
    Assert-Match 'the failure says the gate cannot run blind' 'cannot run blind' $message
}
finally {
    Remove-Item Function:\global:gh -ErrorAction SilentlyContinue
    Pop-Location
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}

Write-Host "`n=== Results: $pass passed, $fail failed ===" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
