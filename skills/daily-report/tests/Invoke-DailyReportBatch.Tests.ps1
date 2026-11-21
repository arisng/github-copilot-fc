Describe 'Invoke-DailyReportBatch.ps1' {
    BeforeAll {
        # Linux has no TEMP env var (Windows-only); the stubs and assertions
        # below log through it, so point it at the platform temp dir when unset.
        if (-not $env:TEMP) { $env:TEMP = [System.IO.Path]::GetTempPath() }
        $batch = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts') 'Invoke-DailyReportBatch.ps1'
        $repo = Join-Path $TestDrive 'repo'
        New-Item -ItemType Directory -Force -Path $repo | Out-Null
        git -C $repo init -q
        git -C $repo config user.name 'alice'
        git -C $repo config user.email 'alice@example.com'

        # Stub scripts directory: records calls; fails on the second day.
        $stub = Join-Path $TestDrive 'stub'
        New-Item -ItemType Directory -Force -Path $stub | Out-Null
        Set-Content (Join-Path $stub 'Get-GitProof.ps1') @'
param([string]$Date, [string]$Start, [string]$End, [string]$Author, [string]$RepoRoot)
Add-Content -Path (Join-Path $env:TEMP 'batch-calls.log') -Value "proof:${RepoRoot}:$Date"
if ($Date -eq '2026-11-02') { Write-Error 'boom'; exit 1 }
'{"commits":[],"commitCount":0}'
'@
        Set-Content (Join-Path $stub 'Get-SessionEvidence.ps1') @'
param([string]$Date, [string]$Start, [string]$End, [string]$RepoRoot, [string]$SessionDbPath, [string]$CloudJson, [int]$UtcOffsetHours)
Add-Content -Path (Join-Path $env:TEMP 'batch-calls.log') -Value "sessions:${RepoRoot}:$Date"
if ($Date -eq '2026-11-06') { Write-Error 'repo scope: cannot resolve owner/name from remote. Refusing an unfiltered query.'; exit 1 }
'{"sessions":[],"sessionCount":0}'
'@
        Set-Content (Join-Path $stub 'Get-ReportManifest.ps1') @'
param([string]$RepoRoot, [switch]$Optional)
if ($env:BATCH_STUB_MANIFEST_MODE -eq 'multi') {
    $watched = $env:BATCH_STUB_WATCHED
    $exists = [bool](Test-Path -LiteralPath $watched)
    $repos = @(
        [ordered]@{ path = $RepoRoot; name = 'tower/tower'; exists = $true; isHomeRepo = $true },
        [ordered]@{ path = $watched; name = 'watched/repo'; exists = $exists; isHomeRepo = $false }
    )
    [ordered]@{ present = $true; manifestPath = 'stub'; mode = 'multi'; homeRepoRoot = $RepoRoot; repos = $repos } | ConvertTo-Json -Depth 5
    exit 0
}
[ordered]@{ present = $false; manifestPath = 'stub'; mode = 'single'; homeRepoRoot = $RepoRoot; repos = @() } | ConvertTo-Json -Depth 5
'@
        Set-Content (Join-Path $stub 'Test-DailyReport.ps1') @'
param([string]$ReportPath, [string]$RepoRoot, [string]$GitUser, [string]$Date, [string]$GlossaryPath, [string]$EvidenceJson)
exit 0
'@
    }

    BeforeEach { Remove-Item (Join-Path $env:TEMP 'batch-calls.log') -ErrorAction SilentlyContinue }

    It 'loops one day per iteration and isolates a failing day' {
        $out = & $batch -StartDate '2026-11-01' -EndDate '2026-11-03' -RepoRoot $repo -GitUser 'alice' -ScriptsDir $stub | Out-String
        $j = $out | ConvertFrom-Json
        @($j.days).Count | Should -Be 3
        $j.days[0].status | Should -Be 'evidence-ready' -Because "detail: $($j.days[0].detail)"
        $j.days[1].status | Should -Be 'failed'
        $j.days[2].status | Should -Be 'evidence-ready' -Because "detail: $($j.days[2].detail)"
        $j.failed | Should -Be 1
    }

    It 'records a session-evidence refusal as a grounding gap, not a day failure' {
        $out = & $batch -StartDate '2026-11-06' -EndDate '2026-11-06' -RepoRoot $repo -GitUser 'alice' -ScriptsDir $stub | Out-String
        $j = $out | ConvertFrom-Json
        $j.days[0].status | Should -Be 'evidence-ready'
        @($j.days[0].gaps).Count | Should -Be 1
        $j.days[0].gaps[0] | Should -Match 'session evidence gap'
        $j.days[0].gaps[0] | Should -Match 'Refusing an unfiltered query'
        $j.failed | Should -Be 0
        $j.gapped | Should -Be 1
        $LASTEXITCODE | Should -Be 0
        # git proof still collected for the gapped repo
        $log = Get-Content (Join-Path $env:TEMP 'batch-calls.log') -Raw
        $log | Should -Match 'proof:.*2026-11-06'
    }

    It 'skips days whose report exists unless -Regenerate' {
        $reportDir = Join-Path $repo 'reports/daily/alice'
        New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
        Set-Content (Join-Path $reportDir '261101.md') 'existing'
        $out = & $batch -StartDate '2026-11-01' -EndDate '2026-11-01' -RepoRoot $repo -GitUser 'alice' -ScriptsDir $stub | Out-String
        ($out | ConvertFrom-Json).days[0].status | Should -Be 'skipped'
        $out2 = & $batch -StartDate '2026-11-01' -EndDate '2026-11-01' -RepoRoot $repo -GitUser 'alice' -ScriptsDir $stub -Regenerate | Out-String
        $d2 = ($out2 | ConvertFrom-Json).days[0]
        $d2.status | Should -Be 'evidence-ready' -Because "detail: $($d2.detail)"
    }

    It 'rejects an inverted range and a range wider than 31 days' {
        { & $batch -StartDate '2026-11-05' -EndDate '2026-11-01' -RepoRoot $repo -GitUser 'alice' -ScriptsDir $stub } | Should -Throw
        { & $batch -StartDate '2026-01-01' -EndDate '2026-11-01' -RepoRoot $repo -GitUser 'alice' -ScriptsDir $stub } | Should -Throw
    }

    It 'collects evidence for every existing watched repo in multi mode' {
        $watched = Join-Path $TestDrive 'watched-batch'
        New-Item -ItemType Directory -Force -Path $watched | Out-Null
        git -C $watched init -q
        # Hermetic fixture: CI runners have no global git identity, and the
        # batch resolves -Author per repo via `git config user.email`.
        git -C $watched config user.name 'alice'
        git -C $watched config user.email 'alice@example.com'
        $env:BATCH_STUB_MANIFEST_MODE = 'multi'
        $env:BATCH_STUB_WATCHED = $watched
        try {
            $out = & $batch -StartDate '2026-11-04' -EndDate '2026-11-04' -RepoRoot $repo -GitUser 'alice' -ScriptsDir $stub | Out-String
        }
        finally {
            Remove-Item Env:BATCH_STUB_MANIFEST_MODE -ErrorAction SilentlyContinue
            Remove-Item Env:BATCH_STUB_WATCHED -ErrorAction SilentlyContinue
        }
        $days = ($out | ConvertFrom-Json).days
        $days[0].status | Should -Be 'evidence-ready' -Because "detail: $($days[0].detail)"
        $log = Get-Content (Join-Path $env:TEMP 'batch-calls.log') -Raw
        $log | Should -Match ([regex]::Escape($repo))
        $log | Should -Match ([regex]::Escape($watched))
    }

    It 'skips a watched repo missing on this machine in multi mode' {
        $missing = Join-Path $TestDrive 'watched-missing'
        $env:BATCH_STUB_MANIFEST_MODE = 'multi'
        $env:BATCH_STUB_WATCHED = $missing
        try {
            $out = & $batch -StartDate '2026-11-05' -EndDate '2026-11-05' -RepoRoot $repo -GitUser 'alice' -ScriptsDir $stub | Out-String
        }
        finally {
            Remove-Item Env:BATCH_STUB_MANIFEST_MODE -ErrorAction SilentlyContinue
            Remove-Item Env:BATCH_STUB_WATCHED -ErrorAction SilentlyContinue
        }
        $days = ($out | ConvertFrom-Json).days
        $days[0].status | Should -Be 'evidence-ready' -Because "detail: $($days[0].detail)"
        $log = Get-Content (Join-Path $env:TEMP 'batch-calls.log') -Raw
        $log | Should -Match ([regex]::Escape($repo))
        $log | Should -Not -Match 'watched-missing'
    }
}
