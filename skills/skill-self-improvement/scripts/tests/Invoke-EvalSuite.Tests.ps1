<#
.SYNOPSIS
    Pester tests for Invoke-EvalSuite.ps1
#>

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..' | Join-Path -ChildPath 'Invoke-EvalSuite.ps1'
}

Describe 'Invoke-EvalSuite.ps1' {

    Context 'Path validation' {

        It 'Exits with code 2 when SkillDir does not exist' {
            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir 'C:\nonexistent-path-12345' 2>&1
            $LASTEXITCODE | Should -Be 2
        }

        It 'Exits with code 2 when eval.json is missing' {
            $tempDir = Join-Path $TestDrive "skill-$(Get-Random)"
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir 2>&1
            $LASTEXITCODE | Should -Be 2
        }
    }

    Context 'Expression syntax only mode' {

        BeforeEach {
            $tempDir = Join-Path $TestDrive "skill-$(Get-Random)"
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

            $evalDir = Join-Path $tempDir 'evals'
            New-Item -Path $evalDir -ItemType Directory -Force | Out-Null
        }

        It 'Reports parseable expressions in syntax-only mode' {
            $evalJson = @"
{
    "skill": "test",
    "objective": "test",
    "cases": [{
        "id": "case-01",
        "prompt": "test",
        "expected_trigger": true,
        "assertions": [
            {"id": "A1", "type": "structural", "description": "word count", "passes_when": "word_count < 150"},
            {"id": "A2", "type": "formatting", "description": "contains", "passes_when": "contains(\"hello\")"}
        ]
    }]
}
"@
            Set-Content -Path (Join-Path $evalDir 'eval.json') -Value $evalJson

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir -ExpressionSyntaxOnly 2>&1
            $json = $result | ConvertFrom-Json
            $json.mode | Should -Be 'syntax_only'
            $json.passed | Should -Be 2
            $json.cases[0].assertions[0].status | Should -Be 'parseable'
        }

        It 'Reports skipped for unparseable expressions' {
            $evalJson = @"
{
    "skill": "test",
    "objective": "test",
    "cases": [{
        "id": "case-01",
        "prompt": "test",
        "expected_trigger": true,
        "assertions": [
            {"id": "A1", "type": "semantic", "description": "vague", "passes_when": "is engaging and fun"}
        ]
    }]
}
"@
            Set-Content -Path (Join-Path $evalDir 'eval.json') -Value $evalJson

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir -ExpressionSyntaxOnly 2>&1
            $json = $result | ConvertFrom-Json
            $json.skipped | Should -Be 1
        }
    }

    Context 'Full evaluation mode' {

        BeforeEach {
            $tempDir = Join-Path $TestDrive "skill-$(Get-Random)"
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

            $evalDir = Join-Path $tempDir 'evals'
            New-Item -Path $evalDir -ItemType Directory -Force | Out-Null
            $samplesDir = Join-Path $evalDir 'samples'
            New-Item -Path $samplesDir -ItemType Directory -Force | Out-Null
        }

        It 'Evaluates word_count assertion correctly' {
            $evalJson = @"
{
    "skill": "test",
    "objective": "test",
    "cases": [{
        "id": "case-01",
        "prompt": "test",
        "expected_trigger": true,
        "assertions": [
            {"id": "A1", "type": "structural", "description": "word count under 10", "passes_when": "word_count < 10"}
        ]
    }]
}
"@
            Set-Content -Path (Join-Path $evalDir 'eval.json') -Value $evalJson
            Set-Content -Path (Join-Path $samplesDir 'case-01.md') -Value 'Hello world'

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir -OutputSamplesDir $samplesDir 2>&1
            $json = $result | ConvertFrom-Json
            $json.cases[0].assertions[0].status | Should -Be 'pass'
        }

        It 'Fails when word_count exceeds threshold' {
            $evalJson = @"
{
    "skill": "test",
    "objective": "test",
    "cases": [{
        "id": "case-01",
        "prompt": "test",
        "expected_trigger": true,
        "assertions": [
            {"id": "A1", "type": "structural", "description": "word count under 3", "passes_when": "word_count < 3"}
        ]
    }]
}
"@
            Set-Content -Path (Join-Path $evalDir 'eval.json') -Value $evalJson
            Set-Content -Path (Join-Path $samplesDir 'case-01.md') -Value 'Hello world this is more than three words'

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir -OutputSamplesDir $samplesDir 2>&1
            $json = $result | ConvertFrom-Json
            $json.cases[0].assertions[0].status | Should -Be 'fail'
        }

        It 'Reports error when output sample is missing' {
            $evalJson = @"
{
    "skill": "test",
    "objective": "test",
    "cases": [{
        "id": "case-01",
        "prompt": "test",
        "expected_trigger": true,
        "assertions": [
            {"id": "A1", "type": "structural", "description": "word count", "passes_when": "word_count < 100"}
        ]
    }]
}
"@
            Set-Content -Path (Join-Path $evalDir 'eval.json') -Value $evalJson
            # No sample file created

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir -OutputSamplesDir $samplesDir 2>&1
            $json = $result | ConvertFrom-Json
            $json.cases[0].assertions[0].status | Should -Be 'error'
        }

        It 'Evaluates contains() assertion correctly' {
            $evalJson = @"
{
    "skill": "test",
    "objective": "test",
    "cases": [{
        "id": "case-01",
        "prompt": "test",
        "expected_trigger": true,
        "assertions": [
            {"id": "A1", "type": "coverage", "description": "must contain hello", "passes_when": "contains(\"hello\")"}
        ]
    }]
}
"@
            Set-Content -Path (Join-Path $evalDir 'eval.json') -Value $evalJson
            Set-Content -Path (Join-Path $samplesDir 'case-01.md') -Value 'Say hello to the world'

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir -OutputSamplesDir $samplesDir 2>&1
            $json = $result | ConvertFrom-Json
            $json.cases[0].assertions[0].status | Should -Be 'pass'
        }

        It 'Evaluates section_present() correctly' {
            $evalJson = @"
{
    "skill": "test",
    "objective": "test",
    "cases": [{
        "id": "case-01",
        "prompt": "test",
        "expected_trigger": true,
        "assertions": [
            {"id": "A1", "type": "structural", "description": "has Installation section", "passes_when": "section_present(\"Installation\")"}
        ]
    }]
}
"@
            Set-Content -Path (Join-Path $evalDir 'eval.json') -Value $evalJson
            Set-Content -Path (Join-Path $samplesDir 'case-01.md') -Value "## Installation`n`nFollow these steps."

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir -OutputSamplesDir $samplesDir 2>&1
            $json = $result | ConvertFrom-Json
            $json.cases[0].assertions[0].status | Should -Be 'pass'
        }
    }

    Context 'Output structure' {

        It 'Outputs JSON with audit_type field' {
            $tempDir = Join-Path $TestDrive "skill-$(Get-Random)"
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

            $evalDir = Join-Path $tempDir 'evals'
            New-Item -Path $evalDir -ItemType Directory -Force | Out-Null
            $evalJson = @"
{
    "skill": "test",
    "objective": "test",
    "cases": []
}
"@
            Set-Content -Path (Join-Path $evalDir 'eval.json') -Value $evalJson

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir -ExpressionSyntaxOnly 2>&1
            $json = $result | ConvertFrom-Json
            $json.audit_type | Should -Be 'execution'
        }
    }
}
