# Pester tests for scripts/workspace/check-powershell.ps1 (retro 2026-11-21).
# The linter exits with a code, so every invocation runs as a subprocess -
# dot-sourcing it would take the Pester host down with it.

BeforeAll {
    $script:linter = (Resolve-Path (Join-Path $PSScriptRoot '..' 'check-powershell.ps1')).Path
    $script:pwsh = (Get-Process -Id $PID).Path
    $script:fixtures = [System.Collections.Generic.List[string]]::new()

    function Invoke-Lint {
        param(
            [Parameter(Mandatory)][string]$Content,
            # Fixture file name; the temp rule scopes by *.Tests.ps1.
            [string]$Name = 'fixture.ps1'
        )

        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('pshlint-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir | Out-Null
        $file = Join-Path $dir $Name
        Set-Content -Path $file -Value $Content -Encoding UTF8
        $script:fixtures.Add($dir)
        $out = @(& $script:pwsh -NoProfile -File $script:linter -Path $file 2>&1 | ForEach-Object { "$_" })
        return [pscustomobject]@{
            Code   = $LASTEXITCODE
            Output = ($out -join "`n")
        }
    }
}

AfterAll {
    foreach ($dir in $script:fixtures) {
        Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'check-powershell.ps1' {
    It 'passes a clean script' {
        $r = Invoke-Lint -Content "param([string]`$Name)`nWrite-Output `$Name"
        $r.Code | Should -Be 0
        $r.Output | Should -Match '\[PASS\] pshlint:'
    }

    It 'flags a parse failure with file and line' {
        $r = Invoke-Lint -Content "function Broken {`n    if (`$true) {`n"
        $r.Code | Should -Be 1
        $r.Output | Should -Match '\[FAIL\] pshlint: parse:'
        $r.Output | Should -Match 'fixture\.ps1:2'
    }

    It 'flags a script param assigned before first read (the clobber class)' {
        $r = Invoke-Lint -Content "param([int]`$MaxItems)`n`$MaxItems = 300`nWrite-Output `$MaxItems"
        $r.Code | Should -Be 1
        $r.Output | Should -Match 'clobber:'
        $r.Output | Should -Match 'assigned before first read'
    }

    It 'flags a case-variant assignment of the same param (PowerShell names are case-insensitive)' {
        $r = Invoke-Lint -Content "param([int]`$TreeMaxIssues)`n`$treemaxissues = 300`nWrite-Output `$TreeMaxIssues"
        $r.Code | Should -Be 1
        $r.Output | Should -Match 'clobber:'
    }

    It 'allows read-first defaulting (the deliberate guard idiom)' {
        $r = Invoke-Lint -Content (@(
                'param([string]$Out)'
                'if ([string]::IsNullOrWhiteSpace($Out)) { $Out = ''fallback'' }'
                'Write-Output $Out'
            ) -join "`n")
        $r.Code | Should -Be 0
    }

    It 'allows a function param assigned after a read' {
        $r = Invoke-Lint -Content (@(
                'function Convert-ToLabel {'
                '    param([string]$Value)'
                '    if ($null -eq $Value) { $Value = '''' }'
                '    return $Value'
                '}'
            ) -join "`n")
        $r.Code | Should -Be 0
    }

    It 'flags a function param clobbered before its first read' {
        $r = Invoke-Lint -Content (@(
                'function Convert-ToLabel {'
                '    param([string]$Value)'
                '    $Value = ''rewritten'''
                '    return $Value'
                '}'
            ) -join "`n")
        $r.Code | Should -Be 1
        $r.Output | Should -Match 'in function Convert-ToLabel param'
    }

    It 'attributes a nested function own-param clobber to the nested scope only' {
        $r = Invoke-Lint -Content (@(
                'param([string]$Value)'
                'function Get-Other {'
                '    param([string]$Value)'
                '    $Value = ''local'''
                '    return $Value'
                '}'
                'Write-Output $Value'
            ) -join "`n")
        $r.Code | Should -Be 1
        $r.Output | Should -Match 'in function Get-Other param'
        $r.Output | Should -Not -Match 'in script param'
    }

    It 'does not flag nested functions that merely assign an outer-scope name' {
        $r = Invoke-Lint -Content (@(
                'param([string]$Value)'
                'function Get-Other {'
                '    $Value = ''local'''
                '    return $Value'
                '}'
                'Write-Output $Value'
            ) -join "`n")
        $r.Code | Should -Be 0
    }

    It 'allows preserve-then-resolve (assignment reads the argument in its own RHS)' {
        $r = Invoke-Lint -Content (@(
                'param([string]$Repo)'
                '$Repo = Resolve-Thing -Repo $Repo -Fallback ''origin'''
                'Write-Output $Repo'
            ) -join "`n")
        $r.Code | Should -Be 0
    }

    It 'flags the same bug in a directory scan' {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('pshlint-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir | Out-Null
        $script:fixtures.Add($dir)
        Set-Content -Path (Join-Path $dir 'ok.ps1') -Value "param([string]`$Name)`n`$Name = 'x'`nWrite-Output `$Name"
        $out = @(& $script:pwsh -NoProfile -File $script:linter -Path $dir 2>&1 | ForEach-Object { "$_" })
        $LASTEXITCODE | Should -Be 1
        ($out -join ' ') | Should -Match 'clobber:'
    }

    Context 'portability rules (exe and temp)' {
        It 'flags a command-position .exe invocation' {
            $r = Invoke-Lint -Content "sqlite3.exe `$db 'SELECT 1'"
            $r.Code | Should -Be 1
            $r.Output | Should -Match 'exe: .*fixture\.ps1:1'
            $r.Output | Should -Match 'invoke the bare name'
        }

        It 'allows .exe in a Get-Command guard - an argument, not an invocation' {
            $r = Invoke-Lint -Content "if (Get-Command sqlite3.exe -ErrorAction SilentlyContinue) { Write-Output 'ok' }"
            $r.Code | Should -Be 0
        }

        It 'allows .exe inside a string literal' {
            $r = Invoke-Lint -Content "`$msg = 'see the sqlite3.exe docs'`nWrite-Output `$msg"
            $r.Code | Should -Be 0
        }

        It 'flags $env:TEMP in a test file with the file and line' {
            $r = Invoke-Lint -Name 'portable.Tests.ps1' -Content "`$log = Join-Path `$env:TEMP 'x.log'`nWrite-Output `$log"
            $r.Code | Should -Be 1
            $r.Output | Should -Match 'temp: .*portable\.Tests\.ps1:1'
            $r.Output | Should -Match 'GetTempPath'
        }

        It 'allows the platform temp dir in a test file' {
            $r = Invoke-Lint -Name 'portable.Tests.ps1' -Content "`$log = Join-Path ([IO.Path]::GetTempPath()) 'x.log'`nWrite-Output `$log"
            $r.Code | Should -Be 0
        }

        It 'scopes the temp rule to test files' {
            $r = Invoke-Lint -Content "`$log = Join-Path `$env:TEMP 'x.log'`nWrite-Output `$log"
            $r.Code | Should -Be 0
        }
    }
}
