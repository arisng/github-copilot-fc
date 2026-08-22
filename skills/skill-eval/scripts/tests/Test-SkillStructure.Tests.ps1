<#
.SYNOPSIS
    Pester tests for Test-SkillStructure.ps1
#>

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..' | Join-Path -ChildPath 'Test-SkillStructure.ps1'
}

Describe 'Test-SkillStructure.ps1' {

    Context 'Path validation' {

        It 'Exits with code 2 when SkillDir does not exist' {
            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir 'C:\nonexistent-path-12345' 2>&1
            $LASTEXITCODE | Should -Be 2
        }

        It 'Exits with code 1 when SKILL.md is missing' {
            $tempDir = Join-Path $TestDrive 'no-skillmd'
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir 2>&1
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'SKILL.md frontmatter validation' {

        BeforeEach {
            $tempDir = Join-Path $TestDrive "skill-$(Get-Random)"
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
        }

        It 'Passes when SKILL.md has valid frontmatter with name and description' {
            $skillMd = @"
---
name: test-skill
description: A test skill for validation
---

# Test Skill

Body content here.
"@
            Set-Content -Path (Join-Path $tempDir 'SKILL.md') -Value $skillMd

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir 2>&1
            $json = $result | ConvertFrom-Json
            $json.compliant | Should -BeTrue
            $json.errors | Should -BeNullOrEmpty
        }

        It 'Fails when description exceeds 1024 characters' {
            $longDesc = 'x' * 1025
            $skillMd = @"
---
name: test-skill
description: $longDesc
---

# Test Skill
"@
            Set-Content -Path (Join-Path $tempDir 'SKILL.md') -Value $skillMd

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir 2>&1
            $json = $result | ConvertFrom-Json
            $json.compliant | Should -BeFalse
            $json.errors | Should -Contain ($json.errors | Where-Object { $_ -match '1024' })
        }

        It 'Fails when frontmatter is missing' {
            $skillMd = @"
# Test Skill

Body content without frontmatter.
"@
            Set-Content -Path (Join-Path $tempDir 'SKILL.md') -Value $skillMd

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir 2>&1
            $LASTEXITCODE | Should -Be 1
        }

        It 'Fails when name field is missing' {
            $skillMd = @"
---
description: A skill without a name
---

# Test Skill
"@
            Set-Content -Path (Join-Path $tempDir 'SKILL.md') -Value $skillMd

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir 2>&1
            $json = $result | ConvertFrom-Json
            $json.errors | Should -Contain ($json.errors | Where-Object { $_ -match 'name' })
        }
    }

    Context 'eval.json validation' {

        BeforeEach {
            $tempDir = Join-Path $TestDrive "skill-$(Get-Random)"
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

            $skillMd = @"
---
name: test-skill
description: A test skill
---

# Test Skill
"@
            Set-Content -Path (Join-Path $tempDir 'SKILL.md') -Value $skillMd
        }

        It 'Warns when evals/eval.json does not exist' {
            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir 2>&1
            $json = $result | ConvertFrom-Json
            $json.warnings | Should -Contain ($json.warnings | Where-Object { $_ -match 'eval.json' })
        }

        It 'Fails when eval.json has invalid JSON' {
            $evalDir = Join-Path $tempDir 'evals'
            New-Item -Path $evalDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $evalDir 'eval.json') -Value '{ invalid json }'

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir 2>&1
            $LASTEXITCODE | Should -Be 1
        }

        It 'Fails when eval.json has empty cases array' {
            $evalDir = Join-Path $tempDir 'evals'
            New-Item -Path $evalDir -ItemType Directory -Force | Out-Null
            $evalJson = @{ skill = 'test'; objective = 'test'; cases = @() } | ConvertTo-Json -Depth 5
            Set-Content -Path (Join-Path $evalDir 'eval.json') -Value $evalJson

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir 2>&1
            $LASTEXITCODE | Should -Be 1
        }

        It 'Fails when assertion has invalid type' {
            $evalDir = Join-Path $tempDir 'evals'
            New-Item -Path $evalDir -ItemType Directory -Force | Out-Null
            $evalJson = @"
{
    "skill": "test",
    "objective": "test",
    "cases": [{
        "id": "case-01",
        "prompt": "test prompt",
        "expected_trigger": true,
        "assertions": [{
            "id": "A1",
            "type": "invalid_type",
            "description": "test",
            "passes_when": "word_count < 100"
        }]
    }]
}
"@
            Set-Content -Path (Join-Path $evalDir 'eval.json') -Value $evalJson

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir 2>&1
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'Report output structure' {

        It 'Outputs JSON with audit_type field' {
            $tempDir = Join-Path $TestDrive "skill-$(Get-Random)"
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

            $skillMd = @"
---
name: test-skill
description: A test skill
---

# Test Skill
"@
            Set-Content -Path (Join-Path $tempDir 'SKILL.md') -Value $skillMd

            $result = & pwsh -NoProfile -File $script:ScriptPath -SkillDir $tempDir 2>&1
            $json = $result | ConvertFrom-Json
            $json.audit_type | Should -Be 'structural'
        }
    }
}
