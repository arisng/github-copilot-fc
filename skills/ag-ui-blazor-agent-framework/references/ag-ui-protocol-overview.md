# AG-UI Protocol & Agent Framework Support

## What is AG-UI?

AG-UI is a standardized, transport-agnostic protocol for agent-to-UI communication. It defines:
- **Message types**: Chat deltas, tool calls, approval requests, state snapshots, progress updates
- **Event stream model**: Append-only, ordered events that flow bidirectionally
- **Session management**: ConversationId to maintain context across requests
- **Transports**: HTTP POST (client→server) + Server-Sent Events/SSE (server→client), or WebSockets

See [ag-ui.com](https://docs.ag-ui.com/) for protocol specification.

## The 7 AG-UI Protocol Features

**Agent Framework supports all 7 features via ASP.NET Core MapAGUI integration:**

### 1. **Agentic Chat**
- **What it is**: Streaming chat where the agent processes tool calls automatically
- **Agent Framework implementation**:
  - `AIAgent` with `RunStreamingAsync()` handles automatic tool resolution
  - Tool calls emit as AG-UI events automatically
  - No manual parsing required by frontend
- **Blazor integration**: Connect to `/api/chat` endpoint; SSE stream contains chat deltas and tool-call events
- **Example event**: `{ "type": "toolCall", "id": "tool-1", "name": "search", "arguments": {...} }`

### 2. **Backend Tool Rendering**
- **What it is**: Tools execute server-side; results stream to client
- **Agent Framework implementation**:
  - `AIFunctionFactory.Create()` defines server-side tools
  - Tool results emit as AG-UI events; Blazor displays output
- **Blazor integration**: Parse tool results from event stream; display in UI
- **Example event**: `{ "type": "toolResult", "toolCallId": "tool-1", "result": {...} }`

### 3. **Human-in-the-Loop (Approvals)**
- **What it is**: Agent requests user approval before executing sensitive actions
- **Agent Framework implementation**:
  - `ApprovalRequiredAIFunction` wraps tools that need approval
  - Middleware converts to AG-UI approval-request event
- **Blazor integration**: Show approval dialog; send user response back via POST
- **Example event**: `{ "type": "approvalRequest", "id": "approval-1", "message": "Allow delete?" }`

### 4. **Agentic Generative UI**
- **What it is**: Long-running tools emit progress updates and optional UI hints
- **Agent Framework implementation**:
  - Async tools (`async IAsyncEnumerable<...>`) emit progress events
  - Tool metadata can specify GenUI hints (component, context)
- **Blazor integration**: Parse progress events; update UI incrementally (e.g., streaming results)
- **Example event**: `{ "type": "progress", "toolCallId": "tool-1", "status": "processing", "percent": 45 }`

### 5. **Tool-Based UI Rendering**
- **What it is**: Custom Blazor components render based on tool definitions
- **Agent Framework implementation**:
  - Tool metadata includes schema (JSON Schema) and optional UI hints
  - `MapAGUI` exposes tool metadata to client
- **Blazor integration**: Use `DynamicComponent` to render tool-specific components
- **Example**: Search tool renders as a specialized search result component, not generic JSON

### 6. **Shared State (Bidirectional Sync)**
- **What it is**: Agent and client maintain synchronized state (e.g., filters, selections)
- **Agent Framework implementation**:
  - Tools can return state snapshots; client sends state updates in requests
  - `ConversationId` + request body carries client state
- **Blazor integration**: Parse state events; update local state; send updated state in next POST
- **Example event**: `{ "type": "state", "key": "filters", "value": {...} }`

### 7. **Predictive State Updates**
- **What it is**: Stream tool arguments to client before execution (optimistic updates)
- **Agent Framework implementation**:
  - Tool arguments emit as AG-UI events immediately after tool call
  - Client can render tool invocation optimistically
- **Blazor integration**: Show tool arguments in UI before results arrive
- **Example event**: `{ "type": "argumentsStream", "toolCallId": "tool-1", "arguments": {...} }`

## Agent Framework → AG-UI Mapping

| Agent Framework              | Maps to AG-UI     | How                                                      |
| ---------------------------- | ----------------- | -------------------------------------------------------- |
| `AIAgent`                    | Agent Endpoint    | Each agent becomes an HTTP endpoint (via MapAGUI)        |
| `agent.RunStreamingAsync()`  | Event Stream      | Yields `AgentResponseUpdate` → converted to AG-UI events |
| `AgentResponseUpdate`        | Protocol Events   | Chat deltas, tool calls, results, state, etc.            |
| `AIFunctionFactory.Create()` | Backend Tools     | Tools execute server-side; results stream                |
| `ApprovalRequiredAIFunction` | Human-in-the-Loop | Middleware emits approval-request events                 |
| `IChatClient`                | LLM Backend       | Azure OpenAI, OpenAI, Ollama, Gemini, etc.               |
| `ConversationId`             | Session Context   | Maintains conversation state across requests             |
| Tool JSON Schema             | Tool Metadata     | Exposed to client for UI rendering                       |

## Transport Details

- **Client → Server**: HTTP POST to `/api/chat` with `ConversationId`, messages, state
- **Server → Client**: Server-Sent Events (SSE) stream, append-only events
- **Error Handling**: Errors emit as AG-UI `error` events; connection closes cleanly
- **Timeout**: Long-lived SSE connections; use heartbeat (empty events) to prevent timeout

## References
- [AG-UI Specification](https://docs.ag-ui.com/)
- [Microsoft Agent Framework Documentation](https://learn.microsoft.com/en-us/agent-framework/)
- [AG-UI GitHub](https://github.com/ag-ui-protocol/ag-ui)
