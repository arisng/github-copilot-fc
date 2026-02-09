# SDK Installation & Setup (.NET)

Quick install commands and platform-specific setup notes for GitHub Copilot CLI SDK (.NET).

## Prerequisites

- GitHub Copilot CLI must be installed (`copilot --version` to verify)
- .NET 6.0+ SDK installed

## Installation

### .NET

```bash
dotnet add package GitHub.Copilot.SDK
```

**Optional: Install Microsoft.Extensions.AI for AIFunctionFactory**
```bash
dotnet add package Microsoft.Extensions.AI
```

**Verify installation**
```bash
dotnet package search GitHub.Copilot.SDK
```

## Platform-Specific Notes

### macOS

- Ensure Copilot CLI is in PATH: `which copilot`
- If not found, add to PATH or specify `CliPath` in client options

### Windows

- SDK works with PowerShell and CMD
- Ensure Copilot CLI executable is accessible
- Use forward slashes in file paths for cross-platform compatibility where possible

### Linux

- Requires Copilot CLI built for Linux
- Verify architecture: `uname -m`

## Verifying Setup

### .NET

```csharp
using GitHub.Copilot.SDK;
using System;

var client = new CopilotClient();
Console.WriteLine($"State: {client.State}");
```
