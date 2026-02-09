# MCP Server Integration (.NET)

Comprehensive guide to Model Context Protocol (MCP) server setup in .NET.

## What is MCP?

Model Context Protocol (MCP) enables language models to interact with external tools and data sources via standardized server interfaces. MCP servers expose "tools" that the assistant can invoke.

---

## Local (Stdio) MCP Servers

### Setup Pattern

```csharp
using GitHub.Copilot.SDK.Mcp;

var session = await client.CreateSessionAsync(new SessionConfig {
    McpServers = new Dictionary<string, McpServerConfig> {
        ["filesystem"] = new McpLocalServerConfig {
            Type = "local", // or "stdio"
            Command = "npx",
            Args = ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/allowed"],
            Tools = "*",  // Include all tools
            Timeout = TimeSpan.FromSeconds(30),
            Env = new Dictionary<string, string> { ["CUSTOM_VAR"] = "value" },
            Cwd = "/working/directory"
        }
    }
});
```

### Key Parameters

- **`Command`**: Executable name or full path
  - Examples: `"npx"`, `"/usr/local/bin/python3"`
  
- **`Args`**: Command arguments passed to executable
  - Example: `["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]`
  
- **`Tools`**: Tool filter
  - `"*"` = all tools exposed by server
  - `["tool1", "tool2"]` = whitelist specific tools
  
- **`Timeout`**: Time to wait for tool response (default: 30s)

### Built-In MCP Servers Examples

#### Filesystem Server

```csharp
["filesystem"] = new McpLocalServerConfig {
    Type = "local",
    Command = "npx",
    Args = ["-y", "@modelcontextprotocol/server-filesystem", "/allowed/path"],
    Tools = ["read_file", "write_file"]
}
```

#### Git Server

```csharp
["git"] = new McpLocalServerConfig {
    Type = "local",
    Command = "npx",
    Args = ["-y", "@modelcontextprotocol/server-git", "/repo/path"],
    Tools = "*"
}
```

---

## Remote (HTTP) MCP Servers

### Setup Pattern

```csharp
["remote-api"] = new McpRemoteServerConfig {
    Type = "http",
    Url = "https://mcp-server.example.com/mcp",
    Tools = ["search"],
    Headers = new Dictionary<string, string> { ["Authorization"] = "Bearer token" }
}
```

---

## Remote (SSE) MCP Servers

### Setup Pattern

```csharp
["streaming-server"] = new McpRemoteServerConfig {
    Type = "sse",
    Url = "https://sse-mcp.example.com/events",
    Tools = "*"
}
```
