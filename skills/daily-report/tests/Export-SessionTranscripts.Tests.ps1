Describe 'Export-SessionTranscripts.ps1' {
    BeforeAll {
        $scriptDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts'
        $export = Join-Path $scriptDir 'Export-SessionTranscripts.ps1'

        # Hermetic Copilot home: one events-backed session, one db-backed session.
        $fxHome = Join-Path $TestDrive 'copilot-home'
        $stateDir = Join-Path $fxHome 'session-state'
        New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
        $evFull = 'aaaabbbb-1111-4222-8333-444444444444'
        $dbFull = 'ccccdddd-0000-4000-8000-000000000001'
        $evDir = Join-Path $stateDir $evFull
        New-Item -ItemType Directory -Force -Path $evDir | Out-Null
        $events = @'
{"type":"user.message","timestamp":"2026-11-17T08:00:00Z","data":{"interactionId":"i1","content":"Fixture question","source":"user"}}
{"type":"assistant.message","timestamp":"2026-11-17T08:00:05Z","data":{"interactionId":"i1","messageId":"m1","turnId":"t1","content":"Fixture answer"}}
'@
        Set-Content -Path (Join-Path $evDir 'events.jsonl') -Value $events -Encoding utf8
        $db = Join-Path $fxHome 'session-store.db'
        sqlite3 $db @'
CREATE TABLE sessions (id TEXT, summary TEXT, cwd TEXT, repository TEXT, branch TEXT, created_at TEXT);
CREATE TABLE turns (session_id TEXT, turn_index INT, user_message TEXT, assistant_response TEXT, timestamp TEXT);
INSERT INTO sessions VALUES ('ccccdddd-0000-4000-8000-000000000001','fixture db session','/fixture','o/r','main','2026-11-17T08:00:00');
INSERT INTO turns VALUES ('ccccdddd-0000-4000-8000-000000000001',0,'DB question','DB answer','2026-11-17T08:00:00');
'@
        if ($LASTEXITCODE -ne 0) { throw 'fixture db creation failed' }

        function New-Report([string]$RefsLine) {
            $dir = Join-Path $TestDrive "repo/reports/daily/alice"
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            $path = Join-Path $dir '261117.md'
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
        # Template link form: 8-char display label, full-UUID target.
        # A report may still carry an old link; it is not a citation form.
        $refsLinks = "- **Refs:** [$($evFull.Substring(0,8))](sessions/261117/$evFull.html) · [$($dbFull.Substring(0,8))](sessions/261117/$dbFull.html)"

        function Get-SessDir([string]$Report) { Join-Path (Split-Path $Report -Parent) 'sessions/261117' }
    }

    BeforeEach {
        $sessionsDir = Join-Path $TestDrive 'repo/reports/daily/alice/sessions'
        if (Test-Path $sessionsDir) { Remove-Item $sessionsDir -Recurse -Force }
    }

    It 'ListOnly lists every cited copilot session and never grill sessions' {
        $r = New-Report $refsAll
        $ids = @(& $export -ReportPath $r -ListOnly)
        $LASTEXITCODE | Should -Be 0
        $ids | Should -Be @('aaaabbbb', 'ccccdddd', 'eeeeffff')
        Test-Path (Join-Path (Split-Path $r -Parent) 'sessions') | Should -BeFalse
    }

    It 'ListOnly reads the link form and yields the full-UUID target stem' {
        $r = New-Report $refsLinks
        $ids = @(& $export -ReportPath $r -ListOnly)
        $LASTEXITCODE | Should -Be 0
        $ids | Should -Be @($evFull, $dbFull)
    }

    It 'ListOnly collapses a session cited in both forms to its full UUID' {
        $r = New-Report "- **Refs:** session ``aaaabbbb`` · [$($evFull.Substring(0,8))](sessions/261117/$evFull.html)"
        $ids = @(& $export -ReportPath $r -ListOnly)
        $LASTEXITCODE | Should -Be 0
        $ids | Should -Be @($evFull)
    }

    It 'ListOnly works without any copilot home (pure parse, no store access)' {
        $r = New-Report '- **Refs:** session `deadbeef`'
        $ids = @(& $export -ReportPath $r -ListOnly -CopilotHome (Join-Path $TestDrive 'nowhere'))
        $ids | Should -Be @('deadbeef')
    }

    It 'exports under the full UUID and notices the unresolvable short citation' {
        $r = New-Report $refsAll
        $j = (& $export -ReportPath $r -CopilotHome $fxHome | Out-String) | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $j.total | Should -Be 3
        @($j.exported).Count | Should -Be 2
        @($j.notice).Count | Should -Be 1
        # the slug is the full UUID even though the report cites the short form
        @($j.exported | ForEach-Object { $_.slug }) | Should -Be @($evFull, $dbFull)
        $sessionsDir = Get-SessDir $r
        (Get-Content (Join-Path $sessionsDir "$evFull.html") -Raw) | Should -Match 'Fixture question'
        (Get-Content (Join-Path $sessionsDir "$dbFull.html") -Raw) | Should -Match 'DB answer'
        Test-Path (Join-Path $sessionsDir 'aaaabbbb.html') | Should -BeFalse
        Test-Path (Join-Path $sessionsDir 'ccccdddd.html') | Should -BeFalse
        $notice = Get-Content (Join-Path $sessionsDir 'eeeeffff.html') -Raw
        $notice | Should -Match 'daily-report-session-notice'
        $notice | Should -Match 'not available on this machine'
    }

    It 'rerun keeps existing files instead of rewriting them' {
        $r = New-Report $refsAll
        & $export -ReportPath $r -CopilotHome $fxHome | Out-Null
        $j = (& $export -ReportPath $r -CopilotHome $fxHome | Out-String) | ConvertFrom-Json
        $j.kept.Count | Should -Be 3
        @($j.exported).Count | Should -Be 0
        @($j.notice).Count | Should -Be 0
    }

    It 'prunes a stale short-form file once the session exports under its full UUID' {
        $r = New-Report $refsAll
        $sessionsDir = Get-SessDir $r
        New-Item -ItemType Directory -Force -Path $sessionsDir | Out-Null
        [IO.File]::WriteAllText((Join-Path $sessionsDir 'aaaabbbb.html'), '<!doctype html><html><body>old short export</body></html>')
        $j = (& $export -ReportPath $r -CopilotHome $fxHome | Out-String) | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        Test-Path (Join-Path $sessionsDir 'aaaabbbb.html') | Should -BeFalse
        Test-Path (Join-Path $sessionsDir "$evFull.html") | Should -BeTrue
        @($j.pruned).Count | Should -Be 1
        $j.pruned[0].id | Should -Be 'aaaabbbb'
        $j.pruned[0].slug | Should -Be $evFull
    }

    It 'upgrades a notice to the real transcript once the session data exists' {
        $r = New-Report '- **Refs:** session `eeeeffff`'
        & $export -ReportPath $r -CopilotHome $fxHome | Out-Null   # notice: unresolvable
        $full = Join-Path $stateDir 'eeeeffff-9999-4222-8333-444444444444'
        New-Item -ItemType Directory -Force -Path $full | Out-Null
        Set-Content -Path (Join-Path $full 'events.jsonl') -Value $events -Encoding utf8
        try {
            $j = (& $export -ReportPath $r -CopilotHome $fxHome | Out-String) | ConvertFrom-Json
            @($j.exported).Count | Should -Be 1
            $j.exported[0].slug | Should -Be 'eeeeffff-9999-4222-8333-444444444444'
            # the short-form notice is pruned by the upgrade
            Test-Path (Join-Path (Get-SessDir $r) 'eeeeffff.html') | Should -BeFalse
        }
        finally { Remove-Item $full -Recurse -Force }
    }

    It 'fails loudly on an ambiguous 8-char prefix and writes nothing' {
        foreach ($n in @('abc12345-1111-4222-8333-444444444444', 'abc12345-5555-4222-8333-444444444444')) {
            New-Item -ItemType Directory -Force -Path (Join-Path $stateDir $n) | Out-Null
        }
        try {
            $r = New-Report '- **Refs:** session `abc12345`'
            { & $export -ReportPath $r -CopilotHome $fxHome } | Should -Throw -ExpectedMessage '*ambiguous*'
            Test-Path (Join-Path (Split-Path $r -Parent) 'sessions') | Should -BeFalse
        }
        finally {
            foreach ($n in @('abc12345-1111-4222-8333-444444444444', 'abc12345-5555-4222-8333-444444444444')) {
                Remove-Item (Join-Path $stateDir $n) -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'exports a link-form citation straight to its full-UUID slug' {
        $r = New-Report $refsLinks
        $j = (& $export -ReportPath $r -CopilotHome $fxHome | Out-String) | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $j.total | Should -Be 2
        @($j.exported | ForEach-Object { $_.slug }) | Should -Be @($evFull, $dbFull)
        $sessionsDir = Get-SessDir $r
        (Get-Content (Join-Path $sessionsDir "$evFull.html") -Raw) | Should -Match 'Fixture question'
        @(Get-ChildItem $sessionsDir -Filter '*.html' -File).Count | Should -Be 2
    }

    It 'rejects a link whose target is not the full session UUID' {
        $r = New-Report '- **Refs:** [aaaabbbb](sessions/261117/aaaabbbb.html)'
        { & $export -ReportPath $r -CopilotHome $fxHome } | Should -Throw -ExpectedMessage '*full session UUID*'
        Test-Path (Join-Path (Split-Path $r -Parent) 'sessions') | Should -BeFalse
    }

    It 'rejects a link pointing outside the report date folder' {
        $r = New-Report "- **Refs:** [$($evFull.Substring(0,8))](sessions/261118/$evFull.html)"
        { & $export -ReportPath $r -CopilotHome $fxHome } | Should -Throw -ExpectedMessage '*beside its report*'
    }

    It 'exports a coverage-receipt session the report never cites' {
        $r = New-Report '- **Refs:** check `task test` → PASS'
        $cov = Join-Path $TestDrive 'cov.json'
        '{"schema":1,"date":"2026-11-17","verified":true,"missed":[],"inScopeIds":["ccccdddd-0000-4000-8000-000000000001"]}' | Set-Content $cov
        $j = (& $export -ReportPath $r -CopilotHome $fxHome -CoverageJson $cov | Out-String) | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $j.total | Should -Be 1
        (Get-Content (Join-Path (Get-SessDir $r) "$dbFull.html") -Raw) | Should -Match 'DB answer'
    }

    It 'keeps one artifact when a receipt repeats a cited session by short id' {
        $r = New-Report '- **Refs:** session `ccccdddd`'
        $cov = Join-Path $TestDrive 'cov.json'
        '{"schema":1,"date":"2026-11-17","verified":true,"missed":[],"inScopeIds":["ccccdddd-0000-4000-8000-000000000001"]}' | Set-Content $cov
        $j = (& $export -ReportPath $r -CopilotHome $fxHome -CoverageJson $cov | Out-String) | ConvertFrom-Json
        $j.total | Should -Be 1
        $sessionsDir = Get-SessDir $r
        Test-Path (Join-Path $sessionsDir "$dbFull.html") | Should -BeTrue
        Test-Path (Join-Path $sessionsDir 'ccccdddd.html') | Should -BeFalse
        @(Get-ChildItem $sessionsDir -Filter '*.html' -File).Count | Should -Be 1
    }

    It 'sweeps an orphan short-form file whose full-UUID peer exists' {
        $r = New-Report '- **Refs:** check `task test` → PASS'
        $sessionsDir = Get-SessDir $r
        New-Item -ItemType Directory -Force -Path $sessionsDir | Out-Null
        [IO.File]::WriteAllText((Join-Path $sessionsDir 'feedface.html'), '<html>old short</html>')
        [IO.File]::WriteAllText((Join-Path $sessionsDir 'feedface-2222-4222-8333-444444444444.html'), '<html>full</html>')
        $j = (& $export -ReportPath $r -CopilotHome $fxHome | Out-String) | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $j.total | Should -Be 0
        @($j.pruned).Count | Should -Be 1
        Test-Path (Join-Path $sessionsDir 'feedface.html') | Should -BeFalse
        Test-Path (Join-Path $sessionsDir 'feedface-2222-4222-8333-444444444444.html') | Should -BeTrue
    }

    It 'never sweeps a short file whose prefix is ambiguous' {
        $r = New-Report '- **Refs:** check `task test` → PASS'
        $sessionsDir = Get-SessDir $r
        New-Item -ItemType Directory -Force -Path $sessionsDir | Out-Null
        [IO.File]::WriteAllText((Join-Path $sessionsDir 'feedface.html'), '<html>short</html>')
        [IO.File]::WriteAllText((Join-Path $sessionsDir 'feedface-2222-4222-8333-444444444444.html'), '<html>a</html>')
        [IO.File]::WriteAllText((Join-Path $sessionsDir 'feedface-3333-4222-8333-444444444444.html'), '<html>b</html>')
        $j = (& $export -ReportPath $r -CopilotHome $fxHome | Out-String) | ConvertFrom-Json
        @($j.pruned).Count | Should -Be 0
        @(Get-ChildItem $sessionsDir -Filter '*.html' -File).Count | Should -Be 3
    }

    It 'fails loudly when the coverage receipt is missing' {
        $r = New-Report '- **Refs:** check `task test` → PASS'
        { & $export -ReportPath $r -CopilotHome $fxHome -CoverageJson (Join-Path $TestDrive 'ghost-coverage.json') } | Should -Throw -ExpectedMessage '*coverage receipt not found*'
    }

    It 'fails loudly when the report is not named yymmdd.md' {
        $dir = Join-Path $TestDrive 'repo/reports/daily/alice'
        $bad = Join-Path $dir 'weekly.md'
        Set-Content $bad 'report content'
        { & $export -ReportPath $bad -CopilotHome $fxHome } | Should -Throw -ExpectedMessage '*yymmdd.md*'
        Test-Path (Join-Path $dir 'sessions') | Should -BeFalse
    }

    It 'emits a zero-total receipt and creates no folder when nothing is cited' {
        $r = New-Report '- **Refs:** check `task test` → PASS'
        $j = (& $export -ReportPath $r -CopilotHome $fxHome | Out-String) | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $j.total | Should -Be 0
        @($j.pruned).Count | Should -Be 0
        Test-Path (Join-Path (Split-Path $r -Parent) 'sessions') | Should -BeFalse
    }

    It 'fails loudly when the report does not exist' {
        { & $export -ReportPath (Join-Path $TestDrive 'ghost.md') } | Should -Throw -ExpectedMessage '*report not found*'
    }
}
