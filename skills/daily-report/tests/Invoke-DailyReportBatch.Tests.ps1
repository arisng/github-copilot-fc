Describe 'Invoke-DailyReportBatch.ps1' {
    BeforeAll {
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
Add-Content -Path (Join-Path $env:TEMP 'batch-calls.log') -Value "proof:$Date"
if ($Date -eq '2026-11-02') { Write-Error 'boom'; exit 1 }
'{"commits":[],"commitCount":0}'
'@
        Set-Content (Join-Path $stub 'Get-SessionEvidence.ps1') @'
param([string]$Date, [string]$Start, [string]$End, [string]$RepoRoot, [string]$SessionDbPath, [string]$CloudJson, [int]$UtcOffsetHours)
Add-Content -Path (Join-Path $env:TEMP 'batch-calls.log') -Value "sessions:$Date"
'{"sessions":[],"sessionCount":0}'
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
        $j.days[0].status | Should -Be 'evidence-ready'
        $j.days[1].status | Should -Be 'failed'
        $j.days[2].status | Should -Be 'evidence-ready'
        $j.failed | Should -Be 1
    }

    It 'skips days whose report exists unless -Regenerate' {
        $reportDir = Join-Path $repo 'reports/daily/alice'
        New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
        Set-Content (Join-Path $reportDir '261101.md') 'existing'
        $out = & $batch -StartDate '2026-11-01' -EndDate '2026-11-01' -RepoRoot $repo -GitUser 'alice' -ScriptsDir $stub | Out-String
        ($out | ConvertFrom-Json).days[0].status | Should -Be 'skipped'
        $out2 = & $batch -StartDate '2026-11-01' -EndDate '2026-11-01' -RepoRoot $repo -GitUser 'alice' -ScriptsDir $stub -Regenerate | Out-String
        ($out2 | ConvertFrom-Json).days[0].status | Should -Be 'evidence-ready'
    }

    It 'rejects an inverted range and a range wider than 31 days' {
        { & $batch -StartDate '2026-11-05' -EndDate '2026-11-01' -RepoRoot $repo -GitUser 'alice' -ScriptsDir $stub } | Should -Throw
        { & $batch -StartDate '2026-01-01' -EndDate '2026-11-01' -RepoRoot $repo -GitUser 'alice' -ScriptsDir $stub } | Should -Throw
    }
}
