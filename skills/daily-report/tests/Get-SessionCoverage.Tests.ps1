Describe 'Get-SessionCoverage.ps1' {
    BeforeAll {
        $scriptDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts'
        $coverage = Join-Path $scriptDir 'Get-SessionCoverage.ps1'

        $tower = Join-Path $TestDrive 'tower'
        New-Item -ItemType Directory -Force -Path $tower | Out-Null
        git -C $tower init -q
        git -C $tower remote add origin 'https://github.com/o/r.git'

        $db = Join-Path $TestDrive 'store.db'
        $sub = Join-Path $tower 'deep'
        sqlite3.exe $db @"
CREATE TABLE sessions (id TEXT, cwd TEXT, repository TEXT, summary TEXT, created_at TEXT, updated_at TEXT);
CREATE TABLE turns (session_id TEXT, turn_index INT, user_message, assistant_response TEXT, timestamp TEXT);
INSERT INTO sessions VALUES ('k1', 'C:/elsewhere', 'o/r', 'key matched', '2026-11-10', '2026-11-10');
INSERT INTO sessions VALUES ('c1', '$sub', NULL, 'cwd matched, repo never recorded', '2026-11-10', '2026-11-10');
INSERT INTO sessions VALUES ('x1', 'C:/elsewhere2', 'x/y', 'different checkout', '2026-11-10', '2026-11-10');
INSERT INTO sessions VALUES ('u1', NULL, NULL, 'nothing to attribute', '2026-11-10', '2026-11-10');
INSERT INTO turns VALUES ('k1', 0, 'q', 'a', '2026-11-10T02:00:00');
INSERT INTO turns VALUES ('c1', 0, 'q', 'a', '2026-11-10T03:00:00');
INSERT INTO turns VALUES ('x1', 0, 'q', 'a', '2026-11-10T04:00:00');
INSERT INTO turns VALUES ('u1', 0, 'q', 'a', '2026-11-10T05:00:00');
"@
        if ($LASTEXITCODE -ne 0) { throw 'fixture db creation failed' }

        $fullK1 = 'aaaaaaaa-1111-4222-8333-444444444444'
        $fullC1 = 'bbbbbbbb-1111-4222-8333-444444444444'
        $fullX1 = 'cccccccc-1111-4222-8333-444444444444'
        $fullU1 = 'dddddddd-1111-4222-8333-444444444444'
        # Re-key the fixture rows to full uuids the receipt carries verbatim.
        sqlite3.exe $db @"
UPDATE sessions SET id = '$fullK1' WHERE id = 'k1';
UPDATE sessions SET id = '$fullC1' WHERE id = 'c1';
UPDATE sessions SET id = '$fullX1' WHERE id = 'x1';
UPDATE sessions SET id = '$fullU1' WHERE id = 'u1';
UPDATE turns SET session_id = '$fullK1' WHERE session_id = 'k1';
UPDATE turns SET session_id = '$fullC1' WHERE session_id = 'c1';
UPDATE turns SET session_id = '$fullX1' WHERE session_id = 'x1';
UPDATE turns SET session_id = '$fullU1' WHERE session_id = 'u1';
"@ | Out-Null

        # Evidence file covering both in-scope sessions.
        $evAll = Join-Path $TestDrive 'ev-all.json'
        [IO.File]::WriteAllText($evAll, (@{ sessions = @(
            @{ id = $fullK1 }, @{ id = $fullC1 }) } | ConvertTo-Json -Depth 4))
        $evPartial = Join-Path $TestDrive 'ev-partial.json'
        [IO.File]::WriteAllText($evPartial, (@{ sessions = @(
            @{ id = $fullK1 }) } | ConvertTo-Json -Depth 4))
    }

    It 'classifies every store session: in-scope by key and cwd, out of scope, unattributed' {
        $out = & $coverage -Date '2026-11-10' -RepoRoot $tower -SessionDbPath $db | Out-String
        $LASTEXITCODE | Should -Be 0
        $j = $out | ConvertFrom-Json
        $j.schema | Should -Be 1
        $j.storeSessions | Should -Be 4
        $j.inScope | Should -Be 2
        @($j.inScopeIds) | Should -Contain $fullK1
        @($j.inScopeIds) | Should -Contain $fullC1
        @($j.outOfScope).Count | Should -Be 1
        $j.outOfScope[0].repository | Should -Be 'x/y'
        @($j.unattributed).Count | Should -Be 1
        $j.verified | Should -BeFalse
        $j.complete | Should -BeFalse
    }

    It 'verifies against evidence files: verified with no misses' {
        $out = & $coverage -Date '2026-11-10' -RepoRoot $tower -SessionDbPath $db -EvidenceJson $evAll | Out-String
        $j = $out | ConvertFrom-Json
        $j.verified | Should -BeTrue
        @($j.missed).Count | Should -Be 0
        $j.complete | Should -BeTrue
    }

    It 'reports an in-scope session the evidence missed' {
        $out = & $coverage -Date '2026-11-10' -RepoRoot $tower -SessionDbPath $db -EvidenceJson $evPartial | Out-String
        $j = $out | ConvertFrom-Json
        $j.verified | Should -BeTrue
        @($j.missed).Count | Should -Be 1
        @($j.missed) | Should -Contain $fullC1
        $j.complete | Should -BeFalse
    }

    It 'fails loudly on a missing evidence file' {
        { & $coverage -Date '2026-11-10' -RepoRoot $tower -SessionDbPath $db -EvidenceJson (Join-Path $TestDrive 'ghost.json') } | Should -Throw
    }

    It 'writes the receipt with -OutJson and prints it' {
        $dest = Join-Path $TestDrive 'out/261110.coverage.json'
        $out = & $coverage -Date '2026-11-10' -RepoRoot $tower -SessionDbPath $db -EvidenceJson $evAll -OutJson $dest | Out-String
        Test-Path $dest | Should -BeTrue
        (Get-Content $dest -Raw | ConvertFrom-Json).complete | Should -BeTrue
        ($out | ConvertFrom-Json).storeSessions | Should -Be 4
    }

    It 'watches every manifest repo in multi mode' {
        $w2 = Join-Path $TestDrive 'watched2'
        New-Item -ItemType Directory -Force -Path $w2 | Out-Null
        git -C $w2 init -q
        git -C $w2 remote add origin 'https://github.com/w/repo.git'
        $manifestDir = Join-Path $tower 'reports/daily'
        New-Item -ItemType Directory -Force -Path $manifestDir | Out-Null
        $manifest = @{
            schema = 1; mode = 'multi'
            repos  = @($tower, $w2)
        } | ConvertTo-Json
        [IO.File]::WriteAllText((Join-Path $manifestDir 'daily-report.manifest.json'), $manifest)
        try {
            $out = & $coverage -Date '2026-11-10' -RepoRoot $tower -SessionDbPath $db -EvidenceJson $evAll | Out-String
            $j = $out | ConvertFrom-Json
            $j.mode | Should -Be 'multi'
            $j.watched | Should -Be 2
            $j.inScope | Should -Be 2
        }
        finally {
            Remove-Item (Join-Path $manifestDir 'daily-report.manifest.json') -Force -ErrorAction SilentlyContinue
        }
    }
}
