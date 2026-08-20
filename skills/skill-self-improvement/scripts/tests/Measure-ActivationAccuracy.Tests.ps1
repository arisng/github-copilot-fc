<#
.SYNOPSIS
    Pester tests for Measure-ActivationAccuracy.ps1
#>

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..' | Join-Path -ChildPath 'Measure-ActivationAccuracy.ps1'
}

Describe 'Measure-ActivationAccuracy.ps1' {

    Context 'Path validation' {

        It 'Exits with code 2 when SkillDir does not exist' {
            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir 'C:\nonexistent-path-12345' 2>&1
            $LASTEXITCODE | Should -Be 2
        }

        It 'Exits with code 2 when activation-matrix.md is missing' {
            $tempDir = Join-Path $TestDrive "skill-$(Get-Random)"
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir 2>&1
            $LASTEXITCODE | Should -Be 2
        }
    }

    Context 'Matrix parsing' {

        BeforeEach {
            $tempDir = Join-Path $TestDrive "skill-$(Get-Random)"
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
        }

        It 'Exits with code 2 when no valid table is found' {
            Set-Content -Path (Join-Path $tempDir 'activation-matrix.md') -Value "# No table here`nJust some text."

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir 2>&1
            $LASTEXITCODE | Should -Be 2
        }

        It 'Exits with code 2 when table has no data rows' {
            $matrix = @"
# Activation Matrix

| ID | Prompt | Should Trigger | Actual Trigger | Failure Type | Notes |
|---|---|---|---|---|---|
"@
            Set-Content -Path (Join-Path $tempDir 'activation-matrix.md') -Value $matrix

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir 2>&1
            $LASTEXITCODE | Should -Be 2
        }
    }

    Context 'Metrics computation' {

        BeforeEach {
            $tempDir = Join-Path $TestDrive "skill-$(Get-Random)"
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
        }

        It 'Computes 100% accuracy for perfect results' {
            $matrix = @"
# Activation Matrix

| ID | Prompt | Should Trigger | Actual Trigger | Failure Type | Notes |
|---|---|---|---|---|---|
| pos-01 | prompt A | yes | yes | pass | |
| pos-02 | prompt B | yes | yes | pass | |
| neg-01 | prompt C | no | no | pass | |
| neg-02 | prompt D | no | no | pass | |
"@
            Set-Content -Path (Join-Path $tempDir 'activation-matrix.md') -Value $matrix

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir 2>&1
            $json = $result | ConvertFrom-Json
            $json.accuracy | Should -Be 100
            $json.passed | Should -BeTrue
        }

        It 'Computes accuracy with false positives' {
            $matrix = @"
# Activation Matrix

| ID | Prompt | Should Trigger | Actual Trigger | Failure Type | Notes |
|---|---|---|---|---|---|
| pos-01 | prompt A | yes | yes | pass | |
| pos-02 | prompt B | yes | yes | pass | |
| neg-01 | prompt C | no | yes | false_positive | |
| neg-02 | prompt D | no | no | pass | |
"@
            Set-Content -Path (Join-Path $tempDir 'activation-matrix.md') -Value $matrix

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir 2>&1
            $json = $result | ConvertFrom-Json
            $json.accuracy | Should -Be 75
            $json.false_positives | Should -Be 1
        }

        It 'Excludes pending rows from computation' {
            $matrix = @"
# Activation Matrix

| ID | Prompt | Should Trigger | Actual Trigger | Failure Type | Notes |
|---|---|---|---|---|---|
| pos-01 | prompt A | yes | yes | pass | |
| pos-02 | prompt B | yes | pending | pending | |
| neg-01 | prompt C | no | no | pass | |
| neg-02 | prompt D | no | pending | pending | |
"@
            Set-Content -Path (Join-Path $tempDir 'activation-matrix.md') -Value $matrix

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir 2>&1
            $json = $result | ConvertFrom-Json
            $json.evaluated_rows | Should -Be 2
            $json.pending_count | Should -Be 2
            $json.accuracy | Should -Be 100
        }

        It 'Warns on imbalanced matrix' {
            $matrix = @"
# Activation Matrix

| ID | Prompt | Should Trigger | Actual Trigger | Failure Type | Notes |
|---|---|---|---|---|---|
| pos-01 | prompt A | yes | yes | pass | |
| pos-02 | prompt B | yes | yes | pass | |
| pos-03 | prompt C | yes | yes | pass | |
| neg-01 | prompt D | no | no | pass | |
"@
            Set-Content -Path (Join-Path $tempDir 'activation-matrix.md') -Value $matrix

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir 2>&1
            $json = $result | ConvertFrom-Json
            $json.warnings.Count | Should -BeGreaterThan 0
        }

        It 'Exits with code 1 when accuracy is below threshold' {
            $matrix = @"
# Activation Matrix

| ID | Prompt | Should Trigger | Actual Trigger | Failure Type | Notes |
|---|---|---|---|---|---|
| pos-01 | prompt A | yes | no | false_negative | |
| pos-02 | prompt B | yes | no | false_negative | |
| neg-01 | prompt C | no | no | pass | |
| neg-02 | prompt D | no | no | pass | |
"@
            Set-Content -Path (Join-Path $tempDir 'activation-matrix.md') -Value $matrix

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir -Threshold 80 2>&1
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'Output structure' {

        It 'Outputs JSON with audit_type field' {
            $tempDir = Join-Path $TestDrive "skill-$(Get-Random)"
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

            $matrix = @"
# Activation Matrix

| ID | Prompt | Should Trigger | Actual Trigger | Failure Type | Notes |
|---|---|---|---|---|---|
| pos-01 | prompt A | yes | yes | pass | |
| neg-01 | prompt B | no | no | pass | |
"@
            Set-Content -Path (Join-Path $tempDir 'activation-matrix.md') -Value $matrix

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir 2>&1
            $json = $result | ConvertFrom-Json
            $json.audit_type | Should -Be 'activation'
        }
    }
}
