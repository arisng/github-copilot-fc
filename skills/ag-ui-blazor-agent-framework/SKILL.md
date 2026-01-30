---
name: ag-ui-blazor-agent-framework
description: Build Blazor-native agent user interfaces using AG-UI protocol with Microsoft Agent Framework and ASP.NET Core. Use when implementing the 7 AG-UI protocol features: agentic chat, backend tools, human-in-the-loop approvals, generative UI (async tools), tool-based UI rendering, shared state, and predictive state updates. Covers ASP.NET Core MapAGUI endpoints, Agent Framework integration, Blazor component rendering, and SSE streaming architecture.
version: 1.3.0
---

# AG-UI Blazor + Agent Framework

## Quick Start

For a basic ASP.NET Core agent with Blazor frontend:

1. Install NuGet package: `Microsoft.Agents.AI.Hosting.AGUI.AspNetCore`
2. Create an `AIAgent` using `IChatClient` (Azure OpenAI, OpenAI, Ollama)
3. Map the AG-UI endpoint: `app.MapAGUI("/api/chat", agent)` in ASP.NET Core startup
4. In Blazor: Connect via HTTP POST + Server-Sent Events (SSE)
5. Parse AG-UI protocol events; render messages and tool UIs dynamically

For approval workflows, generative UI, or shared state, see full workflow below.

## The 7 AG-UI Protocol Features & Agent Framework Support

Agent Framework's AG-UI integration supports all 7 standardized protocol features:

1. **Agentic Chat** — Streaming chat with automatic tool calling (no manual parsing)
2. **Backend Tool Rendering** — Tools execute server-side via `AIFunctionFactory`; results stream to client
3. **Human-in-the-Loop** — `ApprovalRequiredAIFunction` middleware converts to approval protocol events
4. **Agentic Generative UI** — Async tools with progress updates for long-running operations
5. **Tool-Based UI Rendering** — Custom Blazor components render based on tool definitions
6. **Shared State** — Bidirectional state synchronization between agent and Blazor client
7. **Predictive State Updates** — Stream tool arguments as optimistic updates before execution

Each feature maps directly to Agent Framework abstractions: `AIAgent`, `IChatClient`, `AIFunctionFactory`, `ApprovalRequiredAIFunction`, `ConversationId`, and tool metadata serialization.

## Full Workflow

1. **Install AG-UI hosting package**
   - `dotnet add package Microsoft.Agents.AI.Hosting.AGUI.AspNetCore`
   - Includes all dependencies: Agent Framework, Extensions.AI, protocol implementation

2. **Create an AIAgent** from IChatClient
   - Wire a chat client (Azure OpenAI, OpenAI, Ollama, etc.)
   - Add tools using `AIFunctionFactory.Create()`
   - Optional: wrap with middleware for approvals or state management
   - See [mslearn-ag-ui-getting-started.md](references/mslearn-ag-ui-getting-started.md)

3. **Map the AG-UI endpoint** in ASP.NET Core
   - Use `app.MapAGUI("/api/chat", agent)` to expose agent as HTTP endpoint
   - Handles HTTP POST requests + Server-Sent Events (SSE) streaming automatically
   - Manages ConversationId for session context

4. **Implement backend tools** (optional)
   - Define tools that execute server-side: search, database queries, API calls
   - Results stream to client via AG-UI protocol
   - See [mslearn-backend-tool-rendering.md](references/mslearn-backend-tool-rendering.md)

5. **Add approval workflows** (optional)
   - Wrap functions with `ApprovalRequiredAIFunction` for sensitive actions
   - Middleware converts to human-in-the-loop protocol events
   - Client displays approval UI and sends user confirmation back

6. **Build frontend UI in Blazor**
   - Connect to HTTP endpoint + SSE stream via `HttpClient` and event parsing
   - Implement Blazor components that parse AG-UI protocol events
   - Display chat messages, tool calls, approval requests, and progress updates
   - Handle SSE streaming: append-only event stream, throttle for performance
   - See [blazor-ag-ui-genui-patterns.md](references/blazor-ag-ui-genui-patterns.md) for component patterns
   - Reference: [copilotkit-generative-ui.md](references/copilotkit-generative-ui.md) for UX/GenUI design patterns (framework-agnostic)

7. **Implement generative UI in Blazor** (optional)
   - Use async tools for long-running operations with progress callbacks
   - Render custom Blazor components based on tool definitions (slots, templates)
   - Implement shared state synchronization: parse state events, update Blazor component state bidirectionally
   - Use predictive updates: render tool arguments optimistically before confirmation
   - See [blazor-ag-ui-genui-patterns.md](references/blazor-ag-ui-genui-patterns.md) for Blazor-specific implementation

8. **Validate protocol compliance and UX**
   - Test event serialization and SSE streaming
   - Ensure session management via ConversationId
   - Verify tool call lifecycle (queued → executing → succeeded/failed)
   - Test accessibility: focus management, `aria-live`, keyboard nav

## References

**When to read each reference:**

- **7 Features & Agent Framework support**: [ag-ui-protocol-overview.md](references/ag-ui-protocol-overview.md) — All 7 features, Agent Framework abstractions, protocol contracts
- **Getting started** (Step 2-3): [mslearn-ag-ui-getting-started.md](references/mslearn-ag-ui-getting-started.md) — MapAGUI setup, IChatClient wiring, C# examples
- **Backend tools** (Step 4): [mslearn-backend-tool-rendering.md](references/mslearn-backend-tool-rendering.md) — AIFunctionFactory usage, tool metadata, streaming results
- **Blazor SSE & event parsing** (Step 6): [mslearn-frontend-tool-rendering.md](references/mslearn-frontend-tool-rendering.md) — SSE parsing, protocol event structures, Blazor integration
- **Blazor component patterns** (Step 6-7): [blazor-ag-ui-genui-patterns.md](references/blazor-ag-ui-genui-patterns.md) — Component composition, DynamicComponent rendering, state flow, shared state in Blazor
- **Approvals** (Step 5): [approvals-human-in-the-loop.md](references/approvals-human-in-the-loop.md) — ApprovalRequiredAIFunction, middleware, approval event protocol
- **UX/GenUI design** (Step 7, reference only): [copilotkit-generative-ui.md](references/copilotkit-generative-ui.md) — Framework-agnostic UX patterns, async tool design, shared state concepts

## Skill Maintenance

To keep this skill current, run the [maintenance workflow](references/maintenance.md) weekly or when dependencies update.
Checkpoints include: NuGet version changes, Microsoft Learn documentation updates, AG-UI protocol changes, and accessibility/security standards.

## Guardrails

- **Architecture**: Use `MapAGUI` for endpoint management. Session context flows via `ConversationId` — include in all Blazor requests.
- **Transport**: AG-UI uses HTTP POST + Server-Sent Events (SSE). Blazor Server can use SignalR; ensure Blazor WASM uses SSE fallback.
- **7 Features**: Verify all 7 AG-UI features are implemented (chat, backend tools, approvals, async tools, tool-based UI, shared state, predictive updates).
- **Tools**: Define via `AIFunctionFactory.Create()`. Wrap sensitive tools with `ApprovalRequiredAIFunction`. Test JSON schema serialization.
- **Blazor**: Parse AG-UI events safely (sanitize HTML, validate JSON). Use DynamicComponent for tool UI rendering. Don't block SSE reads; throttle updates to avoid render thrash.
- **Debugging**: Log ConversationId with all tool invocations and approval requests for traceability.
