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

## Maintenance & Update Workflow

Run this workflow weekly or at custom intervals to ensure the skill stays current:

1. **Check Package Versions**
   - Query latest NuGet releases: `Microsoft.Extensions.AI.*`, `Microsoft.AgentFramework.*`, `Microsoft.AspNetCore.Components.*`
   - Flag major/minor version bumps; review changelog/breaking changes
   - Update version constraints in references if needed

2. **Monitor Official Documentation**
   - Scan Microsoft Learn for updates: [AG-UI docs](https://learn.microsoft.com/ai/), [Blazor docs](https://learn.microsoft.com/aspnet/core/blazor/)
   - Check [AG-UI GitHub repo](https://github.com/microsoft/ag-ui) for protocol spec changes
   - Review [Microsoft Agent Framework releases](https://github.com/microsoft/semantic-kernel) for tool rendering updates

3. **Validate Code Examples**
   - Run smoke tests on workflow steps (if automated test harness exists)
   - Verify protocol event structures match current spec (especially streaming deltas)
   - Check Blazor component patterns against latest templates (`dotnet new blazor`)

4. **Update References**
   - Re-fetch updated Microsoft Learn articles into `references/`
   - Archive deprecated references with `[DEPRECATED YYYY-MM-DD]` prefix
   - Add new references for emerging patterns (e.g., new GenUI components, protocol extensions)

5. **Protocol Compatibility Check**
   - Compare current AG-UI protocol version vs skill assumptions
   - Test tool metadata serialization (ensure backward compatibility)
   - Validate event transport compatibility (SignalR/SSE version alignment)

6. **Industry Standards Audit**
   - Cross-reference with CopilotKit/Vercel AI SDK patterns (GenUI best practices)
   - Review accessibility standards (WCAG updates, ARIA patterns)
   - Check security advisories for dependencies

7. **Update Workflow & Guardrails**
   - Revise workflow steps if protocol/framework changes require new patterns
   - Add new guardrails for discovered pitfalls or anti-patterns
   - Remove obsolete steps or notes

8. **Version & Changelog**
   - Increment skill version in frontmatter if updates are substantial
   - Document changes in a `CHANGELOG.md` (if maintained) or commit message

## Guardrails

- Prefer prerelease packages only when required; validate version compatibility.
- Keep AG-UI protocol messages typed and validated.
- Isolate tool UI components in Blazor and pass agent context via cascading parameters.
- Log tool invocations and results for debugging and traceability.
- When updates originate off the renderer thread, dispatch UI refresh via `InvokeAsync(...)` (avoid dispatcher errors).
