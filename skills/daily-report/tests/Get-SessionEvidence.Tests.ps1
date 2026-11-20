Describe 'Get-SessionEvidence.ps1' {
    BeforeAll {
        $scriptDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts'
        $repo = Join-Path $TestDrive 'repo'
        New-Item -ItemType Directory -Force -Path $repo | Out-Null
        git -C $repo init -q
        git -C $repo remote add origin 'https://github.com/o/r.git'
        $db = Join-Path $TestDrive 'store.db'
        sqlite3.exe $db @'
CREATE TABLE sessions (id TEXT, branch TEXT, summary TEXT, repository TEXT, created_at TEXT, updated_at TEXT);
CREATE TABLE turns (session_id TEXT, turn_index INT, user_message TEXT, assistant_response TEXT, timestamp TEXT);
CREATE TABLE session_files (session_id TEXT, file_path TEXT, tool_name TEXT, turn_index INT);
CREATE TABLE session_refs (session_id TEXT, ref_type TEXT, ref_value TEXT, created_at TEXT);
INSERT INTO sessions VALUES ('s1','main','work','o/r','2026-11-10','2026-11-10');
INSERT INTO sessions VALUES ('s2','main','other repo','x/y','2026-11-10','2026-11-10');
INSERT INTO sessions VALUES ('s3','main','azure work','contoso/Proj/App','2026-11-10','2026-11-10');
INSERT INTO turns VALUES ('s1',0,'do things','done','2026-11-10T02:00:00');
INSERT INTO turns VALUES ('s2',0,'other','other','2026-11-10T02:00:00');
INSERT INTO turns VALUES ('s3',0,'azure','done','2026-11-10T02:00:00');
INSERT INTO turns VALUES ('s1',1,'yesterday','old','2026-11-09T02:00:00');
INSERT INTO session_files VALUES ('s1','a.txt','edit',0);
INSERT INTO session_files VALUES ('s1','b.txt','edit',1);
INSERT INTO session_files VALUES ('s1','c.txt','create',2);
'@
    }

    It 'parses multi-row results (sqlite3 pretty-prints across lines)' {
        $out = & (Join-Path $scriptDir 'Get-SessionEvidence.ps1') -Date '2026-11-10' -RepoRoot $repo -SessionDbPath $db -UtcOffsetHours 7 | Out-String
        $j = $out | ConvertFrom-Json
        $j.sessions[0].files.Count | Should -Be 3
    }

    It 'returns every turn inside the window, not just first and last' {
        $out = & (Join-Path $scriptDir 'Get-SessionEvidence.ps1') -Date '2026-11-10' -RepoRoot $repo -SessionDbPath $db -UtcOffsetHours 7 | Out-String
        $j = $out | ConvertFrom-Json
        $s1 = @($j.sessions | Where-Object { $_.id -eq 's1' })[0]
        $turns = @($s1.windowTurns)
        $turns.Count | Should -Be 1
        $turns[0].turn | Should -Be 0
    }

    It 'returns only sessions of the current repository in the day' {
        $out = & (Join-Path $scriptDir 'Get-SessionEvidence.ps1') -Date '2026-11-10' -RepoRoot $repo -SessionDbPath $db -UtcOffsetHours 7 | Out-String
        $j = $out | ConvertFrom-Json
        $j.sessionCount | Should -Be 1
        $j.sessions[0].id | Should -Be 's1'
    }

    It 'refuses an unresolvable repository (no unfiltered queries)' {
        $bare = Join-Path $TestDrive 'bare'; New-Item -ItemType Directory -Force -Path $bare | Out-Null
        git -C $bare init -q
        { & (Join-Path $scriptDir 'Get-SessionEvidence.ps1') -Date '2026-11-10' -RepoRoot $bare -SessionDbPath $db } | Should -Throw
    }

    It 'scopes an Azure DevOps HTTPS remote as org/project/repo' {
        $az = Join-Path $TestDrive 'az-https'; New-Item -ItemType Directory -Force -Path $az | Out-Null
        git -C $az init -q
        git -C $az remote add origin 'https://contoso@dev.azure.com/contoso/Proj/_git/App'
        $out = & (Join-Path $scriptDir 'Get-SessionEvidence.ps1') -Date '2026-11-10' -RepoRoot $az -SessionDbPath $db -UtcOffsetHours 7 | Out-String
        $LASTEXITCODE | Should -Be 0
        $j = $out | ConvertFrom-Json
        $j.repository | Should -Be 'contoso/Proj/App'
        $j.sessionCount | Should -Be 1
        $j.sessions[0].id | Should -Be 's3'
    }

    It 'scopes an Azure DevOps SSH remote (v3) as org/project/repo' {
        $az = Join-Path $TestDrive 'az-ssh'; New-Item -ItemType Directory -Force -Path $az | Out-Null
        git -C $az init -q
        git -C $az remote add origin 'git@ssh.dev.azure.com:v3/contoso/Proj/App'
        $out = & (Join-Path $scriptDir 'Get-SessionEvidence.ps1') -Date '2026-11-10' -RepoRoot $az -SessionDbPath $db -UtcOffsetHours 7 | Out-String
        $LASTEXITCODE | Should -Be 0
        $j = $out | ConvertFrom-Json
        $j.repository | Should -Be 'contoso/Proj/App'
        $j.sessionCount | Should -Be 1
        $j.sessions[0].id | Should -Be 's3'
    }

    It 'rejects a window outside the day' {
        { & (Join-Path $scriptDir 'Get-SessionEvidence.ps1') -Date '2026-11-10' -Start '2026-11-09 08:00' -End '2026-11-09 12:00' -RepoRoot $repo -SessionDbPath $db } | Should -Throw
    }

    It 'refuses cloud rows from another repository' {
        $cloud = Join-Path $TestDrive 'cloud.json'
        '[{"id":"c1","repository":"x/y","updatedAt":"2026-11-10T02:00:00"}]' | Set-Content $cloud
        { & (Join-Path $scriptDir 'Get-SessionEvidence.ps1') -Date '2026-11-10' -RepoRoot $repo -SessionDbPath $db -CloudJson $cloud } | Should -Throw
    }
}
