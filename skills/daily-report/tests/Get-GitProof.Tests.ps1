Describe 'Get-GitProof.ps1' {
    BeforeAll {
        $scriptDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts'
        $repo = Join-Path $TestDrive 'repo'
        New-Item -ItemType Directory -Force -Path $repo | Out-Null
        git -C $repo init -q
        git -C $repo config user.name 'Test User'
        git -C $repo config user.email 'test@example.com'
        # Commits must stay date-monotonic: git prunes the walk by date, so a
        # later commit with an older date hides its newer-dated parents.
        Set-Content (Join-Path $repo 'd.txt') 'w'; git -C $repo add d.txt
        $env:GIT_AUTHOR_DATE = '2026-11-09T09:00:00'; $env:GIT_COMMITTER_DATE = '2026-11-09T09:00:00'
        git -C $repo commit -q -m 'chore: other day'
        Set-Content (Join-Path $repo 'a.txt') 'x'; git -C $repo add a.txt
        $env:GIT_AUTHOR_DATE = '2026-11-10T09:00:00'; $env:GIT_COMMITTER_DATE = '2026-11-10T09:00:00'
        git -C $repo commit -q -m 'feat: real work'
        Set-Content (Join-Path $repo 'b.txt') 'y'; git -C $repo add b.txt
        $env:GIT_AUTHOR_DATE = '2026-11-10T10:00:00'; $env:GIT_COMMITTER_DATE = '2026-11-10T10:00:00'
        git -C $repo commit -q -m 'Agent host session abc123 - turn 3'
        git -C $repo config user.name 'Other Dev'; git -C $repo config user.email 'other@example.com'
        Set-Content (Join-Path $repo 'c.txt') 'z'; git -C $repo add c.txt
        $env:GIT_AUTHOR_DATE = '2026-11-10T11:00:00'; $env:GIT_COMMITTER_DATE = '2026-11-10T11:00:00'
        git -C $repo commit -q -m 'chore: foreign work'
        git -C $repo config user.name 'Test User'; git -C $repo config user.email 'test@example.com'
        Remove-Item Env:GIT_AUTHOR_DATE -ErrorAction SilentlyContinue
        Remove-Item Env:GIT_COMMITTER_DATE -ErrorAction SilentlyContinue
    }

    It 'returns only the runner commits of the day, excluding checkpoint noise' {
        $out = & (Join-Path $scriptDir 'Get-GitProof.ps1') -Date '2026-11-10' -RepoRoot $repo -Author 'test@example.com' | Out-String
        $j = $out | ConvertFrom-Json
        $j.commitCount | Should -Be 1
        $j.noiseExcluded | Should -Be 1
        $j.commits[0].subject | Should -Be 'feat: real work'
        $j.commits[0].files.Count | Should -Be 1
    }

    It 'surfaces untracked files modified inside the window as proof' {
        $new = Join-Path $repo 'new-artifact.md'
        Set-Content $new 'x'
        (Get-Item $new).LastWriteTime = [DateTime]'2026-11-10 12:00'
        $old = Join-Path $repo 'old-artifact.md'
        Set-Content $old 'y'
        (Get-Item $old).LastWriteTime = [DateTime]'2026-11-01 09:00'
        $out = & (Join-Path $scriptDir 'Get-GitProof.ps1') -Date '2026-11-10' -RepoRoot $repo -Author 'test@example.com' | Out-String
        $j = $out | ConvertFrom-Json
        $paths = @($j.workingTree | ForEach-Object { $_.path })
        $paths | Should -Contain 'new-artifact.md'
        $paths | Should -Not -Contain 'old-artifact.md'
    }

    It 'rejects a window wider than one calendar day' {
        { & (Join-Path $scriptDir 'Get-GitProof.ps1') -Start '2026-11-10 08:00' -End '2026-11-11 08:00' -RepoRoot $repo -Author 'test@example.com' } | Should -Throw
    }

    It 'rejects mixing -Date with a window' {
        { & (Join-Path $scriptDir 'Get-GitProof.ps1') -Date '2026-11-10' -Start '2026-11-10 08:00' -End '2026-11-10 12:00' -RepoRoot $repo } | Should -Throw
    }

    It 'rejects a missing day' {
        { & (Join-Path $scriptDir 'Get-GitProof.ps1') -RepoRoot $repo } | Should -Throw
    }
}
