# Generative UI patterns (2026) — practical guidance for Blazor + AG-UI

Source (conceptual): https://dev.to/copilotkit/the-developers-guide-to-generative-ui-in-2026-1bh3

## What “Generative UI” means (in practice)
Generative UI (GenUI) is when an agent influences the interface at runtime:
- Requests structured inputs (not just free-text)
- Shows task-specific UI (forms, cards, tables, previews)
- Updates UI as plans evolve (progress + intermediate results)

AG-UI is *not* a UI spec; it’s the runtime event/state protocol that streams tool lifecycle, progress, approvals, and state updates between agent ↔ app ↔ user.

## Three patterns (freedom vs control)

### 1) Static Generative UI ("AG-UI-style")
**Idea:** Developers pre-build UI components. The agent decides *when* they appear and *what data* they receive.

**Best for:**
- Reliable, high-stakes flows (payments, deletes, deployments)
- Known tool set with stable schemas
- Accessibility and branding consistency

**Blazor mapping:**
- Tool renderer registry (`toolName` → component type) + `DynamicComponent`
- Render tool lifecycle states: queued/executing/succeeded/failed
- Optimistically render streamed arguments (predictive updates)

**Safety:**
- Strongest: the frontend fully owns layout and allowed interactions

### 2) Declarative Generative UI (A2UI / Open-JSON-UI)
**Idea:** The agent returns a structured UI description (JSON) and the frontend renders it within constraints.

**Best for:**
- Many UI variants where writing bespoke components is too slow
- “Card/list/form/table” style UI that can be expressed as a schema
- Teams that want flexibility without embedding arbitrary markup

**Blazor mapping:**
- Treat the agent’s UI spec as *untrusted input*.
- Validate against a schema/version.
- Maintain a component whitelist (e.g., `Card`, `Text`, `Table`, `TextField`, `Button`).
- Convert the declarative tree to Blazor components (renderer/interpreter).
- Use AG-UI state events as the source of truth for data-model updates.

**Safety:**
- Medium: safe if you validate + whitelist components and sanitize rich text.

### 3) Open-ended Generative UI (MCP Apps)
**Idea:** The agent can surface a whole UI “surface” (often hosted elsewhere) that your app embeds.

**Best for:**
- Complex tools with existing UI (dashboards, editors, admin consoles)
- You need rich interactions beyond forms/tables

**Blazor mapping (cautious):**
- Host as an embedded surface (e.g., iframe) or a separate route.
- Gate behind explicit user intent + permissions.
- Keep a strict allowlist of origins/servers.

**Safety:**
- Lowest: treat as third-party content; isolate with sandboxing and strict authz.

## Picking the right pattern
- Start with **Static** for core workflows and anything security-sensitive.
- Add **Declarative** when you’re building many variations of “structured UI” quickly.
- Use **Open-ended** when you’re effectively integrating an external app.

A practical hybrid is common: Static for tool execution + approvals, Declarative for “reporting cards”, and Open-ended for rare specialist tools.

## Implementation notes for AG-UI + Blazor
- Prefer one-way data flow: parent owns canonical timeline/state; children emit events.
- Throttle render updates for token/progress streams (30–100ms coalescing).
- Always dispatch UI updates via `InvokeAsync(StateHasChanged)` when events arrive from background callbacks.
- Don’t render arbitrary HTML from agents/tools; prefer markdown with a restricted renderer.
