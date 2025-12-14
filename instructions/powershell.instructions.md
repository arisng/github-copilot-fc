---
name: powershell
description: Best practices for writing maintainable PowerShell scripts with comprehensive unit testing using Pester
applyTo: "scripts/**/*.ps1"
---

# PowerShell Script Development with Unit Testing

## Summary

This guide establishes best practices for writing PowerShell scripts that are modular, testable, and maintainable. Focus on function-based architecture, comprehensive error handling, and thorough unit testing with Pester.

## Why

PowerShell scripts in infrastructure projects need to be:
- **Reliable**: Thorough testing prevents production issues
- **Maintainable**: Modular code is easier to debug and extend
- **Secure**: Proper credential handling and validation
- **Testable**: Unit tests catch regressions early

## Conventions

### Script Structure
- Use functions for reusable logic
- Include parameter validation
- Add comprehensive error handling
- Use meaningful variable names
- Include detailed comments for complex logic

### Function Naming
- Use approved PowerShell verbs (Get-, Set-, Test-, etc.)
- Follow PascalCase naming
- Be descriptive but concise

### Error Handling
- Use try/catch blocks for external operations
- Provide meaningful error messages
- Use Write-Error for non-terminating errors
- Exit with appropriate codes for scripts

### Testing
- Write tests before or alongside code
- Aim for high test coverage
- Use descriptive test names
- Mock external dependencies

## Do / Don't

### ✅ Do
- Write modular, single-purpose functions
- Include parameter validation with [Validate*] attributes
- Use Pester for unit testing
- Mock external commands and APIs
- Handle errors gracefully
- Use .env files for sensitive configuration
- Include dry-run modes for destructive operations
- Document function parameters and return values

### ❌ Don't
- Hardcode credentials or sensitive data
- Use Write-Host for logging (use Write-Verbose/Information instead)
- Ignore error handling
- Create monolithic scripts without functions
- Skip testing because "it's just a script"
- Use unapproved verbs in function names
- Mix data and logic in the same functions

## Examples

### Good: Modular Function with Testing

```powershell
function Get-EnvironmentConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$ConfigPath
    )

    try {
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        Write-Verbose "Loaded configuration from $ConfigPath"
        return $config
    }
    catch {
        Write-Error "Failed to load config from $ConfigPath`: $_"
        throw
    }
}
```

### Good: Comprehensive Testing

```powershell
Describe "Get-EnvironmentConfig Tests" {
    BeforeAll {
        # Setup test data
        $testConfig = '{"setting": "value"}'
        $testPath = Join-Path $TestDrive "test.json"
        $testConfig | Out-File $testPath
    }

    It "Should load valid JSON config" {
        $result = Get-EnvironmentConfig -ConfigPath $testPath
        $result.setting | Should Be "value"
    }

    It "Should throw for non-existent file" {
        { Get-EnvironmentConfig -ConfigPath "nonexistent.json" } | Should Throw
    }

    It "Should validate parameter" {
        { Get-EnvironmentConfig -ConfigPath "" } | Should Throw
    }
}
```

### Good: Dry-Run Pattern

```powershell
function Set-AWSProfile {
    [CmdletBinding()]
    param(
        [string]$ProfileName,
        [string]$AccessKey,
        [switch]$DryRun
    )

    if ($DryRun) {
        Write-Host "DRY RUN: Would configure profile '$ProfileName'" -ForegroundColor Yellow
        return
    }

    # Actual implementation
    aws configure set aws_access_key_id $AccessKey --profile $ProfileName
}
```

## Testing / Run

### Running Tests
```powershell
# Run all tests in current directory
Invoke-Pester

# Run specific test file
Invoke-Pester -Path .\MyScript.Tests.ps1

# Run with verbose output
Invoke-Pester -Verbose
```

### Test Organization
- Place test files alongside scripts with `.Tests.ps1` suffix
- Use `BeforeAll`/`AfterAll` for setup/teardown
- Use `TestDrive:` for temporary test files
- Mock external dependencies

### Coverage Goals
- Aim for 80%+ code coverage
- Test happy path and error scenarios
- Include edge cases and boundary conditions

## Notes on globs

This guidance applies to PowerShell scripts in the `scripts/` directory. The glob pattern `scripts/**/*.ps1` ensures:
- All .ps1 files in scripts/ and subdirectories are covered
- Excludes generated or build files
- Allows for organized script hierarchies

## References

- [Pester Documentation](https://pester.dev/docs/introduction) - Official testing framework docs
- [PowerShell Best Practices](https://docs.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands) - Microsoft approved verbs
- [PowerShell Scripting Guidelines](https://docs.microsoft.com/en-us/powershell/scripting/developer/scripting-with-windows-powershell) - Microsoft scripting best practices
- [VS Code PowerShell Extension](https://code.visualstudio.com/docs/languages/powershell) - Development environment setup