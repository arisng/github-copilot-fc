# Blazor UI Patterns for AG-UI + Generative UI (GenUI)

## Quick Reference: 7 AG-UI Features in Blazor

| Feature                | Blazor Pattern                                            | Component/Service         |
| ---------------------- | --------------------------------------------------------- | ------------------------- |
| **Agentic Chat**       | Parse chat-delta events; append to timeline               | Chat message component    |
| **Backend Tools**      | Display tool-call events; stream results                  | Tool result renderer      |
| **Human-in-the-Loop**  | Show approval dialog; send response back                  | Approval dialog component |
| **Agentic GenUI**      | Display progress events; increment long-running UI        | Progress indicator        |
| **Tool-Based UI**      | Registry + `DynamicComponent` for custom tool renderers   | Tool UI registry          |
| **Shared State**       | Parse state events; update local model; send in next POST | State service (scoped)    |
| **Predictive Updates** | Render tool arguments optimistically before results       | Optimistic UI update      |

---

## Summary

This reference captures practical Blazor UI development patterns for building **agent-driven** apps where:

- An agent emits a stream of AG-UI protocol events (chat deltas, tool calls, results, state, progress, approvals).
- The UI must render **dynamic tool UIs** (tool metadata → Blazor component mapping).
- The UI must stay responsive and accessible while updates stream in via SSE or SignalR.

The core idea: treat agent output as an **AG-UI event stream** feeding a **state store**, and render the UI as a projection of that state. Prefer well-defined "tool UI contracts" (schema + UI hints) and a controlled rendering pipeline (registry + `DynamicComponent`/templates), instead of ad-hoc conditional markup.

---

## Architecture Options

### Option A: Blazor Server (agent + tools on server; UI over Blazor circuit)

**Best when:** you want secrets and tool execution to stay server-side, and you can accept always-online behavior.

- Transport to browser is already a **SignalR circuit** (Blazor Server). UI updates and event handling happen over SignalR/WebSockets.
- Streaming agent output can be processed server-side and pushed into scoped/per-circuit state.
- Pros:

  - Server-only secrets; app code not shipped to client.
  - Easy access to server resources and internal networks.
  - Natural fit for long-running tool executions and secure backends.

- Cons:

  - Network hop on interactions; must plan for reconnection and latency.
  - Server must maintain per-client circuit state; scaling requires planning.

Practical AG-UI mapping:

- **Agent runtime**: hosted service / background worker; but careful about dispatching UI updates to the circuit’s sync context.
- **Transport**: internal service pushes “AG-UI events” into a per-circuit store; components subscribe and rerender.

### Option B: Blazor WebAssembly (WASM) + server API (agent + tools on server)

**Best when:** you want client-side interactivity and offline-ish UI shell, but still keep tools and secrets on the server.

- UI runs in-browser; you must add a backplane for streaming updates:

  - **SignalR** (recommended for bidirectional) or
  - **SSE** (unidirectional) or
  - custom WebSocket.

- Pros:

  - UI responsiveness (local render loop) and offloaded client processing.
  - Can run as static app + API (CDN + server).

- Cons:

  - Anything in browser is inspectable/tamperable; never trust client.
  - Streaming requires explicit infra (hub/SSE endpoint) and auth.

Practical AG-UI mapping:

- Browser subscribes to a stream of agent events (chat deltas, tool-call lifecycle) and updates local state.
- UI sends user actions back (tool parameter edits, approve/deny, retry) via HTTP or SignalR.

### Option C: Blazor Web App with per-page/component render modes (hybrid “best of both”)

**Best when:** you want fast initial render (SSR) but interactive islands for the agent console/tooling.

- Render modes let you mix server-side and WebAssembly interactivity per component/page.
- Pattern: SSR shell + an **interactive “agent workspace”** component that owns streaming.

---

## UI Patterns

### 1) Model the UI around “Agent Timeline” primitives

Define a small set of UI entities and stick to them:

- `Message` (user/assistant/system), with optional streaming delta state.
- `ToolCall` (name, arguments, status, timestamps, correlation id).
- `ToolResult` (structured payload + optional rich rendering hints).
- `Artifact` (files, images, tables, previews) referenced by tool results.

UX tips for tool-call panels:

- Show a **compact timeline** with expandable details.
- Display **clear status** (queued/running/succeeded/failed/canceled).
- Provide “copy” affordances and stable ids.

### 2) Use “slots” (templated components) for consistent layouts

Treat your tool UI host like a shell with replaceable parts:

- `Header` (title, status, elapsed time, actions)
- `Body` (form inputs / results)
- `Footer` (retry/cancel/approve)

In Blazor, use `RenderFragment` parameters to implement slots (`ChildContent`, `Header`, `Footer`, etc.). This keeps tool panels consistent without forcing everything into one mega-component.

### 3) Prefer one-way data flow + explicit events

For sync between chat, tool panels, and sidebars:

- Parent owns canonical state.
- Children receive state as parameters.
- Children emit events upward via `EventCallback<T>`.

For app-wide/per-circuit state:

- Use a state container service + component subscriptions.
- Keep state objects granular; avoid one giant global mutable model.

---

## Streaming / State

### Transport choices for streaming agent output

#### SignalR

- Good for bidirectional events (client can send actions; server streams deltas).
- Particularly natural for:

  - Blazor Server (already uses SignalR circuits)
  - Blazor WASM (client hub connection)

#### SSE (Server-Sent Events)

- Good for **server → client** streaming where client sends actions via normal HTTP.
- Works well for token streams and progress updates.
- Watch out for buffering/proxies/load balancers; you may need to disable response buffering and keep-alives depending on infra.

#### WebSockets (raw)

- Use when you need very low-level control; otherwise SignalR is usually easier and includes fallback.

### Safe `StateHasChanged` patterns (the “dispatcher” rule)

In Blazor, rendering must occur on the renderer’s synchronization context. When an update originates from:

- background timers,
- hosted services,
- `Task.Run`,
- external callbacks,

…dispatch back to the renderer using `InvokeAsync(...)`, and trigger rerender safely:

- Prefer `await InvokeAsync(StateHasChanged)` (or set state then `await InvokeAsync(StateHasChanged)`), and unsubscribe in `Dispose`.

### Avoiding UI thrash during streaming

Token-level updates can overwhelm rendering.
Patterns:

- Buffer incoming deltas and update UI on a **throttle** (e.g., 30–100ms) instead of per token.
- Coalesce state updates (Blazor already avoids enqueueing multiple renders if one is pending, but your own state container may still trigger too often).
- Use virtualized lists for long timelines; keep DOM shallow.

### State synchronization patterns that scale

- **Per-circuit/per-session store** (scoped service) for Blazor Server.
- **Client store + server stream** for WASM.
- Use notifications that are safe outside sync context: components should wrap `StateHasChanged` in `InvokeAsync` when a service can notify from outside Blazor’s dispatcher.

---

## Tool UI Rendering Patterns (tool metadata → UI)

### Pattern 1: Tool renderer registry + `DynamicComponent`

Create a registry mapping tool ids/names → renderer component types:

- `Dictionary<string, Type>` or a richer descriptor (type + parameter mapping + capability flags).
- Render using `DynamicComponent Type="..." Parameters="..."`.

This is a strong fit for AG-UI “tool schema” events:

- Tool metadata becomes the *source of truth*.
- Your UI selects the renderer based on name/version/schema.

Also consider:

- Passing `EventCallback`s through the `Parameters` dictionary.
- Accessing the rendered component instance via `DynamicComponent.Instance` when you need advanced interactions.

### Pattern 2: Schema-driven forms (JSON schema → generic editor)

For tools with mostly form-like inputs:

- Use a generic form renderer based on tool parameter schema.
- Allow per-tool overrides (registry points to a custom component when needed).

### Pattern 3: RenderFragments for “micro-templates”

For repeated layouts (lists, tables, cards) where you want customization without new component types:

- Accept `RenderFragment<T>` (item template) and use it to render tool results.

### Versioning and backward compatibility

Tool UIs change. Recommended:

- Include `toolName`, `toolVersion`, and `schemaVersion`.
- Registry lookup uses the most specific match, with fallbacks.
- If no renderer is found, render a safe generic view (JSON/markdown) with copy/download.

---

## Security / Privacy Considerations

### Hosting model impacts

- **WASM**: assume all client-side code and state is inspectable and modifiable. Never embed secrets, and never trust tool arguments or “approved” flags without server-side validation.
- **Server**: app code stays on server, but you must harden:

  - authz boundaries per user/session,
  - logging/redaction of prompts/tool outputs,
  - circuit/session isolation.

### Streaming endpoints

- Authenticate and authorize your streaming transport (SignalR hub or SSE endpoint).
- Apply per-user scoping using a session/correlation id.
- Consider replay protection if you support reconnect/resume.

### Rendering untrusted content

Agent/tool outputs are untrusted:

- Don’t render raw HTML unless you sanitize and intentionally allow it.
- Prefer markdown rendering with a restricted feature set.
- For file artifacts, proxy downloads through the server with access checks.

---

## Gotchas

- Blazor Server circuits are stateful; opening the app in multiple tabs creates multiple circuits.
- Calling `StateHasChanged` from the wrong thread throws: “The current thread is not associated with the Dispatcher…” → use `InvokeAsync`.
- Avoid `async void` handlers; prefer `async Task`.
- Long polling fallback for SignalR can be a perf/UX problem; watch for proxies/VPNs blocking WebSockets.
- Accessibility: don’t let streaming updates steal focus. Prefer `aria-live="polite"` regions for incremental text and keep keyboard focus stable.

---

## Source Links (curated)

- [Blazor hosting models](https://learn.microsoft.com/en-us/aspnet/core/blazor/hosting-models?view=aspnetcore-10.0) - Canonical tradeoffs for Blazor Server vs WASM (security, latency, offline, circuits).
- [Blazor component rendering](https://learn.microsoft.com/en-us/aspnet/core/blazor/components/rendering?view=aspnetcore-10.0) - When/why to call `StateHasChanged`, and how to rerender during multi-phase async work or external events.
- [Blazor synchronization context](https://learn.microsoft.com/en-us/aspnet/core/blazor/components/synchronization-context?view=aspnetcore-10.0) - Safe patterns for updating components from timers/background work using `InvokeAsync`.
- [DynamicComponent](https://learn.microsoft.com/en-us/aspnet/core/blazor/components/dynamiccomponent?view=aspnetcore-10.0) - `DynamicComponent` for tool metadata → component mapping; passing parameters and callbacks.
- [Blazor state management](https://learn.microsoft.com/en-us/aspnet/core/blazor/state-management/?view=aspnetcore-10.0) - State container patterns and guidance for notifying components safely.
- [SignalR with Blazor tutorial](https://learn.microsoft.com/en-us/aspnet/core/blazor/tutorials/signalr-blazor?view=aspnetcore-10.0) - Practical SignalR-with-Blazor example; includes rationale for using WASM client.
- [SignalR fundamentals for Blazor](https://learn.microsoft.com/en-us/aspnet/core/blazor/fundamentals/signalr?view=aspnetcore-10.0) - SignalR guidance for Blazor circuits and transport configuration.
- [WebSockets in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/websockets?view=aspnetcore-10.0) - Why SignalR is typically preferred over raw WebSockets; transport fallback considerations.
- [ASP.NET Core 10.0 release notes](https://learn.microsoft.com/en-us/aspnet/core/release-notes/aspnetcore-10.0?view=aspnetcore-10.0) - Notes on first-class SSE result support in ASP.NET Core (.NET 10).
- [MDN: Server-sent events](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events) - Browser-side SSE model (`EventSource`) for unidirectional streaming.
- [WAI-ARIA keyboard interface practices](https://www.w3.org/WAI/ARIA/apg/practices/keyboard-interface/) - Keyboard/focus management conventions for interactive panels and composite widgets.
- [Dynamic components in Blazor (Jon Hilton)](https://jonhilton.net/blazor-dynamic-components/) - Practical discussion of dynamic rendering approaches (types vs fragments) and why `DynamicComponent` is preferred.
