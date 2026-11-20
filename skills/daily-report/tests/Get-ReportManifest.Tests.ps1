Describe 'Get-ReportManifest.ps1' {
    BeforeAll {
        $scriptDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts'
        $resolver = Join-Path $scriptDir 'Get-ReportManifest.ps1'

        $tower = Join-Path $TestDrive 'home-repo'
        New-Item -ItemType Directory -Force -Path $tower | Out-Null
        git -C $tower init -q
        git -C $tower config user.name 'Test User'
        git -C $tower config user.email 'test@example.com'

        $watched = Join-Path $TestDrive 'watched'
        New-Item -ItemType Directory -Force -Path $watched | Out-Null
        git -C $watched init -q
        git -C $watched remote add origin https://github.com/acme/widgets.git

        $towerTop = (git -C $tower rev-parse --show-toplevel).Trim()

        function New-Manifest {
            param([string]$Root, $Object)
            $dir = Join-Path $Root 'reports/daily'
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            ($Object | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath (Join-Path $dir 'daily-report.manifest.json')
        }
    }

    It 'fails loudly when the manifest is absent and -Optional is not given' {
        { & $resolver -RepoRoot $tower } | Should -Throw
    }

    It 'answers single mode for an absent manifest with -Optional' {
        $j = & $resolver -RepoRoot $tower -Optional | Out-String | ConvertFrom-Json
        $j.present | Should -BeFalse
        $j.mode | Should -Be 'single'
        $j.repos.Count | Should -Be 0
        $j.homeRepoRoot.Replace('/', '\').TrimEnd('\') | Should -Be $towerTop.Replace('/', '\').TrimEnd('\')
    }

    It 'resolves a multi manifest into mode, tower, and per-repo facts' {
        New-Manifest -Root $tower -Object ([ordered]@{
            schema = 1
            mode   = 'multi'
            repos  = @($watched, $tower)
        })
        $j = & $resolver -RepoRoot $tower -Optional | Out-String | ConvertFrom-Json
        $j.present | Should -BeTrue
        $j.mode | Should -Be 'multi'
        @($j.repos).Count | Should -Be 2
        $byRepo = @($j.repos)
        ($byRepo | Where-Object { $_.path.Replace('/', '\').TrimEnd('\') -ieq $watched.Replace('/', '\').TrimEnd('\') })[0].name | Should -Be 'acme/widgets'
        ($byRepo | Where-Object { $_.path.Replace('/', '\').TrimEnd('\') -ieq $watched.Replace('/', '\').TrimEnd('\') })[0].exists | Should -BeTrue
        @($byRepo | Where-Object { $_.isHomeRepo }).Count | Should -Be 1
        (@($byRepo | Where-Object { $_.isHomeRepo })[0].path.Replace('/', '\').TrimEnd('\')) | Should -Be $towerTop.Replace('/', '\').TrimEnd('\')
    }

    It 'marks a watched path missing on this machine instead of failing' {
        $missing = Join-Path $TestDrive 'no-such-checkout'
        New-Manifest -Root $tower -Object ([ordered]@{
            schema = 1
            mode   = 'multi'
            repos  = @($watched, $missing)
        })
        $j = & $resolver -RepoRoot $tower -Optional | Out-String | ConvertFrom-Json
        $j.mode | Should -Be 'multi'
        $gone = @($j.repos | Where-Object { $_.exists -eq $false })
        $gone.Count | Should -Be 1
        $gone[0].path | Should -Be $missing
    }

    It 'ignores repos in single mode - the manifest dictates the mode' {
        New-Manifest -Root $tower -Object ([ordered]@{
            schema = 1
            mode   = 'single'
            repos  = @('relative/junk', $watched)
        })
        $j = & $resolver -RepoRoot $tower -Optional | Out-String | ConvertFrom-Json
        $j.mode | Should -Be 'single'
        $j.repos.Count | Should -Be 0
    }

    It 'rejects a relative path in multi mode' {
        New-Manifest -Root $tower -Object ([ordered]@{
            schema = 1
            mode   = 'multi'
            repos  = @('some/where')
        })
        { & $resolver -RepoRoot $tower -Optional } | Should -Throw
    }

    It 'rejects duplicate paths in multi mode' {
        New-Manifest -Root $tower -Object ([ordered]@{
            schema = 1
            mode   = 'multi'
            repos  = @($watched, "$watched\")
        })
        { & $resolver -RepoRoot $tower -Optional } | Should -Throw
    }

    It 'rejects an unknown mode' {
        New-Manifest -Root $tower -Object ([ordered]@{
            schema = 1
            mode   = 'mega'
            repos  = @($watched)
        })
        { & $resolver -RepoRoot $tower -Optional } | Should -Throw
    }

    It 'rejects an unsupported or missing schema' {
        New-Manifest -Root $tower -Object ([ordered]@{
            schema = 2
            mode   = 'multi'
            repos  = @($watched)
        })
        { & $resolver -RepoRoot $tower -Optional } | Should -Throw
        New-Manifest -Root $tower -Object ([ordered]@{
            mode  = 'multi'
            repos = @($watched)
        })
        { & $resolver -RepoRoot $tower -Optional } | Should -Throw
    }

    It 'rejects malformed JSON' {
        $dir = Join-Path $tower 'reports/daily'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'daily-report.manifest.json') '{not json'
        { & $resolver -RepoRoot $tower -Optional } | Should -Throw
    }

    It 'rejects a path that exists but is not a git checkout' {
        $plain = Join-Path $TestDrive 'plain-dir'
        New-Item -ItemType Directory -Force -Path $plain | Out-Null
        New-Manifest -Root $tower -Object ([ordered]@{
            schema = 1
            mode   = 'multi'
            repos  = @($plain)
        })
        { & $resolver -RepoRoot $tower -Optional } | Should -Throw
    }

    It 'fails when the given root is not a git repository' {
        $plain = Join-Path $TestDrive 'outside-any-repo'
        New-Item -ItemType Directory -Force -Path $plain | Out-Null
        { & $resolver -RepoRoot $plain -Optional } | Should -Throw
    }
}
