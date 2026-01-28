---
name: ag-ui-blazor-agent-framework
description: Build AG-UI integrations in .NET/C# with Microsoft Agent Framework and Blazor, including backend tool rendering, frontend tools, and generative UI context. Use when implementing the AG-UI protocol or wiring agent tools into Blazor UIs.
---

# AG-UI Blazor + Agent Framework

## Workflow

1. Identify the hosting/integration surface (server-only, Blazor Server, or Blazor WASM with a backend).
2. Choose the event transport for agent ⇄ UI communication.

    - Blazor Server: align with the existing SignalR circuit model.
    - Blazor WASM: prefer SignalR for bidirectional events; consider SSE for server → client streaming plus HTTP for user actions.

3. Design the client state store + event stream.

    - Treat agent output as an append-only event stream (chat deltas, tool-call lifecycle, tool results).
    - Keep a per-session/per-circuit store and a projection model (timeline/messages/tool panels).
    - Throttle/coalesce streaming updates to avoid render thrash.

4. Implement AG-UI protocol endpoints and map protocol events into your store.
5. Implement backend tool rendering from Agent Framework tool metadata.
6. Implement dynamic tool UI rendering in Blazor.

    - Maintain a tool renderer registry (tool id/name/version → component type/descriptor).
    - Render tool panels via `DynamicComponent` with a `Parameters` dictionary (including callbacks).
    - Provide a safe fallback renderer (structured JSON/markdown view) when no custom renderer exists.

7. Add GenUI context and interaction patterns.

    - Use slots (templated components / `RenderFragment`) for consistent tool panel layouts.
    - Use one-way data flow (state down, `EventCallback<T>` up) for approvals/retries/edits.

8. Validate UX and accessibility.

    - Don’t steal focus during streaming; use `aria-live="polite"` for incremental text where appropriate.
    - Ensure keyboard navigation and clear status for tool calls (queued/running/succeeded/failed).
    - Avoid rendering untrusted HTML; sanitize or prefer restricted markdown rendering.

9. Verify protocol compatibility and UI behavior end-to-end.

## References (load as needed)

- [Microsoft Learn: AG-UI getting started (C#)](references/mslearn-ag-ui-getting-started.md)
- [Microsoft Learn: backend tool rendering](references/mslearn-backend-tool-rendering.md)
- [Microsoft Learn: frontend tools](references/mslearn-frontend-tools.md)
- [CopilotKit: generative UI patterns](references/copilotkit-generative-ui.md)
- [AG-UI protocol overview](references/ag-ui-protocol-overview.md)
- [Blazor UI patterns for AG-UI + GenUI](references/blazor-ag-ui-genui-patterns.md)

## Guardrails

- Prefer prerelease packages only when required; validate version compatibility.
- Keep AG-UI protocol messages typed and validated.
- Isolate tool UI components in Blazor and pass agent context via cascading parameters.
- Log tool invocations and results for debugging and traceability.
- When updates originate off the renderer thread, dispatch UI refresh via `InvokeAsync(...)` (avoid dispatcher errors).
