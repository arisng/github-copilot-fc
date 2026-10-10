<#
.SYNOPSIS
    Offline tests for the backlog-triage scripts (taxonomy gate, bootstrap, report).

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

    Write-Host "`n=== backlog-triage tests ===" -ForegroundColor Cyan

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
