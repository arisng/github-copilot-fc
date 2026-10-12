BeforeAll {
    $script:previousEAP = $ErrorActionPreference
    . (Join-Path $PSScriptRoot '..' 'Resolve-CopilotCliPath.ps1')
}

AfterAll {
    $ErrorActionPreference = $script:previousEAP
    Remove-Item -Path Env:\COPILOT_CLI_PATH -ErrorAction SilentlyContinue
}

Describe 'Test-CopilotCliCandidate' {
    It 'rejects a missing path' {
        Test-CopilotCliCandidate -Path (Join-Path $TestDrive 'missing-copilot.exe') -SkipProbe |
            Should -BeFalse
    }

    It 'rejects a directory (mirrors waza IsDir check)' {
        Test-CopilotCliCandidate -Path $TestDrive -SkipProbe | Should -BeFalse
    }

    It 'rejects a blank path' {
        Test-CopilotCliCandidate -Path '' -SkipProbe | Should -BeFalse
    }

    It 'accepts an existing file without probe' {
        $file = Join-Path $TestDrive 'copilot.exe'
        Set-Content -Path $file -Value 'stub'
        Test-CopilotCliCandidate -Path $file -SkipProbe | Should -BeTrue
    }

    It 'fails the --version probe for a non-runnable file' {
        $file = Join-Path $TestDrive 'not-a-real-binary.exe'
        Set-Content -Path $file -Value 'stub'
        Test-CopilotCliCandidate -Path $file | Should -BeFalse
    }
}

Describe 'Get-CopilotCliPathCandidate' {
    BeforeEach {
        Remove-Item -Path Env:\COPILOT_CLI_PATH -ErrorAction SilentlyContinue
        Mock Get-KnownCopilotCliPath { @() }
    }

    It 'honors a usable COPILOT_CLI_PATH override' {
        $file = Join-Path $TestDrive 'override.exe'
        Set-Content -Path $file -Value 'stub'
        $env:COPILOT_CLI_PATH = $file

        Get-CopilotCliPathCandidate -SkipProbe | Should -Be $file
    }

    It 'ignores an unusable override and falls through to PATH' {
        $env:COPILOT_CLI_PATH = 'X:\definitely\missing\copilot.exe'
        Mock Get-Command {
            [pscustomobject]@{ Source = 'C:\fake\copilot.exe' }
        }
        # Only the PATH candidate is usable; the stale override must fail validation.
        Mock Test-CopilotCliCandidate { $Path -eq 'C:\fake\copilot.exe' }

        $warnings = @()
        $result = Get-CopilotCliPathCandidate -SkipProbe -WarningVariable warnings
        $result | Should -Be 'C:\fake\copilot.exe'
        $warnings.Count | Should -BeGreaterThan 0
        $warnings[0].ToString() | Should -Match 're-detecting'
    }

    It 'treats an empty-string override as unset (no warning, detection proceeds)' {
        $env:COPILOT_CLI_PATH = ''
        Mock Get-Command {
            [pscustomobject]@{ Source = 'C:\fake\copilot.exe' }
        }
        Mock Test-CopilotCliCandidate { $true }

        $warnings = @()
        $result = Get-CopilotCliPathCandidate -SkipProbe -WarningVariable warnings
        $result | Should -Be 'C:\fake\copilot.exe'
        $warnings.Count | Should -Be 0
    }

    It 'skips non-.exe shims on Windows and picks the native binary' -Skip:(-not $IsWindows) {
        Mock Get-Command {
            @(
                [pscustomobject]@{ Source = 'C:\npm\copilot.cmd' },
                [pscustomobject]@{ Source = 'C:\npm\copilot.ps1' },
                [pscustomobject]@{ Source = 'C:\real\copilot.exe' }
            )
        }
        Mock Test-CopilotCliCandidate { $true }

        Get-CopilotCliPathCandidate -SkipProbe | Should -Be 'C:\real\copilot.exe'
    }

    It 'returns nothing when every candidate fails validation' {
        Mock Get-Command { [pscustomobject]@{ Source = 'C:\fake\copilot.exe' } }
        Mock Test-CopilotCliCandidate { $false }

        Get-CopilotCliPathCandidate -SkipProbe | Should -BeNullOrEmpty
    }
}

Describe 'Resolve-CopilotCliPath' {
    It 'returns the detected path without installing' {
        Mock Get-CopilotCliPathCandidate { 'C:\fake\copilot.exe' }
        Mock Install-CopilotCliFallback { throw 'install must not run when detection succeeds' }

        Resolve-CopilotCliPath | Should -Be 'C:\fake\copilot.exe'
    }

    It 'installs only when detection is empty and -InstallFallback is set' {
        $script:detectCalls = 0
        Mock Get-CopilotCliPathCandidate {
            $script:detectCalls++
            if ($script:detectCalls -eq 1) { $null } else { 'C:\new\copilot.exe' }
        }
        Mock Install-CopilotCliFallback { $true }

        Resolve-CopilotCliPath -InstallFallback | Should -Be 'C:\new\copilot.exe'
        Should -Invoke Install-CopilotCliFallback -Times 1 -Exactly
    }

    It 'returns nothing when not found and -InstallFallback is absent' {
        Mock Get-CopilotCliPathCandidate { $null }
        Mock Install-CopilotCliFallback { throw 'install must not run without -InstallFallback' }

        Resolve-CopilotCliPath -WarningAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'returns nothing when detection stays empty after install attempt' {
        Mock Get-CopilotCliPathCandidate { $null }
        Mock Install-CopilotCliFallback { $false }

        Resolve-CopilotCliPath -InstallFallback -WarningAction SilentlyContinue |
            Should -BeNullOrEmpty
    }
}

Describe 'Main-block contract (child process)' -Tag 'Integration' {
    BeforeAll {
        $script:childScript = Join-Path $PSScriptRoot '..' 'Resolve-CopilotCliPath.ps1'
    }

    It 'exits 0 with exactly one stdout line and warnings on stderr when override is stale' -Skip:(-not $IsWindows) {
        $stdoutFile = Join-Path $TestDrive 'out.txt'
        $stderrFile = Join-Path $TestDrive 'err.txt'
        $oldPath = $env:COPILOT_CLI_PATH
        $env:COPILOT_CLI_PATH = 'X:\definitely\missing\copilot.exe'
        try {
            $proc = Start-Process -FilePath 'pwsh' -ArgumentList @(
                '-NoProfile', '-File', $script:childScript, '-SkipProbe'
            ) -Wait -PassThru -WindowStyle Hidden `
              -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
        }
        finally {
            if ($null -eq $oldPath) { Remove-Item Env:\COPILOT_CLI_PATH -ErrorAction SilentlyContinue }
            else { $env:COPILOT_CLI_PATH = $oldPath }
        }

        $proc.ExitCode | Should -Be 0
        $stdoutLines = @(Get-Content $stdoutFile)
        $stdoutLines.Count | Should -Be 1
        $stdoutLines[0] | Should -Match 'copilot'
        (Get-Content $stderrFile -Raw) | Should -Match 're-detecting'
    }

    It 'exits 1 with empty stdout and a warning on stderr when no CLI is found' -Skip:(-not $IsWindows) {
        $stdoutFile = Join-Path $TestDrive 'out2.txt'
        $stderrFile = Join-Path $TestDrive 'err2.txt'
        # Blank PATH so neither PATH nor npm (known-location) detection can succeed.
        $emptyDir = Join-Path $TestDrive 'emptybin'
        New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null

        # Resolve pwsh before blanking PATH; child inherits parent env (reliable),
        # because -Environment @{PATH=...} can merge case-insensitively and leak Path.
        $pwshExe = (Get-Process -Id $PID).Path
        $oldPath = $env:PATH
        $oldOverride = $env:COPILOT_CLI_PATH
        $env:PATH = $emptyDir
        Remove-Item Env:\COPILOT_CLI_PATH -ErrorAction SilentlyContinue
        try {
            $proc = Start-Process -FilePath $pwshExe -ArgumentList @(
                '-NoProfile', '-File', $script:childScript, '-SkipProbe'
            ) -Wait -PassThru -WindowStyle Hidden `
              -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
        }
        finally {
            $env:PATH = $oldPath
            if ($null -ne $oldOverride) { $env:COPILOT_CLI_PATH = $oldOverride }
        }

        $proc.ExitCode | Should -Be 1
        @(Get-Content $stdoutFile).Count | Should -Be 0
        (Get-Content $stderrFile -Raw) | Should -Match 'No Copilot CLI found'
    }

    It '-Persist writes the user-level env var and the value is re-resolvable' -Skip:(-not $IsWindows) {
        $userBefore = [Environment]::GetEnvironmentVariable('COPILOT_CLI_PATH', 'User')
        $oldPath = $env:COPILOT_CLI_PATH
        # Point the override at a guaranteed-usable file so detection succeeds deterministically.
        $stub = Join-Path $TestDrive 'persist-copilot.exe'
        Set-Content -Path $stub -Value 'stub'
        $env:COPILOT_CLI_PATH = $stub
        try {
            $proc = Start-Process -FilePath 'pwsh' -ArgumentList @(
                '-NoProfile', '-File', $script:childScript, '-SkipProbe', '-Persist'
            ) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $TestDrive 'out3.txt') `
              -RedirectStandardError (Join-Path $TestDrive 'err3.txt')

            $proc.ExitCode | Should -Be 0
            [Environment]::GetEnvironmentVariable('COPILOT_CLI_PATH', 'User') | Should -Be $stub
        }
        finally {
            if ($null -eq $oldPath) { Remove-Item Env:\COPILOT_CLI_PATH -ErrorAction SilentlyContinue }
            else { $env:COPILOT_CLI_PATH = $oldPath }
            [Environment]::SetEnvironmentVariable('COPILOT_CLI_PATH', $userBefore, 'User')
        }
    }
}

Describe 'Install-CopilotCliFallback' {
    BeforeEach {
        $script:wingetOrder = @()
    }

    It 'tries the MSIX package first, then the official portable package' -Skip:(-not $IsWindows) {
        Mock Invoke-WingetInstall {
            $script:wingetOrder += $Id
            return ($Id -eq 'GitHub.Copilot')
        }

        Install-CopilotCliFallback -WarningAction SilentlyContinue | Should -BeTrue
        $script:wingetOrder | Should -Be @('GitHub.Copilot.CLI', 'GitHub.Copilot')
    }

    It 'returns false when every install attempt fails' -Skip:(-not $IsWindows) {
        Mock Invoke-WingetInstall { $script:wingetOrder += $Id; return $false }

        Install-CopilotCliFallback -WarningAction SilentlyContinue | Should -BeFalse
        $script:wingetOrder.Count | Should -Be 2
    }
}
