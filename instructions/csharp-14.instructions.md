---
description: 'Guidelines for developing applications with C# 14 on .NET 10.0, including modern project structures like .slnx files'
applyTo: '**/*.cs, **/*.csproj, **/*.slnx, **/*.sln'
---

# C# 14 (.NET 10.0) Development Guidelines

## Overview

This guide provides best practices for developing applications using C# 14 on the .NET 10.0 SDK, incorporating new language features and modern project structures like .slnx solution files. It ensures code is efficient, maintainable, and leverages the latest language capabilities.

## Workflow

1. **Project Setup**: Use .slnx for solution files in C# projects targeting .NET 10.0 for better mergeability and readability.
2. **Feature Adoption**: Incorporate C# 14 features like extension members and field keyword where appropriate.
3. **Performance Optimization**: Utilize C# 14's language features for improved code clarity and performance on .NET 10.0.
4. **Testing and Validation**: Run comprehensive tests to verify new features work as expected.

## Rules & Constraints

- Target the **.NET 10.0** SDK (specifically `net10.0` TFM) for new projects to access LTS support until November 2028.
- Use .slnx format for solution files; avoid legacy .sln where possible.
- Implement C# 14 features only where they improve code clarity and performance.
- Ensure compatibility with Visual Studio 2026, VS Code C# Dev Kit, and Rider.
- Follow semantic versioning for packages targeting .NET 10.

## Best Practices

- **Performance**: Leverage C# 14 features for reduced boilerplate and improved readability.
- **Maintainability**: Use new syntax to make code more expressive and easier to understand.

## Code Standards

### Naming Conventions
- Follow existing C# naming conventions (PascalCase for types, camelCase for locals).
- Use descriptive names for extension members and partial constructors.

### File Organization
- Place .slnx files at the solution root.
- Organize projects logically within the solution structure.

### Error Handling
- Use enhanced diagnostics in .NET 10 for better error reporting.
- Implement proper exception handling for new APIs.

## Common Patterns

### Using Extension Members (C# 14)
```csharp
public static class StringExtensions
{
    public static bool IsNullOrWhiteSpace(this string value)
    {
        return string.IsNullOrWhiteSpace(value);
    }
}

// Usage
string input = "  ";
if (input.IsNullOrWhiteSpace())
{
    Console.WriteLine("Input is empty or whitespace.");
}
```

### Field Keyword in Properties (C# 14)
```csharp
public class Person
{
    private string _name;

    public string Name
    {
        get => field; // Direct access to backing field
        set => field = value?.Trim();
    }
}
```

### Null-Conditional Assignment (C# 14)
```csharp
Dictionary<string, int> counts = new();
string key = "example";

// Safe assignment
counts[key] ??= 0;
counts[key]++;
```

### .slnx Solution File Structure
```xml
<?xml version="1.0" encoding="utf-8"?>
<Solution xmlns="http://schemas.microsoft.com/vs/2022/solution">
  <Project Path="src/MyApp/MyApp.csproj" />
  <Project Path="tests/MyApp.Tests/MyApp.Tests.csproj" />
</Solution>
```

## Validation

- **Build**: Run `dotnet build` to ensure compatibility with .NET 10.0 SDK.
- **Test**: Execute `dotnet test` to verify unit tests pass with new features.
- **Lint**: Use Roslyn analyzers for code quality checks.
- **Compatibility**: Test on target platforms including Windows, Linux, and macOS.

## Notes on globs

This guidance applies to C# files, project files, and .slnx solutions targeting .NET 10.0 to ensure comprehensive coverage.

## References

- [C# 14 Language Features](https://learn.microsoft.com/dotnet/csharp/whats-new/csharp-14) - C# 14 specifications
- [.slnx Solution Files](https://learn.microsoft.com/visualstudio/extensibility/internals/solution-dot-slnx-file) - .slnx format documentation