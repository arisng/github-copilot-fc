# MCP Server Integration

Comprehensive guide to Model Context Protocol (MCP) server setup, patterns, and debugging.

## What is MCP?

Model Context Protocol (MCP) enables language models to interact with external tools and data sources via standardized server interfaces. MCP servers expose "tools" that the assistant can invoke.

### MCP vs Custom Tools

| Aspect         | Custom Tools                              | MCP Servers                             |
| -------------- | ----------------------------------------- | --------------------------------------- |
| **Definition** | Tools defined in session config           | External processes exposing tools       |
| **Execution**  | Runs in-process (handler code in session) | Runs in separate process/service        |
| **Language**   | Same as SDK application                   | Any language (separate executable)      |
| **Use Case**   | Simple operations, SDK-native logic       | Complex tools, third-party integrations |

---

## Local (Stdio) MCP Servers

### Setup Pattern

```typescript
const session = await client.createSession({
    mcpServers: {
        "filesystem": {
            type: "local",  // or "stdio"
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/allowed"],
            tools: "*",  // Include all tools
            timeout: 30000,
            env: { "CUSTOM_VAR": "value" },
            cwd: "/working/directory"
        }
    }
});
```

### Key Parameters

- **`command`**: Executable name or full path
  - Examples: `"npx"`, `"/usr/local/bin/python3"`, `"./scripts/mcp-server.sh"`
  
- **`args`**: Command arguments passed to executable
  - Example: `["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]`
  
- **`tools`**: Tool filter
  - `"*"` = all tools exposed by server
  - `["tool1", "tool2"]` = whitelist specific tools
  
- **`timeout`**: Milliseconds to wait for tool response (default: 30000)
  
- **`env`**: Environment variables inherited by process
  
- **`cwd`**: Working directory for process startup

### Built-In MCP Servers

#### Filesystem Server

```typescript
"filesystem": {
    type: "local",
    command: "npx",
    args: ["-y", "@modelcontextprotocol/server-filesystem", "/allowed/path"],
    tools: ["read_file", "write_file", "list_directory"]
}
```

**Available tools:** `read_file`, `write_file`, `list_directory`, `move_file`, `delete_file`

#### Postgres Server

```typescript
"postgres": {
    type: "local",
    command: "npx",
    args: ["-y", "@modelcontextprotocol/server-postgres"],
    tools: "*",
    env: {
        "PG_CONNECTION_STRING": "postgresql://user:pass@localhost/db"
    }
}
```

#### Git Server

```typescript
"git": {
    type: "local",
    command: "npx",
    args: ["-y", "@modelcontextprotocol/server-git", "/repo/path"],
    tools: "*"
}
```

---

## Remote (HTTP) MCP Servers

### Setup Pattern

```typescript
const session = await client.createSession({
    mcpServers: {
        "remote-api": {
            type: "http",
            url: "https://api.example.com/mcp",
            tools: ["search", "fetch"],
            headers: {
                "Authorization": "Bearer YOUR_API_KEY",
                "X-Custom-Header": "value"
            }
        }
    }
});
```

### Key Parameters

- **`url`**: Full HTTPS URL to MCP endpoint
  - Example: `"https://mcp-server.example.com/mcp"`
  
- **`tools`**: Tool filter (same as stdio)
  
- **`headers`**: Custom HTTP headers (auth, custom metadata)

### HTTP Server Example

```typescript
const session = await client.createSession({
    mcpServers: {
        "github-search": {
            type: "http",
            url: "https://github-mcp-server.herokuapp.com/mcp",
            tools: ["search_repositories", "search_code"],
            headers: {
                "Authorization": "Bearer ghp_YOUR_GITHUB_TOKEN"
            }
        }
    }
});

await session.sendAndWait({
    prompt: "Find repositories related to machine learning in JavaScript"
});
```

---

## Remote (SSE) MCP Servers

### Setup Pattern

```typescript
const session = await client.createSession({
    mcpServers: {
        "sse-server": {
            type: "sse",
            url: "https://sse-server.example.com/events",
            tools: "*"
        }
    }
});
```

### When to Use SSE

- Server requires persistent connection
- Real-time streaming of results
- Server-initiated events

---

## Multiple MCP Servers

### Combining Servers

```typescript
const session = await client.createSession({
    mcpServers: {
        "filesystem": {
            type: "local",
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
            tools: "*"
        },
        "postgres": {
            type: "local",
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-postgres"],
            tools: "*",
            env: { "PG_CONNECTION_STRING": "postgresql://..." }
        },
        "external-api": {
            type: "http",
            url: "https://api.example.com/mcp",
            tools: ["query"]
        }
    }
});

// Assistant can now use tools from all three servers
await session.sendAndWait({
    prompt: "Query the database, save results to /tmp/results.json, then upload to external API"
});
```

---

## Debugging MCP Servers

### Enable Debug Logging

```typescript
const client = new CopilotClient({
    logLevel: "debug"  // Shows MCP server startup and tool invocations
});
```

### Common Issues

| Issue                    | Diagnosis                         | Solution                                                         |
| ------------------------ | --------------------------------- | ---------------------------------------------------------------- |
| "MCP server unavailable" | Server not running or unreachable | Verify server is running; check port/URL                         |
| "Tool not found"         | Tool name doesn't exist on server | Check server's tool list; verify tool name                       |
| "Timeout"                | Tool took longer than timeout     | Increase timeout parameter (default: 30000ms)                    |
| "Permission denied"      | Server lacks permissions          | Check environment variables, working directory, file permissions |
| "Connection refused"     | HTTP/TCP connection failed        | Verify server URL is correct and accessible                      |

### Manual Testing

**Test local stdio server:**
```bash
npx @modelcontextprotocol/server-filesystem /tmp
# Type: {"jsonrpc": "2.0", "id": 1, "method": "list_resources", "params": {}}
# Press Enter to see response
```

**Test HTTP server:**
```bash
curl -X POST https://api.example.com/mcp \
  -H "Authorization: Bearer token" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "id": 1, "method": "list_tools", "params": {}}'
```

### Session Event Monitoring

```typescript
session.on((event) => {
    if (event.type === "tool.execution_start") {
        console.log(`MCP tool invoked: ${event.data.toolName}`);
    }
    if (event.type === "tool.execution_end") {
        console.log(`MCP tool completed: ${event.data.toolName}`);
    }
    if (event.type === "session.error") {
        console.error(`Session error: ${event.data.message}`);
    }
});
```

---

## Security Considerations

### Filesystem Server

Restrict to specific directories:
```typescript
"filesystem": {
    type: "local",
    command: "npx",
    args: ["-y", "@modelcontextprotocol/server-filesystem", "/safe/directory"],
    tools: ["read_file"]  // Read-only, no writes
}
```

### Database Server

Use connection strings with minimal privileges:
```typescript
env: {
    "PG_CONNECTION_STRING": "postgresql://readonly_user:pass@localhost/db"
}
```

### HTTP Server

Always use HTTPS and token-based auth:
```typescript
"api": {
    type: "http",
    url: "https://secure-api.example.com/mcp",  // HTTPS required
    headers: {
        "Authorization": "Bearer API_KEY"  // Use env vars in real code
    }
}
```

---

## Performance Optimization

### Selective Tool Access

Only expose tools the assistant needs:
```typescript
tools: ["read_file", "write_file"]  // Not "*"
```

### Timeout Configuration

Balance responsiveness vs. long operations:
```typescript
timeout: 60000  // 60 seconds for longer operations
```

### Caching Strategies

For HTTP servers, implement server-side caching:
```typescript
headers: {
    "Cache-Control": "max-age=3600"
}
```
