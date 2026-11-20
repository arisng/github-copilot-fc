Describe 'Export-SessionTranscripts.ps1' {
    BeforeAll {
        $scriptDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts'
        $export = Join-Path $scriptDir 'Export-SessionTranscripts.ps1'

        # Hermetic Copilot home: one events-backed session, one db-backed session.
        $fxHome = Join-Path $TestDrive 'copilot-home'
        $stateDir = Join-Path $fxHome 'session-state'
        New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
        $evDir = Join-Path $stateDir 'aaaabbbb-1111-4222-8333-444444444444'
        New-Item -ItemType Directory -Force -Path $evDir | Out-Null
        $events = @'
{"type":"user.message","timestamp":"2026-11-17T08:00:00Z","data":{"interactionId":"i1","content":"Fixture question","source":"user"}}
{"type":"assistant.message","timestamp":"2026-11-17T08:00:05Z","data":{"interactionId":"i1","messageId":"m1","turnId":"t1","content":"Fixture answer"}}
'@
        Set-Content -Path (Join-Path $evDir 'events.jsonl') -Value $events -Encoding utf8
        $db = Join-Path $fxHome 'session-store.db'
        sqlite3.exe $db @'
CREATE TABLE sessions (id TEXT, summary TEXT, cwd TEXT, repository TEXT, branch TEXT, created_at TEXT);
CREATE TABLE turns (session_id TEXT, turn_index INT, user_message TEXT, assistant_response TEXT, timestamp TEXT);
INSERT INTO sessions VALUES ('ccccdddd-0000-4000-8000-000000000001','fixture db session','C:/fixture','o/r','main','2026-11-17T08:00:00');
INSERT INTO turns VALUES ('ccccdddd-0000-4000-8000-000000000001',0,'DB question','DB answer','2026-11-17T08:00:00');
'@
        if ($LASTEXITCODE -ne 0) { throw 'fixture db creation failed' }

        function New-Report([string]$Name, [string]$RefsLine) {
            $dir = Join-Path $TestDrive "repo/reports/daily/alice"
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            $path = Join-Path $dir $Name
            @'
---
created: 2026-11-17 16:00 +07:00
updated: 2026-11-17 16:00 +07:00
---

# Daily Report

'@ + $RefsLine + "`n" | Set-Content $path -Encoding utf8
            return $path
        }

        $refsAll = '- **Refs:** session `aaaabbbb` · session `ccccdddd` · session `eeeeffff` · grill session `20261105-120133`'
    }

    BeforeEach {
        $sessionsDir = Join-Path $TestDrive 'repo/reports/daily/alice/sessions'
        if (Test-Path $sessionsDir) { Remove-Item $sessionsDir -Recurse -Force }
    }

    It 'ListOnly lists every mentioned copilot session and never grill sessions' {
        $r = New-Report 'list.md' $refsAll
        $ids = @(& $export -ReportPath $r -ListOnly)
        $LASTEXITCODE | Should -Be 0
        $ids | Should -Be @('aaaabbbb', 'ccccdddd', 'eeeeffff')
        Test-Path (Join-Path (Split-Path $r -Parent) 'sessions') | Should -BeFalse
    }

    It 'ListOnly works without any copilot home (pure parse, no store access)' {
        $r = New-Report 'list2.md' '- **Refs:** session `deadbeef`'
        $ids = @(& $export -ReportPath $r -ListOnly -CopilotHome (Join-Path $TestDrive 'nowhere'))
        $ids | Should -Be @('deadbeef')
    }

    It 'exports events- and db-backed sessions and notices the unresolvable one' {
        $r = New-Report 'full.md' $refsAll
        $j = (& $export -ReportPath $r -CopilotHome $fxHome | Out-String) | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $j.total | Should -Be 3
        @($j.exported).Count | Should -Be 2
        @($j.notice).Count | Should -Be 1
        $sessionsDir = Join-Path (Split-Path $r -Parent) 'sessions'
        (Get-Content (Join-Path $sessionsDir 'aaaabbbb.html') -Raw) | Should -Match 'Fixture question'
        (Get-Content (Join-Path $sessionsDir 'ccccdddd.html') -Raw) | Should -Match 'DB answer'
        $notice = Get-Content (Join-Path $sessionsDir 'eeeeffff.html') -Raw
        $notice | Should -Match 'daily-report-session-notice'
        $notice | Should -Match 'not available on this machine'
    }

    It 'rerun keeps existing files instead of rewriting them' {
        $r = New-Report 'keep.md' $refsAll
        & $export -ReportPath $r -CopilotHome $fxHome | Out-Null
        $j = (& $export -ReportPath $r -CopilotHome $fxHome | Out-String) | ConvertFrom-Json
        $j.kept.Count | Should -Be 3
        @($j.exported).Count | Should -Be 0
        @($j.notice).Count | Should -Be 0
    }

    It 'upgrades a notice to the real transcript once the session data exists' {
        $r = New-Report 'upgrade.md' '- **Refs:** session `eeeeffff`'
        & $export -ReportPath $r -CopilotHome $fxHome | Out-Null   # notice: unresolvable
        $full = Join-Path $stateDir 'eeeeffff-9999-4222-8333-444444444444'
        New-Item -ItemType Directory -Force -Path $full | Out-Null
        Set-Content -Path (Join-Path $full 'events.jsonl') -Value $events -Encoding utf8
        try {
            $j = (& $export -ReportPath $r -CopilotHome $fxHome | Out-String) | ConvertFrom-Json
            @($j.exported).Count | Should -Be 1
            $j.exported[0].id | Should -Be 'eeeeffff'
        }
        finally { Remove-Item $full -Recurse -Force }
    }

    It 'fails loudly on an ambiguous 8-char prefix and writes nothing' {
        foreach ($n in @('abc12345-1111-4222-8333-444444444444', 'abc12345-5555-4222-8333-444444444444')) {
            New-Item -ItemType Directory -Force -Path (Join-Path $stateDir $n) | Out-Null
        }
        try {
            $r = New-Report 'ambig.md' '- **Refs:** session `abc12345`'
            { & $export -ReportPath $r -CopilotHome $fxHome } | Should -Throw -ExpectedMessage '*ambiguous*'
            Test-Path (Join-Path (Split-Path $r -Parent) 'sessions') | Should -BeFalse
        }
        finally {
            foreach ($n in @('abc12345-1111-4222-8333-444444444444', 'abc12345-5555-4222-8333-444444444444')) {
                Remove-Item (Join-Path $stateDir $n) -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'emits a zero-total receipt and creates no folder when nothing is mentioned' {
        $r = New-Report 'none.md' '- **Refs:** check `task test` → PASS'
        $j = (& $export -ReportPath $r -CopilotHome $fxHome | Out-String) | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $j.total | Should -Be 0
        Test-Path (Join-Path (Split-Path $r -Parent) 'sessions') | Should -BeFalse
    }

    It 'fails loudly when the report does not exist' {
        { & $export -ReportPath (Join-Path $TestDrive 'ghost.md') } | Should -Throw -ExpectedMessage '*report not found*'
    }
}
