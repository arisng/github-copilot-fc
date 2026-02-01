---
name: blazor-ag-ui-agent-framework
description: Build Blazor-native agent user interfaces using AG-UI protocol with Microsoft Agent Framework (MAF) and ASP.NET Core. Use when implementing the 7 AG-UI protocol features: agentic chat, backend tools, human-in-the-loop approvals, generative UI (async tools), tool-based UI rendering, shared state, and predictive state updates. Covers ASP.NET Core MapAGUI endpoints, Agent Framework integration, Blazor component rendering, and SSE streaming architecture.
version: 1.5.0
---

# AG-UI Blazor + Agent Framework (MAF)

## Quick Start

For a basic ASP.NET Core agent with Blazor frontend:

1. Install NuGet package: `Microsoft.Agents.AI.Hosting.AGUI.AspNetCore`
2. Create an `AIAgent` using `IChatClient` (Azure OpenAI, OpenAI, Ollama)
3. Map the AG-UI endpoint: `app.MapAGUI("/api/chat", agent)` in ASP.NET Core startup
4. In Blazor: Connect via HTTP POST + Server-Sent Events (SSE)
5. Parse AG-UI protocol events; render messages and tool UIs dynamically

**Triggering Generative UI**: Use intent keywords in prompts:
- "Make an interactive..." (highest success rate)
- "Create an interactive..."
- "Simulate... with adjustable..."
- Keep interfaces focused: specify 2-4 controls per prompt for cleaner layouts

For approval workflows, generative UI, or shared state, see full workflow below.

## Generative UI patterns (2026): pick the right level of freedom

Generative UI (GenUI) is when the agent influences the interface at runtime (structured inputs, progress UI, dynamic panels), not just text.

AG-UI is the **runtime event/state protocol** that enables GenUI; it is not a UI specification.

Three practical patterns:

1. **Static GenUI (AG-UI-style)** — Prebuilt UI components; the agent decides *when* to show them and *what data* they receive.
2. **Declarative GenUI (A2UI / Open-JSON-UI)** — The agent returns a constrained UI description (JSON); the app renders it with validation/whitelisting.
3. **Open-ended GenUI (MCP Apps)** — The agent can surface an external UI “surface” the app embeds; highest power, highest risk.

This skill primarily focuses on **Static GenUI in Blazor** (tool lifecycle → Blazor components), while pointing to safe extension paths for declarative/open-ended approaches.

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
   - **Validation**: Sanitize HTML, validate JSON structure before rendering
   - **Error handling**: Display partial results on stream failure; provide clear error messages
   - See [blazor-ag-ui-genui-patterns.md](references/blazor-ag-ui-genui-patterns.md) for component patterns
   - Reference: [copilotkit-generative-ui.md](references/copilotkit-generative-ui.md) for UX/GenUI design patterns (framework-agnostic)

7. **Implement generative UI in Blazor** (optional)
   - Use async tools for long-running operations with progress callbacks
   - Render custom Blazor components based on tool definitions (slots, templates)
   - Implement shared state synchronization: parse state events, update Blazor component state bidirectionally
   - Use predictive updates: render tool arguments optimistically before confirmation
   - See [blazor-ag-ui-genui-patterns.md](references/blazor-ag-ui-genui-patterns.md) for Blazor-specific implementation

8. **Extend beyond static GenUI** (optional)
   - **Declarative GenUI**: add a validated, schema-versioned renderer for a constrained UI spec (e.g., cards/forms/tables)
   - **Open-ended GenUI**: embed external UI surfaces only with strict origin allowlists and server-side authorization
   - See [generative-ui-2026-patterns.md](references/generative-ui-2026-patterns.md) for selection guidance and mappings

9. **Validate protocol compliance and UX**
   - Test event serialization and SSE streaming
   - Ensure session management via ConversationId
   - Verify tool call lifecycle (queued → executing → succeeded/failed)
   - Test accessibility: focus management, `aria-live`, keyboard nav

## Performance Optimization

1. **Streaming for perceived speed**: Render components progressively as they become available—don't wait for complete responses
2. **Token management**: Include only relevant context in agent calls (conversation history, state); trim unnecessary data
3. **Model configuration**: Balance response quality vs latency based on use case:
   - Interactive UI: prioritize speed (lower temperature, shorter max tokens)
   - Complex reasoning: prioritize accuracy (higher temperature, allow longer responses)
4. **Throttle rendering**: Batch rapid SSE updates to avoid render thrash in Blazor
5. **Graceful degradation**: If tool execution fails, display cached/partial results with retry option

## Real-World Applications

**When to use AG-UI with Blazor + MAF:**

1. **Rapid Prototyping**: Generate functional UIs in minutes for testing product concepts or client demos
2. **Custom Dashboards**: Create personalized analytics interfaces tailored to specific metrics and user roles
3. **Educational Tools**: Build interactive simulations and adaptive learning experiences
4. **Internal Tools**: Generate admin panels, form builders, and workflow managers without dedicated frontend dev
5. **Dynamic Forms**: Create context-aware forms that adapt based on user inputs and agent reasoning

**Selection criteria**: Use static GenUI (prebuilt Blazor components) for high-risk workflows; consider declarative GenUI for flexibility with validation.

## References

**When to read each reference:**

- **7 Features & Agent Framework support**: [ag-ui-protocol-overview.md](references/ag-ui-protocol-overview.md) — All 7 features, Agent Framework abstractions, protocol contracts
- **Getting started** (Step 2-3): [mslearn-ag-ui-getting-started.md](references/mslearn-ag-ui-getting-started.md) — MapAGUI setup, IChatClient wiring, C# examples
- **Backend tools** (Step 4): [mslearn-backend-tool-rendering.md](references/mslearn-backend-tool-rendering.md) — AIFunctionFactory usage, tool metadata, streaming results
- **Blazor SSE & event parsing** (Step 6): [mslearn-frontend-tool-rendering.md](references/mslearn-frontend-tool-rendering.md) — SSE parsing, protocol event structures, Blazor integration
- **Blazor component patterns** (Step 6-7): [blazor-ag-ui-genui-patterns.md](references/blazor-ag-ui-genui-patterns.md) — Component composition, DynamicComponent rendering, state flow, shared state in Blazor
- **Approvals** (Step 5): [approvals-human-in-the-loop.md](references/approvals-human-in-the-loop.md) — ApprovalRequiredAIFunction, middleware, approval event protocol
- **UX/GenUI design** (Step 7, reference only): [copilotkit-generative-ui.md](references/copilotkit-generative-ui.md) — Framework-agnostic UX patterns, async tool design, shared state concepts
- **GenUI pattern selection**: [generative-ui-2026-patterns.md](references/generative-ui-2026-patterns.md) — Static vs declarative vs open-ended GenUI, and how they map to Blazor + AG-UI

## Skill Maintenance

To keep this skill current, run the [maintenance workflow](references/maintenance.md) weekly or when dependencies update.
Checkpoints include: NuGet version changes, Microsoft Learn documentation updates, AG-UI protocol changes, and accessibility/security standards.

## Guardrails

- **Architecture**: Use `MapAGUI` for endpoint management. Session context flows via `ConversationId` — include in all Blazor requests.
- **Transport**: AG-UI uses HTTP POST + Server-Sent Events (SSE). Blazor Server can use SignalR; ensure Blazor WASM uses SSE fallback.
- **7 Features**: Verify all 7 AG-UI features are implemented (chat, backend tools, approvals, async tools, tool-based UI, shared state, predictive updates).
- **Tools**: Define via `AIFunctionFactory.Create()`. Wrap sensitive tools with `ApprovalRequiredAIFunction`. Test JSON schema serialization.
- **Prompting**: Use intent keywords ("Make an interactive...", "Create...") to trigger GenUI. Specify 2-4 controls per prompt for cleaner layouts. Test prompt patterns for consistent GenUI activation.
- **Validation**: Always sanitize HTML and validate JSON structure before rendering. Use JSON schema validation for structured outputs to ensure type-safe components.
- **Blazor**: Parse AG-UI events safely. Use DynamicComponent for tool UI rendering. Don't block SSE reads; throttle updates to avoid render thrash. Implement graceful degradation for partial failures.
- **Performance**: Stream progressively for perceived speed. Balance quality vs latency based on use case. Include only necessary context in agent calls.
- **GenUI safety**: Default to Static GenUI for high-risk flows. If implementing declarative UI, validate against a schema and whitelist components. If embedding open-ended UI surfaces, isolate/sandbox and enforce strict origin allowlists + server-side authz.
- **Debugging**: Log ConversationId with all tool invocations and approval requests for traceability.
