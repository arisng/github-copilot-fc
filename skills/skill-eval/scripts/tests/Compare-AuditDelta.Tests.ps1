<#
.SYNOPSIS
    Pester tests for Compare-AuditDelta.ps1
#>

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..' | Join-Path -ChildPath 'Compare-AuditDelta.ps1'
}

Describe 'Compare-AuditDelta.ps1' {

    Context 'Input validation' {

        It 'Exits with code 2 when BeforeReport does not exist' {
            $result = & pwsh -NoProfile -File $script:ScriptPath -BeforeReport 'C:\nonexistent-before.json' -AfterReport 'C:\nonexistent-after.json' 2>&1
            $LASTEXITCODE | Should -Be 2
        }

        It 'Exits with code 2 when reports have mismatched audit_type' {
            $beforePath = Join-Path $TestDrive 'before.json'
            $afterPath  = Join-Path $TestDrive 'after.json'

            @{ audit_type = 'structural'; errors = @() } | ConvertTo-Json -Depth 5 | Set-Content $beforePath
            @{ audit_type = 'execution'; pass_rate = 0.8 } | ConvertTo-Json -Depth 5 | Set-Content $afterPath

            $result = & pwsh -NoProfile -File $script:ScriptPath -BeforeReport $beforePath -AfterReport $afterPath 2>&1
            $LASTEXITCODE | Should -Be 2
        }
    }

    Context 'Structural delta comparison' {

        It 'Reports improvement when error count decreases' {
            $beforePath = Join-Path $TestDrive 'before.json'
            $afterPath  = Join-Path $TestDrive 'after.json'

            @{ audit_type = 'structural'; errors = @('err1', 'err2', 'err3') } | ConvertTo-Json -Depth 5 | Set-Content $beforePath
            @{ audit_type = 'structural'; errors = @('err1') } | ConvertTo-Json -Depth 5 | Set-Content $afterPath

            $result = & pwsh -NoProfile -File $script:ScriptPath -BeforeReport $beforePath -AfterReport $afterPath 2>&1
            $json = $result | ConvertFrom-Json
            $json.passed | Should -BeTrue
            $json.delta.after_errors | Should -Be 1
        }

        It 'Reports regression when error count increases' {
            $beforePath = Join-Path $TestDrive 'before.json'
            $afterPath  = Join-Path $TestDrive 'after.json'

            @{ audit_type = 'structural'; errors = @('err1') } | ConvertTo-Json -Depth 5 | Set-Content $beforePath
            @{ audit_type = 'structural'; errors = @('err1', 'err2', 'err3') } | ConvertTo-Json -Depth 5 | Set-Content $afterPath

            $result = & pwsh -NoProfile -File $script:ScriptPath -BeforeReport $beforePath -AfterReport $afterPath 2>&1
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'Execution delta comparison' {

        It 'Reports improvement when pass_rate increases' {
            $beforePath = Join-Path $TestDrive 'before.json'
            $afterPath  = Join-Path $TestDrive 'after.json'

            $beforeReport = @{
                audit_type = 'execution'
                pass_rate  = 0.5
                cases = @(@{
                    id = 'case-01'
                    assertions = @(
                        @{ id = 'A1'; status = 'fail' },
                        @{ id = 'A2'; status = 'pass' }
                    )
                })
            }
            $afterReport = @{
                audit_type = 'execution'
                pass_rate  = 1.0
                cases = @(@{
                    id = 'case-01'
                    assertions = @(
                        @{ id = 'A1'; status = 'pass' },
                        @{ id = 'A2'; status = 'pass' }
                    )
                })
            }

            $beforeReport | ConvertTo-Json -Depth 5 | Set-Content $beforePath
            $afterReport  | ConvertTo-Json -Depth 5 | Set-Content $afterPath

            $result = & pwsh -NoProfile -File $script:ScriptPath -BeforeReport $beforePath -AfterReport $afterPath 2>&1
            $json = $result | ConvertFrom-Json
            $json.passed | Should -BeTrue
        }

        It 'Detects regression on specific assertions' {
            $beforePath = Join-Path $TestDrive 'before.json'
            $afterPath  = Join-Path $TestDrive 'after.json'

            $beforeReport = @{
                audit_type = 'execution'
                pass_rate  = 1.0
                cases = @(@{
                    id = 'case-01'
                    assertions = @(
                        @{ id = 'A1'; status = 'pass' },
                        @{ id = 'A2'; status = 'pass' }
                    )
                })
            }
            $afterReport = @{
                audit_type = 'execution'
                pass_rate  = 0.5
                cases = @(@{
                    id = 'case-01'
                    assertions = @(
                        @{ id = 'A1'; status = 'fail' },
                        @{ id = 'A2'; status = 'pass' }
                    )
                })
            }

            $beforeReport | ConvertTo-Json -Depth 5 | Set-Content $beforePath
            $afterReport  | ConvertTo-Json -Depth 5 | Set-Content $afterPath

            $result = & pwsh -NoProfile -File $script:ScriptPath -BeforeReport $beforePath -AfterReport $afterPath 2>&1
            $json = $result | ConvertFrom-Json
            $json.passed | Should -BeFalse
            $json.delta.regressed_assertions | Should -Contain 'A1'
        }

        It 'Detects added and removed assertions' {
            $beforePath = Join-Path $TestDrive 'before.json'
            $afterPath  = Join-Path $TestDrive 'after.json'

            $beforeReport = @{
                audit_type = 'execution'
                pass_rate  = 1.0
                cases = @(@{
                    id = 'case-01'
                    assertions = @(
                        @{ id = 'A1'; status = 'pass' },
                        @{ id = 'A2'; status = 'pass' }
                    )
                })
            }
            $afterReport = @{
                audit_type = 'execution'
                pass_rate  = 1.0
                cases = @(@{
                    id = 'case-01'
                    assertions = @(
                        @{ id = 'A1'; status = 'pass' },
                        @{ id = 'A3'; status = 'pass' }
                    )
                })
            }

            $beforeReport | ConvertTo-Json -Depth 5 | Set-Content $beforePath
            $afterReport  | ConvertTo-Json -Depth 5 | Set-Content $afterPath

            $result = & pwsh -NoProfile -File $script:ScriptPath -BeforeReport $beforePath -AfterReport $afterPath 2>&1
            $json = $result | ConvertFrom-Json
            $json.delta.added_assertions | Should -Contain 'A3'
            $json.delta.removed_assertions | Should -Contain 'A2'
        }
    }

    Context 'Activation delta comparison' {

        It 'Reports improvement when accuracy increases' {
            $beforePath = Join-Path $TestDrive 'before.json'
            $afterPath  = Join-Path $TestDrive 'after.json'

            @{ audit_type = 'activation'; accuracy = 70; false_positive_rate = 20; false_negative_rate = 10 } | ConvertTo-Json -Depth 5 | Set-Content $beforePath
            @{ audit_type = 'activation'; accuracy = 90; false_positive_rate = 5; false_negative_rate = 5 } | ConvertTo-Json -Depth 5 | Set-Content $afterPath

            $result = & pwsh -NoProfile -File $script:ScriptPath -BeforeReport $beforePath -AfterReport $afterPath 2>&1
            $json = $result | ConvertFrom-Json
            $json.passed | Should -BeTrue
            $json.delta.accuracy_delta | Should -Be 20
        }
    }

    Context 'Output structure' {

        It 'Outputs JSON with passed field' {
            $beforePath = Join-Path $TestDrive 'before.json'
            $afterPath  = Join-Path $TestDrive 'after.json'

            @{ audit_type = 'structural'; errors = @() } | ConvertTo-Json -Depth 5 | Set-Content $beforePath
            @{ audit_type = 'structural'; errors = @() } | ConvertTo-Json -Depth 5 | Set-Content $afterPath

            $result = & pwsh -NoProfile -File $script:ScriptPath -BeforeReport $beforePath -AfterReport $afterPath 2>&1
            $json = $result | ConvertFrom-Json
            $json.PSObject.Properties.Name | Should -Contain 'passed'
            $json.PSObject.Properties.Name | Should -Contain 'delta'
        }
    }
}
