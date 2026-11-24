Describe 'Initialize-HomeRepo.ps1' {
    BeforeAll {
        $initializer = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/Initialize-HomeRepo.ps1'

        function New-Target {
            param([string]$Name)
            $target = Join-Path $TestDrive $Name
            return $target
        }

        function Invoke-Init {
            param([hashtable]$Arguments)
            $json = & $initializer @Arguments 2>$null | Out-String
            return ($json | ConvertFrom-Json)
        }
    }

    It 'seeds the full skeleton and reports what it created' {
        $target = New-Target 'fresh'
        $r = Invoke-Init @{ Path = $target; GitUser = 'Test User' }

        foreach ($rel in @('AGENTS.md', 'docs/coding-standards.md', 'docs/glossary.md', 'scripts/local-ci.ps1', '.githooks/pre-commit', '.gitignore')) {
            Join-Path $target ($rel -replace '/', '\') | Should -Exist
        }
        @($r.created) | Should -Contain 'AGENTS.md'
        @($r.skipped).Count | Should -Be 0
        $r.gitInitialized | Should -BeTrue
        $r.hooksPath | Should -Be '.githooks'
        $r.mode | Should -Be 'single'

        $agents = Get-Content -LiteralPath (Join-Path $target 'AGENTS.md') -Raw
        $agents | Should -Match 'Test User'
        $agents | Should -Match 'Placeholder repo'
    }

    It 'writes pointer bullets with a path and a clone URL' {
        $target = New-Target 'pointers'
        # Fixtures use /work/... because it is rooted on both platforms;
        # 'C:\Work\...' is not absolute on the Linux CI runner.
        $r = Invoke-Init @{
            Path = $target
            Repo = 'widgets|/work/widgets|https://github.com/acme/widgets.git'
        }

        @($r.pointers).Count | Should -Be 1
        @($r.pointers)[0].name | Should -Be 'widgets'
        $agents = Get-Content -LiteralPath (Join-Path $target 'AGENTS.md') -Raw
        $agents | Should -Match '/work/widgets'
        $agents | Should -Match 'Clone from https://github.com/acme/widgets.git if missing'
        $agents | Should -Not -Match 'Placeholder repo'
    }

    It 'switches the manifest to multi mode when watched repos are given' {
        $target = New-Target 'multi'
        Invoke-Init @{ Path = $target; WatchedRepo = @('/work/one', '/work/two') } | Out-Null

        $manifest = Get-Content -LiteralPath (Join-Path $target 'reports/daily/daily-report.manifest.json') -Raw | ConvertFrom-Json
        $manifest.schema | Should -Be 1
        $manifest.mode | Should -Be 'multi'
        @($manifest.repos).Count | Should -Be 2
    }

    It 'keeps single mode out of the manifest repos field' {
        $target = New-Target 'single'
        Invoke-Init @{ Path = $target } | Out-Null

        $manifest = Get-Content -LiteralPath (Join-Path $target 'reports/daily/daily-report.manifest.json') -Raw | ConvertFrom-Json
        $manifest.mode | Should -Be 'single'
        $manifest.PSObject.Properties.Name | Should -Not -Contain 'repos'
    }

    It 'never overwrites an existing seeded file unless -Force is given' {
        $target = New-Target 'preserve'
        Invoke-Init @{ Path = $target } | Out-Null
        $agentsPath = Join-Path $target 'AGENTS.md'
        Set-Content -LiteralPath $agentsPath -Value 'hand edited' -NoNewline

        $r = Invoke-Init @{ Path = $target }
        (Get-Content -LiteralPath $agentsPath -Raw) | Should -Be 'hand edited'
        @($r.skipped) | Should -Contain 'AGENTS.md'

        $r2 = Invoke-Init @{ Path = $target; Force = $true }
        (Get-Content -LiteralPath $agentsPath -Raw) | Should -Not -Be 'hand edited'
        @($r2.created) | Should -Contain 'AGENTS.md'
    }

    It 'keeps an existing manifest instead of replacing watched repos' {
        $target = New-Target 'manifest-preserve'
        Invoke-Init @{ Path = $target; WatchedRepo = @('/work/one') } | Out-Null
        $manifestPath = Join-Path $target 'reports/daily/daily-report.manifest.json'
        $before = Get-Content -LiteralPath $manifestPath -Raw

        $r = Invoke-Init @{ Path = $target; WatchedRepo = @('/work/two') }

        (Get-Content -LiteralPath $manifestPath -Raw) | Should -Be $before
        @($r.skipped) | Should -Contain 'reports/daily/daily-report.manifest.json'
    }

    It 'rejects a repo entry without a path or a URL' {
        $target = New-Target 'bad-entry'
        { & $initializer -Path $target -Repo 'widgets' } | Should -Throw
        Test-Path -LiteralPath (Join-Path $target 'AGENTS.md') | Should -BeFalse
    }

    It 'rejects a relative repo path' {
        $target = New-Target 'relative'
        { & $initializer -Path $target -Repo 'widgets|relative/path|https://github.com/acme/widgets.git' } | Should -Throw
    }

    It 'rejects a pointer path containing a space' {
        $target = New-Target 'spaced'
        { & $initializer -Path $target -Repo 'widgets|/work/my widgets|https://github.com/acme/widgets.git' } | Should -Throw
    }

    It 'rejects a malformed clone URL' {
        $target = New-Target 'bad-url'
        { & $initializer -Path $target -Repo 'widgets|/work/widgets|not-a-url' } | Should -Throw
    }

    It 'adds origin only when a remote URL is supplied' {
        $target = New-Target 'remote'
        Invoke-Init @{ Path = $target; RemoteUrl = 'https://github.com/acme/home.git' } | Out-Null
        (& git -C $target remote get-url origin).Trim() | Should -Be 'https://github.com/acme/home.git'
    }

    It 'skips git work with -SkipGitInit' {
        $target = New-Target 'no-git'
        $r = Invoke-Init @{ Path = $target; SkipGitInit = $true }
        $r.gitInitialized | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $target '.git') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $target 'AGENTS.md') | Should -BeTrue
    }
}
