# Mental Model: GitHub Copilot SDK Communication with CLI in ACP Server Mode

Based on the Copilot SDK documentation and examples, here's how to conceptualize the SDK's interaction with the CLI in `--acp` (Agent Client Protocol) server mode. I'll break it down step-by-step, then highlight specific use cases with code examples.

## Core Architecture

- **CLI as Server**: When you run `copilot --acp`, the CLI becomes a JSON-RPC server (over stdio or TCP) that exposes Copilot's AI agent capabilities. It handles authentication, model management, session isolation, and tool execution.
- **SDK as Client**: The SDK (available in Node.js/TypeScript, Python, Go, .NET) is a client library that connects to this server. It manages the connection lifecycle and provides a programmatic API for your application.
- **Session-Based Interaction**: The SDK creates "sessions" (isolated conversation contexts) with custom configurations. Each session can send prompts, receive streaming responses, and execute tools/MCP integrations.
- **Default Behavior**: The SDK auto-starts/stops the CLI process, but you can connect to a pre-running `--acp` server for better control (e.g., shared server across multiple apps).

## Communication Flow

1. **Connection**: SDK client establishes JSON-RPC connection to CLI server.
2. **Session Creation**: SDK sends configuration (model, MCP servers, custom agents, tools, permissions).
3. **Prompt Execution**: SDK sends user prompts; CLI processes via AI model and returns responses/tools.
4. **Tool Handling**: CLI executes approved tools (file ops, Git, web requests) and streams results back.
5. **Streaming/Events**: Real-time response streaming and event handling for interactive experiences.

## Key Features Enabled by ACP Mode

- **MCP Server Integration**: Connect to local/remote MCP servers for extended data sources (e.g., filesystem, APIs).
- **Custom Agents**: Define specialized AI personas with custom prompts, tool restrictions, and MCP access.
- **Tool Customization**: Fine-grained control over available tools (e.g., allow/deny specific operations).
- **Bring-Your-Own-Key (BYOK)**: Use custom AI providers/models.
- **Permission Handling**: Configurable approval flows for tool execution.

## Specific Use Cases with Examples

### 1. Integrating MCP Servers for Extended Capabilities  

Use case: Build an app that combines Copilot's AI with external data sources (e.g., filesystem access or remote APIs) for tasks like automated code analysis or documentation generation.

*Python Example* (from SDK docs):
```python
from copilot import CopilotClient

async def main():
    client = CopilotClient()
    await client.start()

    # Create session with MCP servers
    session = await client.create_session({
        "model": "gpt-5",
        "mcp_servers": {
            "filesystem": {
                "type": "local",
                "command": "npx",
                "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path"],
                "tools": "*",  # All filesystem tools
            },
            "remote-api": {
                "type": "http",
                "url": "https://api.example.com/mcp",
                "tools": ["search"],
                "headers": {"Authorization": "Bearer token"},
            },
        },
    })

    # Send prompt leveraging MCP tools
    result = await session.send_and_wait({
        "prompt": "Analyze the codebase in /path and search for API usage patterns"
    })
    print(result.data.content)

    await session.destroy()
    await client.stop()
```

### 2. Custom Agents for Specialized Workflows  

Use case: Create domain-specific AI assistants (e.g., security reviewer, documentation writer) integrated into your app, with restricted tool access and custom prompts.

*TypeScript Example*:
```typescript
import { CopilotClient } from "@github/copilot-sdk";

const client = new CopilotClient();
await client.start();

const session = await client.createSession({
    model: "gpt-5",
    customAgents: [
        {
            name: "security-reviewer",
            displayName: "Security Reviewer",
            description: "Reviews code for vulnerabilities",
            prompt: `You are a security expert. Identify vulnerabilities and suggest fixes following OWASP guidelines.`,
            tools: ["Read", "Grep"],  // Limited tools
            mcpServers: {
                "security-db": {
                    type: "http",
                    url: "https://security-mcp.example.com",
                    tools: ["query-vulnerabilities"],
                },
            },
        },
    ],
});

// Use the agent
const result = await session.sendAndWait({
    prompt: "@security-reviewer Review src/auth.ts for vulnerabilities",
});
console.log(result.data.content);

await session.destroy();
await client.stop();
```

### 3. Building Custom IDEs or Web Apps  

Use case: Embed Copilot into your own editor/IDE or web application for AI-assisted coding, refactoring, or task automation. The SDK handles the heavy lifting of session management and tool execution.

*Node.js Example* (web app integration):
```typescript
// In a web server
import { CopilotClient } from "@github/copilot-sdk";

const client = new CopilotClient();
await client.start();

// API endpoint for AI assistance
app.post('/ai-assist', async (req, res) => {
    const session = await client.createSession({
        model: "gpt-5",
        mcpServers: { /* filesystem, git, etc. */ },
    });

    const result = await session.sendAndWait({
        prompt: req.body.prompt,  // e.g., "Refactor this function"
    });

    res.json({ response: result.data.content });
    await session.destroy();
});
```

### 4. Automation and CI/CD Integration  

Use case: Automate code reviews, testing, or deployment tasks in scripts or CI pipelines, connecting to a shared CLI server for efficiency.

*Python Example* (CI script):
```python
# Connect to pre-running CLI server
client = CopilotClient(server_url="tcp://localhost:8080")  # External --acp server
await client.start()

session = await client.create_session({
    "customAgents": [{"name": "ci-agent", "tools": ["Run", "Git"]}],
})

# Automated PR review
result = await session.send_and_wait({
    "prompt": "@ci-agent Review PR #123 for code quality and run tests",
})
print(f"Review: {result.data.content}")

await client.stop()
```

## Why ACP Mode Matters

- **Programmatic Access**: Turns interactive CLI into an embeddable service for apps/tools.
- **Scalability**: Shared server instances for multiple clients (e.g., in enterprise setups).
- **Extensibility**: MCP servers and custom agents enable domain-specific AI workflows.
- **Security/Control**: Fine-grained permissions prevent unauthorized actions in integrated apps.

This setup essentially makes Copilot's agent capabilities a programmable API, enabling AI-powered features in any application. For full docs, check the [GitHub Copilot SDK repo](https://github.com/github/copilot-sdk). If you want to explore a specific language SDK or use case in more depth, let me know!