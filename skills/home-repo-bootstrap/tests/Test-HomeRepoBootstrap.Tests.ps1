Describe 'Test-HomeRepoBootstrap.ps1' {
    BeforeAll {
        $skillRoot = Split-Path $PSScriptRoot -Parent
        $initializer = Join-Path $skillRoot 'scripts/Initialize-HomeRepo.ps1'
        $verifier = Join-Path $skillRoot 'scripts/Test-HomeRepoBootstrap.ps1'

        function New-HomeRepo {
            param([string]$Name, [hashtable]$Arguments = @{})
            $target = Join-Path $TestDrive $Name
            $base = @{ Path = $target; GitUser = 'Test User' }
            foreach ($key in $Arguments.Keys) { $base[$key] = $Arguments[$key] }
            & $initializer @base | Out-Null
            return $target
        }

        function Invoke-Verify {
            param([string]$Path, [switch]$SkipGate)
            $args = @{ Path = $Path }
            if ($SkipGate) { $args.SkipGate = $true }
            $json = & $verifier @args 2>$null | Out-String
            return ($json | ConvertFrom-Json)
        }
    }

    It 'passes a freshly seeded home repo' {
        $target = New-HomeRepo 'clean'
        $r = Invoke-Verify -Path $target
        $r.passed | Should -BeTrue
        (@($r.checks | Where-Object { $_.status -eq 'fail' })).Count | Should -Be 0
    }

    It 'reports each named check' {
        $target = New-HomeRepo 'checks'
        $r = Invoke-Verify -Path $target
        $names = @($r.checks | ForEach-Object { $_.name })
        foreach ($expected in @('layout', 'git', 'manifest', 'pointers', 'gate', 'skills')) {
            $names | Should -Contain $expected
        }
    }

    It 'fails when a seeded file is missing' {
        $target = New-HomeRepo 'missing-doc'
        Remove-Item -LiteralPath (Join-Path $target 'docs/glossary.md') -Force
        $r = Invoke-Verify -Path $target
        $r.passed | Should -BeFalse
        (@($r.checks | Where-Object { $_.name -eq 'layout' })[0].status) | Should -Be 'fail'
    }

    It 'fails when the hooks directory is not wired' {
        $target = New-HomeRepo 'unwired'
        git -C $target config --unset core.hooksPath
        $r = Invoke-Verify -Path $target
        $r.passed | Should -BeFalse
        (@($r.checks | Where-Object { $_.name -eq 'git' })[0].status) | Should -Be 'fail'
    }

    It 'fails when a pointer bullet lacks a clone URL' {
        $target = New-HomeRepo 'bad-pointer'
        $agentsPath = Join-Path $target 'AGENTS.md'
        $text = Get-Content -LiteralPath $agentsPath -Raw
        $text = $text -replace '(?m)^- .*$', '- widgets: /work/widgets.'
        Set-Content -LiteralPath $agentsPath -Value $text -NoNewline
        $r = Invoke-Verify -Path $target
        $r.passed | Should -BeFalse
        (@($r.checks | Where-Object { $_.name -eq 'pointers' })[0].status) | Should -Be 'fail'
    }

    It 'warns instead of failing for a pointer path absent on this machine' {
        $target = New-HomeRepo 'absent-path'
        $agentsPath = Join-Path $target 'AGENTS.md'
        $text = Get-Content -LiteralPath $agentsPath -Raw
        $text = $text -replace '(?m)^- .*$', '- widgets: /no/such/path. Clone from https://github.com/acme/widgets.git if missing.'
        Set-Content -LiteralPath $agentsPath -Value $text -NoNewline

        $r = Invoke-Verify -Path $target
        $r.passed | Should -BeTrue
        @($r.warnings).Count | Should -BeGreaterThan 0
    }

    It 'fails when the manifest mode is invalid' {
        $target = New-HomeRepo 'bad-manifest'
        $manifestPath = Join-Path $target 'reports/daily/daily-report.manifest.json'
        '{ "schema": 1, "mode": "tower" }' | Set-Content -LiteralPath $manifestPath
        $r = Invoke-Verify -Path $target
        $r.passed | Should -BeFalse
        (@($r.checks | Where-Object { $_.name -eq 'manifest' })[0].status) | Should -Be 'fail'
    }

    It 'fails when multi mode lists no repos' {
        $target = New-HomeRepo 'empty-multi'
        $manifestPath = Join-Path $target 'reports/daily/daily-report.manifest.json'
        '{ "schema": 1, "mode": "multi", "repos": [] }' | Set-Content -LiteralPath $manifestPath
        $r = Invoke-Verify -Path $target
        $r.passed | Should -BeFalse
    }

    It 'accepts a POSIX absolute pointer path so a non-Windows teammate passes the gate' {
        $target = New-HomeRepo 'posix-pointer'
        $agentsPath = Join-Path $target 'AGENTS.md'
        $text = Get-Content -LiteralPath $agentsPath -Raw
        $text = $text -replace '(?m)^- .*$', '- widgets: /home/dev/widgets. Clone from https://github.com/acme/widgets.git if missing.'
        Set-Content -LiteralPath $agentsPath -Value $text -NoNewline

        $r = Invoke-Verify -Path $target
        (@($r.checks | Where-Object { $_.name -eq 'pointers' })[0].status) | Should -Be 'pass'
    }

    It 'does not read a clone URL as the pointer path' {
        $target = New-HomeRepo 'url-not-path'
        $agentsPath = Join-Path $target 'AGENTS.md'
        $text = Get-Content -LiteralPath $agentsPath -Raw
        $text = $text -replace '(?m)^- .*$', '- widgets: Clone from https://github.com/acme/widgets.git if missing.'
        Set-Content -LiteralPath $agentsPath -Value $text -NoNewline

        $r = Invoke-Verify -Path $target
        (@($r.checks | Where-Object { $_.name -eq 'pointers' })[0].status) | Should -Be 'fail'
        (@($r.checks | Where-Object { $_.name -eq 'pointers' })[0].detail) | Should -Match 'without a local path'
    }

    It 'fails when the gate is red and reports the drift check only on request' {
        $target = New-HomeRepo 'drift-default'
        $r = Invoke-Verify -Path $target
        $names = @($r.checks | ForEach-Object { $_.name })
        $names | Should -Not -Contain 'drift'
    }

    It 'reports matching seeded files as pass when a seed source is given' {
        $target = New-HomeRepo 'drift-match'
        $skillAssets = Join-Path (Split-Path $PSScriptRoot -Parent) 'assets'
        $json = & $verifier -Path $target -SeedSource $skillAssets 2>$null | Out-String
        $r = $json | ConvertFrom-Json
        $drift = @($r.checks | Where-Object { $_.name -eq 'drift' })[0]
        $drift.status | Should -Be 'pass'
    }

    It 'fails when a seeded file drifts from the published asset' {
        $target = New-HomeRepo 'drift-mismatch'
        $ciPath = Join-Path $target 'scripts/local-ci.ps1'
        Add-Content -LiteralPath $ciPath -Value '# local-only edit'
        $skillAssets = Join-Path (Split-Path $PSScriptRoot -Parent) 'assets'

        $json = & $verifier -Path $target -SeedSource $skillAssets 2>$null | Out-String
        $r = $json | ConvertFrom-Json
        $r.passed | Should -BeFalse
        $drift = @($r.checks | Where-Object { $_.name -eq 'drift' })[0]
        $drift.status | Should -Be 'fail'
        $drift.detail | Should -Match 'scripts/local-ci.ps1'
        $drift.detail | Should -Match 'home-repo-bootstrap/assets'
    }

    It 'fails the drift check when the seed source does not exist' {
        $target = New-HomeRepo 'drift-missing-source'
        $json = & $verifier -Path $target -SeedSource (Join-Path $TestDrive 'no-assets') 2>$null | Out-String
        $r = $json | ConvertFrom-Json
        @($r.checks | Where-Object { $_.name -eq 'drift' })[0].status | Should -Be 'fail'
    }

    It 'fails when the local CI gate fails' {
        $target = New-HomeRepo 'red-gate'
        $agentsPath = Join-Path $target 'AGENTS.md'
        $text = Get-Content -LiteralPath $agentsPath -Raw
        $text = $text -replace '(?m)^- .*$', '- widgets: /work/widgets.'
        Set-Content -LiteralPath $agentsPath -Value $text -NoNewline

        $r = Invoke-Verify -Path $target
        (@($r.checks | Where-Object { $_.name -eq 'gate' })[0].status) | Should -Be 'fail'
    }

    It 'marks the gate check as skipped on request' {
        $target = New-HomeRepo 'skip-gate'
        $r = Invoke-Verify -Path $target -SkipGate
        (@($r.checks | Where-Object { $_.name -eq 'gate' })[0].status) | Should -Be 'skip'
    }

    It 'rejects a relative path' {
        { & $verifier -Path 'relative/home' } | Should -Throw
    }

    It 'rejects a path that does not exist' {
        { & $verifier -Path (Join-Path $TestDrive 'nope') } | Should -Throw
    }
}
