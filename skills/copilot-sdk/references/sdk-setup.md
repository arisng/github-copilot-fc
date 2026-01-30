# SDK Installation & Setup

Quick install commands and platform-specific setup notes for GitHub Copilot CLI SDKs.

## Prerequisites

- GitHub Copilot CLI must be installed (`copilot --version` to verify)
- Language runtime installed (Node.js 18+, Python 3.8+, Go 1.18+, .NET 6.0+)

## Installation by Language

### Node.js / TypeScript

```bash
npm install @github/copilot-sdk
```

**Optional: Install Zod for type-safe schemas**
```bash
npm install zod
```

**Verify installation**
```bash
npm list @github/copilot-sdk
```

### Python

```bash
pip install github-copilot-sdk
```

**Optional: Install Pydantic for type-safe schemas**
```bash
pip install pydantic
```

**Verify installation**
```bash
pip show github-copilot-sdk
```

### Go

```bash
go get github.com/github/copilot-sdk/go
```

**In go.mod:**
```
require github.com/github/copilot-sdk/go vX.Y.Z
```

**Verify installation**
```bash
go list github.com/github/copilot-sdk/go
```

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
- If not found, add to PATH or specify `cliPath` in client options

### Windows

- SDK works with PowerShell and CMD
- Ensure Copilot CLI executable is accessible (add to PATH or specify `cliPath`)
- Use forward slashes in file paths for cross-platform compatibility

### Linux

- Requires Copilot CLI built for Linux
- Verify architecture: `uname -m`
- Add execute permission: `chmod +x /path/to/copilot`

## Verifying Setup

### TypeScript

```typescript
import { CopilotClient } from "@github/copilot-sdk";
const client = new CopilotClient();
await client.start();
console.log(client.getState()); // Should print "connected"
await client.stop();
```

### Python

```python
from copilot import CopilotClient
async def main():
    client = CopilotClient()
    await client.start()
    print(client.get_state())  # Should print "connected"
    await client.stop()
import asyncio
asyncio.run(main())
```

### Go

```go
package main
import (
    "fmt"
    copilot "github.com/github/copilot-sdk/go"
)
func main() {
    client := copilot.NewClient(nil)
    client.Start()
    fmt.Println(client.GetState())  // Should print "connected"
    client.Stop()
}
```

### .NET

```csharp
using GitHub.Copilot.SDK;
var client = new CopilotClient();
await client.StartAsync();
Console.WriteLine(client.State);  // Should print "connected"
await client.StopAsync();
```

## Environment Variables

### Required

- None (SDK auto-detects Copilot CLI)

### Optional

- `COPILOT_CLI_PATH`: Custom path to Copilot CLI binary
- `COPILOT_LOG_LEVEL`: SDK logging level (debug, info, warning, error)

## Troubleshooting Installation

| Issue                             | Solution                                                                 |
| --------------------------------- | ------------------------------------------------------------------------ |
| "Module not found"                | Run install command again; verify package manager (npm, pip, go, dotnet) |
| "CLI server not found"            | Verify Copilot CLI installed; specify `cliPath` in client options        |
| "Permission denied" (Linux/macOS) | Add execute permission: `chmod +x /path/to/copilot`                      |
| "EADDRINUSE"                      | Another process using port; use different port or reset CLI server       |

## Version Management

### Check SDK Version

**TypeScript:** `npm list @github/copilot-sdk`
**Python:** `pip show github-copilot-sdk`
**Go:** `go list -m github.com/github/copilot-sdk/go`
**.NET:** `dotnet package search GitHub.Copilot.SDK`

### Update SDK

**TypeScript:** `npm update @github/copilot-sdk`
**Python:** `pip install --upgrade github-copilot-sdk`
**Go:** `go get -u github.com/github/copilot-sdk/go`
**.NET:** `dotnet package update GitHub.Copilot.SDK`
