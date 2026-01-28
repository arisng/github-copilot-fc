---
name: ag-ui-blazor-agent-framework
description: Build AG-UI integrations in .NET/C# with Microsoft Agent Framework and Blazor, including backend tool rendering, frontend tools, and generative UI context. Use when implementing the AG-UI protocol or wiring agent tools into Blazor UIs.
---

# AG-UI Blazor + Agent Framework

## Workflow
1. Identify the integration surface (server-only, Blazor Server, or Blazor WASM with a backend).
2. Implement AG-UI protocol endpoints/transport for agent ⇄ UI communication.
3. Implement backend tool rendering from Agent Framework tool metadata.
4. Implement frontend tool UIs in Blazor and bind tool invocation/results.
5. Add generative UI context (state, actions, UI slots) for adaptive rendering.
6. Verify protocol compatibility and UI behavior end-to-end.

## References (load as needed)
- [Microsoft Learn: AG-UI getting started (C#)](references/mslearn-ag-ui-getting-started.md)
- [Microsoft Learn: backend tool rendering](references/mslearn-backend-tool-rendering.md)
- [Microsoft Learn: frontend tools](references/mslearn-frontend-tools.md)
- [CopilotKit: generative UI patterns](references/copilotkit-generative-ui.md)
- [AG-UI protocol overview](references/ag-ui-protocol-overview.md)

## Guardrails
- Prefer prerelease packages only when required; validate version compatibility.
- Keep AG-UI protocol messages typed and validated.
- Isolate tool UI components in Blazor and pass agent context via cascading parameters.
- Log tool invocations and results for debugging and traceability.
