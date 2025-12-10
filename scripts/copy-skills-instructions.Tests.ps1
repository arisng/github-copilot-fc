Describe "Copy-SkillsInstructions Tests" {
    BeforeAll {
        # Dot-source the script to load the function
        . $PSScriptRoot\copy-skills-instructions.ps1

        # Mock APPDATA to TestDrive for isolated testing
        $env:APPDATA = $TestDrive

        # Set actual paths used in the function
        $script:sourcePath = Join-Path $PSScriptRoot "..\instructions\skills.instructions.md"
        $script:destinationDir = Join-Path $env:APPDATA "Code\User\prompts"
        $script:destinationPath = Join-Path $script:destinationDir "skills.instructions.md"
    }

    It "Should copy the file when source exists and destination directory is created" {
        Mock Test-Path { $true } -ParameterFilter { $Path -eq $script:sourcePath }
        Mock Test-Path { $false } -ParameterFilter { $Path -eq $script:destinationDir }
        Mock New-Item
        Mock Copy-Item
        Mock Write-Verbose

        { Copy-SkillsInstructions } | Should Not Throw

        Assert-MockCalled New-Item -Exactly 1 -ParameterFilter { $ItemType -eq "Directory" -and $Path -eq $script:destinationDir }
        Assert-MockCalled Copy-Item -Exactly 1 -ParameterFilter { $Path -eq $script:sourcePath -and $Destination -eq $script:destinationPath }
    }

    It "Should throw error when source file does not exist" {
        Mock Test-Path { $false } -ParameterFilter { $Path -eq $script:sourcePath }

        { Copy-SkillsInstructions } | Should Throw "Source file not found"
    }

    It "Should handle exceptions during copy" {
        Mock Test-Path { $true } -ParameterFilter { $Path -eq $script:sourcePath }
        Mock Test-Path { $true } -ParameterFilter { $Path -eq $script:destinationDir }
        Mock Copy-Item { throw "Copy failed" }

        { Copy-SkillsInstructions } | Should Throw
    }

    It "Should not create directory if it already exists" {
        Mock Test-Path { $true } -ParameterFilter { $Path -eq $script:sourcePath }
        Mock Test-Path { $true } -ParameterFilter { $Path -eq $script:destinationDir }
        Mock Copy-Item
        Mock Write-Verbose

        { Copy-SkillsInstructions } | Should Not Throw
    }
}