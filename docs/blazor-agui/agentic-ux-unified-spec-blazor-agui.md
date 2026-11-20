# Unified Architectural Specification for Agentic User Experiences: Blazor, AG-UI, and the Nebula Design System

> **Consolidation of:** *"Architectural Specification for Agentic UX: Integrating Blazor, AG-UI, and Generative Components"* (Feb 4, 2026) and *"Implementing Agentic UX/UI Patterns with Blazor Blueprint UI Library"* (Feb 8, 2026).
>
> **Audience:** Senior software architects, engineering leads, and frontend engineers building agentic AI applications in the .NET ecosystem.

---

## 1. Introduction: The Paradigm Shift to Agentic Interfaces

The evolution of software interfaces is undergoing a seismic shift, transitioning from static, imperative command-and-control models to dynamic, intent-driven paradigms of "Agentic" User Experience (UX). In traditional applications, the UI is a fixed map of capabilities; users navigate menus, forms, and buttons to translate intent into actions. Agentic UX inverts this relationship. The interface becomes a fluid, collaborative canvas where the user declares an intent, and an AI agent orchestrates the necessary tools, data retrieval, and interface generation to fulfill it.

The prevailing model of AI interaction — the linear chat stream — assumes a synchronous, stateless exchange. However, **Agentic AI** breaks this model. [^1] Agents do not merely complete text; they perform loops of thought, execute code, query databases, and correct their own errors before presenting a final result. A linear stream cannot capture the *structure* of this work: hierarchical plans, tool execution logs, multi-agent handoffs, and reflection cycles. [^3]

### 1.1 The Six Pillars of Agentic Interaction

Research into autonomous systems identifies six critical behavioral patterns that the UI must visualize: [^1] [^5]

1. **Reflection (Self-Correction):** The agent drafts, critiques, and refines. The UI must distinguish "rough work" from the "final product."
2. **Tool Use (External Action):** Agents interact with the world via APIs. The UI must serve as a flight recorder and security gate.
3. **Planning (Decomposition):** Complex goals are broken into sub-tasks. The UI must render a persistent, mutable roadmap.
4. **Multi-Agent Collaboration (Orchestration):** Specialized agents collaborate. The UI must clarify *who* is acting and show handoffs.
5. **Artifact Editing (Code & Document Manipulation):** Agents propose edits to code or documents. The UI must show diffs and accept/reject flows.
6. **Generative UI (Dynamic Interface Construction):** Agents construct interfaces at runtime to best present data (charts, forms, tables).

### 1.2 Scope of This Specification

This document provides an exhaustive architectural blueprint for implementing all six patterns within the .NET ecosystem, combining:

- **Infrastructure & Protocol:** The AG-UI protocol over SSE, ASP.NET Core backend, .NET Aspire orchestration, and OpenTelemetry observability.
- **UI Components & Design:** The Blazor Blueprint UI library with the "Nebula" design system, covering layout, theming, and six concrete component patterns.
- **State Management:** Fluxor-based state with DAG conversation branching and AG-UI state snapshots.

---

## 2. The Architectural Core: Decoupling Brain and Body

The fundamental principle is strict separation of the "Brain" (cognitive agent) from the "Body" (user interface). In legacy chatbot implementations, AI logic was tightly coupled with the UI controller, leading to monolithic codebases where UI latency could block AI reasoning. The AG-UI protocol resolves this by establishing a contract-based distributed system. [^2]

### 2.1 The Distributed Agent Pattern

The architecture necessitates a distributed system where the Agent Backend and the Blazor Frontend operate as independent services.

```
┌──────────────────────────────────────────────────────────────────┐
│                     .NET Aspire AppHost                         │
│  ┌─────────────────────┐         ┌─────────────────────────┐    │
│  │   Agent Backend      │  SSE    │   Blazor Frontend        │   │
│  │   (ASP.NET Core)     │◄───────►│   (Blazor Web App)       │   │
│  │                      │         │                          │   │
│  │  ┌────────────────┐  │         │  ┌────────────────────┐  │   │
│  │  │ LLM + Reasoning│  │         │  │ AGUIChatClient      │  │   │
│  │  │ Server Tools   │  │         │  │ DynamicComponent    │  │   │
│  │  │ MapAGUI()      │  │         │  │ Monaco Editor       │  │   │
│  │  └────────────────┘  │         │  │ Nebula Theme        │  │   │
│  └─────────────────────┘         │  └────────────────────┘  │   │
│                                   └─────────────────────────┘    │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              OpenTelemetry Collector                      │    │
│  └─────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────┘
```

**The Agent Backend Service ("Brain")** resides in a dedicated ASP.NET Core web service. Its sole responsibility is to host the AI agent, manage the context window, execute server-side tools, and maintain the reasoning loop. By utilizing `Microsoft.Agents.AI.Hosting.AGUI.AspNetCore`, this service exposes capabilities via standard HTTP endpoints. [^2] This separation ensures compute-heavy and sensitive LLM operations remain insulated from the client browser.

**The Blazor Frontend Client ("Body")** is a Blazor Web App (supporting Server and WebAssembly hosting models). It is the rendering engine responsible for the "Last Mile" of the user experience. It utilizes the `Microsoft.Agents.AI.AGUI` client library to connect to the backend. [^4] The frontend is "dumb" in that it contains no agent reasoning logic, but "smart" in its ability to dynamically adapt layout and render interactive components based on instructions from the Brain.

**Orchestration via .NET Aspire** manages the complexity of these distributed services. [^5a] Aspire handles service discovery, ensuring the Blazor frontend can locate the Agent backend without hardcoded URLs. It injects configuration dynamically (e.g., `AGUI_SERVER_URL`) via environment variables, facilitating seamless transitions between dev, test, and production environments. [^6]

### 2.2 Why Blazor Blueprint UI

The choice of component library is critical. Traditional options like MudBlazor or Radzen are excellent for enterprise dashboards but struggle to achieve the "sleek," consumer-grade aesthetic required for modern AI tools. [^7a] Their heavy reliance on inline styles and rigid DOM structures makes it difficult to implement subtle transitions, glassmorphism, and custom layouts.

**Blazor Blueprint UI** follows the "shadcn/ui" architecture: [^6a]

- **Headless Primitives:** Components handle logic and accessibility (focus management, keyboard navigation) but allow full control over markup and styling. Essential for novel agentic components.
- **Tailwind/CSS Utility Integration:** Standard CSS variables and utility classes enable complex theming engines without touching Razor code. [^7a]
- **Rich Iconography:** Integrated Lucide icon support (1,640+ icons) for semantic labeling of agent actions.
- **88 Components:** 15 headless Primitives + 73 pre-styled Components covering forms, navigation, overlays, displays, and charts.

---

## 3. The AG-UI Protocol: Transport and Streaming

### 3.1 Protocol Architecture: Server-Sent Events (SSE)

A critical architectural decision is the choice of transport protocol. While SignalR (WebSockets) has long been the default for real-time .NET applications, the AG-UI protocol and the broader GenAI industry have coalesced around **Server-Sent Events (SSE)**. [^2]

> **Resolution Note:** One prior spec assumed Blazor Server's native SignalR for agent communication. This unified spec clarifies the distinction: **SignalR** manages the Blazor Server circuit (DOM diffing, interactivity). **SSE** is the dedicated channel for AG-UI agent streaming. These are orthogonal concerns operating on separate connections.

| Feature                 | Server-Sent Events (SSE)             | SignalR (WebSockets)          | Agentic UX Suitability                      |
| :---------------------- | :----------------------------------- | :---------------------------- | :------------------------------------------ |
| **Directionality**      | Unidirectional (Server→Client)       | Bidirectional (Full Duplex)   | High — matches token streaming profile      |
| **Connection Overhead** | Low (Single HTTP Request)            | High (Handshake, Keep-Alives) | SSE preferred for latency sensitivity [^7]  |
| **Protocol**            | Standard HTTP/1.1 or HTTP/2          | Custom Protocol over TCP      | SSE passes easily through firewalls/proxies |
| **Reconnection**        | Native Browser Support (EventSource) | Requires Client Library Logic | SSE simplifies client complexity [^8]       |
| **Statefulness**        | Stateless HTTP (conceptually)        | Stateful "Hubs"               | SSE aligns with RESTful agent APIs          |
| **Load Balancing**      | Trivial (no sticky sessions)         | Requires sticky sessions      | SSE superior for horizontal scaling [^9]    |

The interaction pattern of Generative AI is distinct: a small user prompt triggers a massive, continuous download of tokens, often lasting several seconds or minutes. This is fundamentally a unidirectional "Server Push" scenario. SSE eliminates the complexity of managing WebSocket connections and sticky sessions in load-balanced environments. [^9]

### 3.2 The `AgentResponseUpdate` Envelope

The AG-UI protocol uses the `text/event-stream` MIME type to push `AgentResponseUpdate` objects. [^4] These objects are polymorphic, containing different content types:

| Content Type                     | Purpose                                    | Client Handling                                |
| :------------------------------- | :----------------------------------------- | :--------------------------------------------- |
| `TextContent`                    | Raw text of the agent's response           | Append to chat bubble with buffered rendering  |
| `FunctionCallContent`            | Instruction for client-side tool execution | Trigger DynamicComponent or approval dialog    |
| `FunctionApprovalRequestContent` | HITL authorization request                 | Render approval card with Approve/Deny buttons |
| `DataContent` (State Snapshot)   | JSON of agent's internal state             | Dispatch Fluxor `UpdateStateAction` [^10]      |

---

## 4. Server-Side Implementation Strategy

The server-side architecture is built upon the `Microsoft.Agents.AI.Hosting.AGUI` library, which provides middleware to serialize agent events into the SSE stream.

### 4.1 Middleware Configuration and Routing

The `MapAGUI` extension method creates an endpoint accepting POST requests (containing chat history) and returning the SSE stream. To ensure maintainability, agents should use an "Agent Factory" pattern for dependency injection: [^11]

```csharp
var builder = WebApplication.CreateBuilder(args);

// Register AG-UI services
builder.Services.AddAGUI();
builder.Services.AddScoped<IToolService, DatabaseToolService>();

var app = builder.Build();

// Map the agent to a route
var agent = app.Services.GetRequiredService<IAgentFactory>().Create("primary");
app.MapAGUI("/agent", agent);

app.Run();
```

### 4.2 Tool Registration and Execution Models

The AG-UI protocol supports **Backend Tool Rendering**. Tools (C# functions) are defined and executed on the server. The client is agnostic to implementation details. [^3a]

When an agent calls a tool (e.g., `SearchDatabase`), the server executes the function and streams the result back as part of the conversation. The protocol also transmits *execution status*, allowing the Blazor frontend to display granular updates (e.g., "Scanning database...", "Processing results...") without knowing internal tool logic.

### 4.3 Human-in-the-Loop Middleware

For sensitive tools, the server-side middleware intercepts the call and sends a `FunctionApprovalRequestContent` to the client instead of executing immediately. [^28]

1. **Interception:** Protected tool call detected by middleware.
2. **Request:** Server sends `FunctionApprovalRequestContent` to client.
3. **Decision:** User clicks "Approve" or "Deny" in the UI.
4. **Response:** Client sends decision as `ToolResult`. If approved, server executes; if denied, agent self-corrects.

---

## 5. Client-Side Integration: The Blazor AGUIChatClient

The Blazor client consumes the AG-UI stream via the `AGUIChatClient` class, which implements the `IChatClient` interface. [^4] [^13]

### 5.1 Dependency Injection and Lifecycle

```csharp
// Program.cs
builder.Services.AddHttpClient<AGUIChatClient>(client =>
{
    // URL injected via .NET Aspire service discovery
    client.BaseAddress = new Uri(builder.Configuration["AGUI_SERVER_URL"]!);
});

builder.Services.AddScoped<IChatClient>(sp => sp.GetRequiredService<AGUIChatClient>());
```

- **Blazor Server:** Register as `Scoped` (reused within a user's circuit, isolated between users).
- **Blazor WASM:** `Transient` or `Singleton` depending on auth state management.

### 5.2 Streaming Consumption with `IAsyncEnumerable`

The core loop uses `GetStreamingResponseAsync`, returning `IAsyncEnumerable<AgentResponseUpdate>`. [^4]

**Critical Optimization — Avoiding Render Thrashing:**

Calling `StateHasChanged()` for every token causes severe performance degradation. The strategy:

1. **Buffering:** Accumulate tokens into a `StringBuilder`.
2. **Throttling:** Update UI state only every ~50ms using a timer or token-count threshold.
3. **Virtualization:** Use Blazor's `<Virtualize>` component for long conversation histories to prevent DOM bloat.
4. **Markdown debounce:** Use Markdig for parsing but only re-render `MarkupString` at the throttle interval.

---

## 6. The Dual-Pane Layout Architecture

Agentic interfaces differ from chatbots by introducing a persistent "Artifact" area. The "Context" (chat) is on the left; the "Artifact" (code, document, dashboard) is on the right.

### 6.1 Splitter Component: Blazor Blueprint Resizable

The **Resizable** component from Blazor Blueprint UI provides resizable panel layouts with draggable handles and min/max constraints. [^29]

| Library                               | Component       | Suitability                                     |
| :------------------------------------ | :-------------- | :---------------------------------------------- |
| **Blazor Blueprint UI** (recommended) | Resizable       | Open source, simple API, easy state persistence |
| Telerik UI for Blazor                 | TelerikSplitter | Robust eventing, enterprise support [^14]       |
| Syncfusion Blazor                     | SfSplitter      | Nested panes for terminal windows [^16]         |
| Blazorise                             | Splitter        | Lightweight, Bootstrap integration [^15]        |

The architectural requirement is **programmatic control** over pane sizes — the agent may decide to "Expand the Canvas" to show a wide data grid, adjusting the splitter position automatically.

### 6.2 State Persistence

Layout preferences are persisted via `Blazored.LocalStorage`: [^17]

- **Save:** Subscribe to `OnResize`. Debounce (500ms). Save percentage width.
- **Load:** On `OnInitializedAsync`, retrieve and bind to the `Size` parameter.

---

## 7. The Visual Design System: Project "Nebula"

The "Nebula" design system is a custom implementation of Blazor Blueprint's CSS variable tokens, optimized for the cognitive demands of AI-assisted workflows. [^12]

### 7.1 Design Theory: Sleek Modernism

- **Reduction of Borders:** Distinct background shades (`--card` vs `--background`) define layout instead of heavy borders.
- **Subtle Depth:** `backdrop-filter: blur()` (Glassmorphism) creates layering for floating elements like Plan Drawers or Approval Dialogs.
- **Typography:** **Inter** for UI text (excellent small-size readability). **JetBrains Mono** for code blocks and agent logs. This juxtaposition distinguishes "human" conversational text from "machine" technical output.

### 7.2 Dark Mode: "Deep Space"

Designed for prolonged usage. Background is dark zinc (`#09090b`), not pure black. Primary accent is Electric Violet.

| Variable Token           | Hex Value | Usage Context                                       |
| :----------------------- | :-------- | :-------------------------------------------------- |
| `--background`           | `#09090b` | Main application canvas                             |
| `--foreground`           | `#fafafa` | Primary text content                                |
| `--card`                 | `#18181b` | Chat bubbles and panels                             |
| `--card-foreground`      | `#fafafa` | Text within cards                                   |
| `--popover`              | `#09090b` | Dropdowns and dialogs                               |
| `--primary`              | `#8b5cf6` | **Electric Violet** — Submit buttons, active states |
| `--primary-foreground`   | `#ffffff` | Text on primary buttons                             |
| `--secondary`            | `#27272a` | Muted buttons, inactive tabs                        |
| `--secondary-foreground` | `#a1a1aa` | Text on secondary elements                          |
| `--muted`                | `#27272a` | Backgrounds for "Thinking" blocks                   |
| `--muted-foreground`     | `#71717a` | Metadata, timestamps                                |
| `--destructive`          | `#7f1d1d` | Error states, "Stop Generation"                     |
| `--border`               | `#27272a` | Subtle dividers                                     |
| `--ring`                 | `#8b5cf6` | Focus rings for accessibility                       |

### 7.3 Light Mode: "Ceramic"

Clean laboratory aesthetic. High-brightness whites with Deep Azure accent.

| Variable Token         | Hex Value | Usage Context                              |
| :--------------------- | :-------- | :----------------------------------------- |
| `--background`         | `#ffffff` | Pure white canvas                          |
| `--foreground`         | `#09090b` | High-contrast black text                   |
| `--card`               | `#ffffff` | White cards with subtle shadow             |
| `--primary`            | `#2563eb` | **Deep Azure** — Professional, trustworthy |
| `--primary-foreground` | `#ffffff` | White text on primary                      |
| `--secondary`          | `#f4f4f5` | Very light gray for grouping               |
| `--muted`              | `#f4f4f5` | Secondary content backgrounds              |
| `--muted-foreground`   | `#52525b` | Medium gray for metadata                   |
| `--border`             | `#e4e4e7` | Light gray dividers                        |

### 7.4 CSS Implementation

```css
:root {
    /* Default Light Mode ("Ceramic") */
    --background: 0 0% 100%;
    --foreground: 240 10% 3.9%;
    --card: 0 0% 100%;
    --card-foreground: 240 10% 3.9%;
    --popover: 0 0% 100%;
    --popover-foreground: 240 10% 3.9%;
    --primary: 221.2 83.2% 53.3%;
    --primary-foreground: 210 40% 98%;
    --secondary: 240 4.8% 95.9%;
    --secondary-foreground: 240 5.9% 10%;
    --muted: 240 4.8% 95.9%;
    --muted-foreground: 240 3.8% 46.1%;
    --accent: 240 4.8% 95.9%;
    --accent-foreground: 240 5.9% 10%;
    --destructive: 0 84.2% 60.2%;
    --destructive-foreground: 0 0% 98%;
    --border: 240 5.9% 90%;
    --input: 240 5.9% 90%;
    --ring: 221.2 83.2% 53.3%;
    --radius: 0.5rem;
}

.dark {
    /* Dark Mode ("Deep Space") */
    --background: 240 10% 3.9%;
    --foreground: 0 0% 98%;
    --card: 240 10% 3.9%;
    --card-foreground: 0 0% 98%;
    --popover: 240 10% 3.9%;
    --popover-foreground: 0 0% 98%;
    --primary: 263.4 70% 50.4%; /* Electric Violet */
    --primary-foreground: 210 40% 98%;
    --secondary: 240 3.7% 15.9%;
    --secondary-foreground: 0 0% 98%;
    --muted: 240 3.7% 15.9%;
    --muted-foreground: 240 5% 64.9%;
    --accent: 240 3.7% 15.9%;
    --accent-foreground: 0 0% 98%;
    --destructive: 0 62.8% 30.6%;
    --destructive-foreground: 0 0% 98%;
    --border: 240 3.7% 15.9%;
    --input: 240 3.7% 15.9%;
    --ring: 263.4 70% 50.4%;
}
```

Theme switching is achieved by toggling the `.dark` class on the `<html>` element via JavaScript interop, with preference stored in `localStorage`.

---

## 8. UX Pattern I: Reflection (The "Glass Box" Interface)

The Reflection pattern addresses trust. By visualizing the **Reflection Loop** — the process where an agent critiques its own work — we convert latency into a trust-building mechanism. [^1]

### 8.1 Challenge

The challenge lies in representing a recursive process within a linear stream. An agent might draft, critique, search for a missing citation, update the draft, and finalize. A standard chat bubble cannot contain this.

### 8.2 Component Architecture

```
AgentResponseContainer.razor
├── ThoughtStream.razor          ← Accordion (collapsed by default)
│   └── ReflectionStep[]         ← Badge + monospace content
└── FinalContent.razor           ← Card (fades in on completion)
```

**Blazor Blueprint Components:** `Accordion`, `Badge`, `Card`

### 8.3 Visual Indicators

1. **Draft State:** While thinking, the Accordion border pulses (`animate-pulse`) using `--primary`.
2. **Critique Blocks:** Individual reflection steps labeled with `<Badge Variant="Outline">Critique</Badge>`.
3. **Finalization:** Accordion auto-collapses; `FinalContent` card fades in (`opacity-0` → `opacity-100`).

### 8.4 Implementation

```razor
@if (Steps.Any())
{
    <Accordion Type="AccordionType.Single" Collapsible="true"
               Class="mb-4 border border-border rounded-lg bg-muted/50">
        <AccordionItem Value="thoughts">
            <AccordionTrigger Class="px-4 py-2 text-sm text-muted-foreground hover:text-foreground transition-colors">
                <div class="flex items-center gap-2">
                    <LucideBrain Class="w-4 h-4" />
                    <span>Process Log (@Steps.Count steps)</span>
                    @if (IsThinking)
                    {
                        <LucideLoader2 Class="w-3 h-3 animate-spin text-primary" />
                    }
                </div>
            </AccordionTrigger>
            <AccordionContent>
                <div class="p-4 space-y-3">
                    @foreach (var step in Steps)
                    {
                        <div class="flex flex-col gap-1">
                            <div class="flex items-center gap-2">
                                <Badge Variant="BadgeVariant.Outline" Class="text-xs">@step.Type</Badge>
                                <span class="text-xs text-muted-foreground">@step.Timestamp</span>
                            </div>
                            <p class="text-sm font-mono text-foreground/80 pl-2 border-l-2 border-border">
                                @step.Content
                            </p>
                        </div>
                    }
                </div>
            </AccordionContent>
        </AccordionItem>
    </Accordion>
}
```

**Design Insight:** Using monospace font (`font-mono`) for reflection content visually reinforces "machine thought," distinct from the proportional font used in the final response. This typographic cue reduces cognitive load while maintaining transparency.

---

## 9. UX Pattern II: Tool Use (The "Cockpit" Interface)

Tool use represents the agent's ability to affect the external world. This is the most safety-critical capability and requires the strictest UI controls. [^1]

### 9.1 Challenge

Tools vary in input/output structure. The UI must be polymorphic, adapting presentation to the tool type. For sensitive tools (e.g., `DELETE FROM users`), it must enforce Human-in-the-Loop authorization. [^28]

### 9.2 Three-Component Lifecycle

**Blazor Blueprint Components:** `Command`, `Dialog`, `Table`

1. **Discovery (Command Palette):** The `Command` component (cmd+k interface) lists available tools categorized by domain. It doubles as an active state viewer — if an agent is searching for a tool, the palette can open programmatically.

2. **Authorization (Approval Dialog):** When a sensitive tool is invoked, the workflow pauses. A `Dialog` modal presents:
   - Tool name and description
   - Raw arguments in a code block
   - `--destructive` colored "Approve" button for dangerous actions
   - "Deny" button that returns an error to the agent for self-correction

3. **Observability (Result Rendering):** Structured tool output is rendered as rich UI, not raw JSON.

### 9.3 Dynamic Tool Output Renderer

```razor
@switch (Output.Type)
{
    case ToolOutputType.Text:
        <div class="bg-muted p-3 rounded-md text-sm font-mono">@Output.Data</div>
        break;

    case ToolOutputType.Json:
        <pre class="bg-muted p-3 rounded-md text-xs overflow-x-auto">@Output.Data</pre>
        break;

    case ToolOutputType.Table:
        <div class="border rounded-md">
            <Table>
                <TableHeader>
                    <TableRow>
                        @foreach (var header in Output.Headers)
                        {
                            <TableHead>@header</TableHead>
                        }
                    </TableRow>
                </TableHeader>
                <TableBody>
                    @foreach (var row in Output.Rows)
                    {
                        <TableRow>
                            @foreach (var cell in row)
                            {
                                <TableCell>@cell</TableCell>
                            }
                        </TableRow>
                    }
                </TableBody>
            </Table>
        </div>
        break;
}
```

**Design Insight:** Rendering tool outputs as rich UI (tables, charts) empowers users to *verify* agent findings. If the agent says "I found 5 users," the user can glance at the Table to confirm, eliminating the "hallucination gap."

---

## 10. UX Pattern III: Planning (The Dynamic Roadmap)

Planning is the hallmark of advanced agentic systems — breaking a high-level goal into a dependency graph of sub-tasks. [^1] In typical chat, the plan scrolls off-screen and is lost. The UI solution is **persistence**.

### 10.1 Challenge

The plan is a mutable state machine. Tasks transition through `Pending → InProgress → Completed | Failed`. New tasks are injected; redundant tasks are pruned. The UI must represent this dynamism without disorientation.

### 10.2 The Persistent Sheet

**Blazor Blueprint Components:** `Sheet`, `Progress`, `Card`, Lucide icons

The `Sheet` component (Drawer/Slide-over) houses the plan in a separate visual layer. Unlike a sidebar, it can be toggled to overlay or sit alongside content.

**Visual Structure:**

1. **Global Progress:** `Progress` bar at the top shows overall completion percentage.
2. **Task Graph:** Nested `Card` components represent task hierarchy.
3. **Status Icons (Lucide):**
   - `Circle` — Pending (Gray)
   - `Loader2` — In Progress (Blue, `animate-spin`)
   - `CheckCircle2` — Completed (Green)
   - `XCircle` — Failed (Red)

### 10.3 Implementation

```razor
<Sheet @bind-Open="IsOpen">
    <SheetContent Side="Side.Right" Class="w-[400px] sm:w-[540px] overflow-y-auto">
        <SheetHeader>
            <SheetTitle>Mission Plan</SheetTitle>
            <SheetDescription>Current objective: @CurrentObjective</SheetDescription>
        </SheetHeader>

        <div class="py-6 space-y-6">
            <div class="space-y-2">
                <div class="flex justify-between text-sm">
                    <span>Progress</span>
                    <span class="text-muted-foreground">@PercentComplete%</span>
                </div>
                <Progress Value="@PercentComplete" Class="h-2" />
            </div>

            <div class="space-y-4">
                @foreach (var task in Tasks)
                {
                    <Card Class="@GetTaskClass(task)">
                        <CardHeader Class="p-4 flex flex-row items-start gap-3 space-y-0">
                            <div class="mt-1">
                                @if (task.Status == TaskStatus.Running)
                                {
                                    <LucideLoader2 Class="w-5 h-5 text-primary animate-spin" />
                                }
                                else if (task.Status == TaskStatus.Completed)
                                {
                                    <LucideCheckCircle2 Class="w-5 h-5 text-green-500" />
                                }
                                else
                                {
                                    <LucideCircle Class="w-5 h-5 text-muted-foreground" />
                                }
                            </div>
                            <div class="flex-1 space-y-1">
                                <CardTitle Class="text-sm font-medium leading-none">
                                    @task.Title
                                </CardTitle>
                                <CardDescription>@task.Description</CardDescription>
                            </div>
                        </CardHeader>
                    </Card>
                }
            </div>
        </div>
    </SheetContent>
</Sheet>
```

**Design Insight:** Placing the plan in a separate visual layer (the "Meta-Layer") reinforces that the Plan is the *controller* of the chat stream, not a product of it. Users can browse the plan while the agent generates text, facilitating multi-tasking.

---

## 11. UX Pattern IV: Multi-Agent Orchestration (The "Council" Interface)

Multi-agent systems introduce "Who is speaking?" A system with Researcher, Coder, and Reviewer agents creates confusion in a linear chat. [^3b]

### 11.1 Challenge

Each agent has its own context (memory), tools, and persona. The UI must group messages by agent and show handoff processes.

### 11.2 Three-Layer Visualization

**Blazor Blueprint Components:** `Avatar`, `Badge`, `Tabs`, `Separator`

1. **Identity (Avatars & Badges):** Every message is prefixed with an `Avatar` using distinct Lucide icons: `LucideTerminal` for Coder, `LucideBook` for Researcher. A `Badge` states the role.

2. **Context Switching (Tabs):** A `Tabs` component in the sidebar allows viewing each agent's private context:
   - *Tab 1: Main Stream* (public conversation)
   - *Tab 2: Researcher Memory* (indexed documents)
   - *Tab 3: Coder Workspace* (file definitions)

3. **Handoff Visualization:** A `Separator` with a label is inserted when control passes between agents, creating a visual break.

### 11.3 Implementation

```razor
<div class="flex gap-4 p-4 group hover:bg-muted/50 transition-colors">
    <div class="flex-shrink-0 flex flex-col items-center gap-2">
        <Avatar Class="w-10 h-10 border border-border">
            <AvatarImage Src="@Agent.AvatarUrl" />
            <AvatarFallback>@Agent.Initials</AvatarFallback>
        </Avatar>
        <Badge Variant="BadgeVariant.Outline" Class="text-[10px] px-1 py-0 h-5">
            @Agent.Role
        </Badge>
    </div>

    <div class="flex-1 space-y-2 min-w-0">
        <div class="flex items-center justify-between">
            <span class="font-semibold text-sm">@Agent.Name</span>
            <span class="text-xs text-muted-foreground">@Timestamp</span>
        </div>

        <div class="prose prose-sm dark:prose-invert max-w-none">
            @Content
        </div>

        @if (HasAttachments)
        {
            <div class="mt-4 pt-4 border-t border-border">
                @ChildContent
            </div>
        }
    </div>
</div>
```

**Design Insight:** The vertical Avatar+content alignment creates a "Swimlane" effect. The `Badge` provides quick semantic lookup ("the *Reviewer* is speaking, so this is a critique").

---

## 12. UX Pattern V: Artifact Editing (The Monaco Editor)

For agents generating code or structured text, the architecture mandates the **Monaco Editor** (the engine powering VS Code) to provide an IDE-like experience within the artifact pane.

### 12.1 Integration via BlazorMonaco

BlazorMonaco provides `StandaloneCodeEditor` and `StandaloneDiffEditor` components. [^18] [^19]

**Critical Constraints:**

- **Render Mode:** Monaco requires `InteractiveServer` or `InteractiveWebAssembly`. It fails under Static SSR.
- **Enhanced Navigation:** Blazor's enhanced navigation (.NET 8+) interferes with JavaScript component lifecycles. Apply `data-enhance-nav="false"` to links navigating to editor pages, or manually dispose/re-initialize.

### 12.2 The "Review Changes" Pattern (Diff Editor)

A key agentic workflow: the agent proposes an edit, and the user views a side-by-side diff before accepting.

The `StandaloneDiffEditor` requires two models: [^20]

- **Original:** Current state of the file.
- **Modified:** Agent's proposed state.

To update programmatically, use the `SetModel` API via the component's `@ref`.

### 12.3 Applying Edits: `executeEdits` vs `SetValue`

| Approach       | Use Case                          | Undo Stack                                           |
| :------------- | :-------------------------------- | :--------------------------------------------------- |
| `SetValue`     | Full-file replacements from agent | **Cleared** — acceptable for agent rewrites          |
| `executeEdits` | Small cursor-based insertions     | **Preserved** — required for incremental edits [^22] |

`executeEdits` requires constructing an `IdentifiedSingleEditOperation` that defines a `Range` (start/end line/column) and the `Text` to insert. While complex to bridge via JS Interop, it provides fine-grained control.

### 12.4 Workflow

```
Agent proposes edit → DiffEditor renders Original vs Modified
    ├── User clicks "Accept" → executeEdits() or SetValue() applies changes
    └── User clicks "Reject" → Agent receives rejection, can revise
```

---

## 13. UX Pattern VI: Generative UI (Dynamic Component Rendering)

The most advanced capability: the agent constructs user interfaces at runtime. This moves beyond Markdown tables to interactive Blazor components. [^24]

### 13.1 The `DynamicComponent` + Registry Pattern

Blazor's `<DynamicComponent>` accepts a `Type` and a `Dictionary<string, object>` for parameters. [^24]

**Component Registry Service:**

```csharp
public class ComponentRegistry
{
    private readonly Dictionary<string, Type> _registry = new()
    {
        ["ShowWeatherWidget"] = typeof(WeatherCard),
        ["ShowDataGrid"]      = typeof(DataGridView),
        ["ShowChart"]         = typeof(ChartPanel),
        ["ShowForm"]          = typeof(DynamicForm),
    };

    public (Type Type, Dictionary<string, object> Parameters)?
        Resolve(string toolName, JsonElement arguments)
    {
        if (!_registry.TryGetValue(toolName, out var type))
            return null;

        var parameters = JsonSerializer.Deserialize<Dictionary<string, object>>(arguments);
        return (type, parameters!);
    }
}
```

**Flow:**

1. Agent executes tool `ShowWeatherWidget` with args `{"city": "London"}`.
2. Registry resolves `ShowWeatherWidget` → `typeof(WeatherCard)`.
3. `<DynamicComponent Type="resolvedType" Parameters="resolvedParams" />` renders the card.

### 13.2 Recursive UI Generation via `RenderTreeBuilder`

For complex forms (e.g., "Create a data entry form for this SQL schema"), `DynamicComponent` is too flat. The architecture uses the low-level `RenderTreeBuilder`: [^25]

```csharp
@code {
    [Parameter] public JsonSchema Schema { get; set; }
    [Parameter] public Dictionary<string, object> Data { get; set; }

    protected override void BuildRenderTree(RenderTreeBuilder builder)
    {
        int seq = 0;
        foreach (var prop in Schema.Properties)
        {
            if (prop.Type == "string")
            {
                builder.OpenComponent(seq++, typeof(InputText));
                builder.AddAttribute(seq++, "Label", prop.Title);
                builder.AddAttribute(seq++, "Value", Data[prop.Name]);
                builder.CloseComponent();
            }
            else if (prop.Type == "array")
            {
                builder.OpenComponent(seq++, typeof(DataTable<object>));
                // Configure columns based on array item schema
                builder.CloseComponent();
            }
        }
    }
}
```

This enables rendering interfaces for data structures that did not exist at compile time — true generative capability.

---

## 14. State Management and Conversation Branching

### 14.1 Fluxor Store Architecture

The complexity of agentic workflows exceeds what `CascadingParameter` can handle. **Fluxor** (Redux for Blazor) manages the state: [^27]

| Store           | Contents                                                                                     |
| :-------------- | :------------------------------------------------------------------------------------------- |
| `AgentState`    | Current status (`Idle`, `Thinking`, `ExecutingTool`)                                         |
| `ChatState`     | Polymorphic message list (`TextMessage`, `ToolMessage`, `ThoughtMessage`, `ApprovalMessage`) |
| `PlanState`     | Task hierarchy for the Planning pattern                                                      |
| `ArtifactState` | Current editor content, diff state                                                           |

**Action Dispatch Mapping:**

| Agent Event              | Fluxor Action                  | UI Effect                 |
| :----------------------- | :----------------------------- | :------------------------ |
| Agent starts thinking    | `AgentStartedThinkingAction`   | Accordion pulse animation |
| Tool execution requested | `ToolExecutionRequestedAction` | Dialog modal opens        |
| Plan updated             | `PlanUpdatedAction`            | Sheet content refreshes   |
| State snapshot received  | `UpdateStateAction`            | Global state synchronized |

### 14.2 The Temporal State Graph (Conversation Branching)

Agentic conversations are rarely linear. Users edit previous prompts, creating branches. The state must be modeled as a **Directed Acyclic Graph (DAG)**, not a flat `List<Message>`.

- **Edit Action:** `Dispatch(new EditMessageAction(id, newText))`
- **Reducer:** Does not mutate the existing message. Creates a new node linked as a sibling, forming a branch.
- **Undo/Redo:** Supported via [Fluxor.Undo](https://github.com/Pjotrtje/Fluxor.Undo). [^27]

### 14.3 Synchronization via AG-UI State Snapshots

The AG-UI protocol supports **Shared State** via `STATE_SNAPSHOT` events: [^2] [^10]

1. Server emits a JSON snapshot of agent memory (e.g., `{"user_preference": "dark_mode"}`).
2. Client detects `DataContent` with MIME type `application/json`.
3. Client dispatches `UpdateAgentStateAction`, updating the Fluxor store.
4. UI elements (theme, settings) react to the new state immediately.

---

## 15. Orchestration and Observability

### 15.1 The Golden Triangle

The "Golden Triangle" methodology combines three operational pillars: [^1a]

```
         ┌──────────┐
         │  DevUI   │  ← Local debugging, tool verification
         └────┬─────┘
              │
    ┌─────────┴─────────┐
    │                   │
┌───┴───┐         ┌────┴────────┐
│ AG-UI │         │ OpenTelemetry│
│ (SSE) │         │  (Tracing)  │
└───────┘         └─────────────┘
  Production        Distributed
  Protocol          Observability
```

- **DevUI:** During development, the agent is tested via the simplified DevUI provided by the Microsoft Agent Framework to verify tool logic in isolation.
- **AG-UI:** The production protocol over SSE for real user sessions.
- **OpenTelemetry:** Both the Agent Backend and Blazor Frontend are instrumented. This provides distributed tracing: a request starts at a Blazor button click, travels through the SSE stream, triggers LLM inference, executes a backend tool, and returns. Critical for debugging latency and token usage. [^1a]

### 15.2 .NET Aspire Dashboard

.NET Aspire provides a built-in dashboard that surfaces:

- Service health checks
- Environment variable injection
- Log aggregation across agent + frontend services
- OpenTelemetry trace visualization

---

## 16. Mobile Responsiveness

The Nebula theme and Blazor Blueprint components support mobile-first design via Tailwind utilities.

| Component              | Desktop                                        | Mobile                                |
| :--------------------- | :--------------------------------------------- | :------------------------------------ |
| **Dual-Pane Splitter** | Both panes visible, draggable                  | Single pane with Tab/Drawer toggle    |
| **Plan Sheet**         | Side slide-over                                | Bottom-sheet                          |
| **Command Palette**    | Centered dialog                                | Full-screen                           |
| **Data Tables**        | Full width                                     | Horizontal scroll (`overflow-x-auto`) |
| **Detection**          | CSS media queries or JS Interop viewport check | —                                     |

---

## 17. Conclusion

This unified specification defines a complete architectural blueprint for Agentic UX with Blazor, spanning from the transport layer (SSE via AG-UI) through to pixel-level visual design (the "Nebula" system). The six UX patterns — **Reflection**, **Tool Use**, **Planning**, **Multi-Agent Orchestration**, **Artifact Editing**, and **Generative UI** — transform the "Black Box" of AI into a "Glass Box," ensuring that as systems become more intelligent, they also become more intelligible.

The architecture is characterized by:

- **Strict separation of concerns:** Brain (Agent Backend) and Body (Blazor Frontend) communicate via the AG-UI protocol over SSE.
- **Robust state management:** Fluxor stores with DAG-based conversation branching and AG-UI state snapshots.
- **Orchestration and observability:** .NET Aspire for service discovery, OpenTelemetry for distributed tracing.
- **Visual precision:** The Nebula design system delivers sleek, high-contrast aesthetics optimized for cognitive-heavy AI workflows.
- **Component flexibility:** Blazor Blueprint UI's headless primitives enable novel agentic components without the constraints of opinionated frameworks.

This blueprint provides the foundation for engineering teams to build production-grade, agentic AI applications within the .NET ecosystem.

---

## 18. Implementation Guide: Core Code Structures

### 18.1 NuGet Package Dependencies

```xml
<!-- Agent Communication -->
<PackageReference Include="Microsoft.Agents.AI.AGUI" />
<PackageReference Include="Microsoft.Agents.AI.Hosting.AGUI.AspNetCore" />

<!-- UI Components -->
<PackageReference Include="BlazorBlueprint.Components" />
<PackageReference Include="BlazorBlueprint.Icons" />

<!-- State Management -->
<PackageReference Include="Fluxor.Blazor.Web" />
<PackageReference Include="Blazored.LocalStorage" />

<!-- Editor -->
<PackageReference Include="BlazorMonaco" />

<!-- Markdown -->
<PackageReference Include="Markdig" />

<!-- Observability -->
<PackageReference Include="OpenTelemetry.Extensions.Hosting" />
<PackageReference Include="OpenTelemetry.Exporter.OpenTelemetryProtocol" />
```

### 18.2 Service Registration (Program.cs)

```csharp
var builder = WebApplication.CreateBuilder(args);

// AG-UI Client
builder.Services.AddHttpClient<AGUIChatClient>(client =>
{
    client.BaseAddress = new Uri(builder.Configuration["AGUI_SERVER_URL"]!);
});
builder.Services.AddScoped<IChatClient>(sp => sp.GetRequiredService<AGUIChatClient>());

// Blazor Blueprint UI
builder.Services.AddBlazorBlueprint();

// State Management
builder.Services.AddFluxor(options => options.ScanAssemblies(typeof(Program).Assembly));

// Theme & Layout
builder.Services.AddScoped<IThemeService, ThemeService>();
builder.Services.AddBlazoredLocalStorage();

// Generative UI Registry
builder.Services.AddSingleton<ComponentRegistry>();

// OpenTelemetry
builder.Services.AddOpenTelemetry()
    .WithTracing(tracing => tracing
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddOtlpExporter());

var app = builder.Build();
```

### 18.3 AG-UI Agent Service Wrapper

```csharp
public class AgentService
{
    private readonly IChatClient _client;
    private readonly IState<AgentState> _state;
    private readonly IDispatcher _dispatcher;

    public AgentService(IChatClient client, IState<AgentState> state, IDispatcher dispatcher)
    {
        _client = client;
        _state = state;
        _dispatcher = dispatcher;
    }

    public async IAsyncEnumerable<ChatResponseItem> StreamResponseAsync(
        List<ChatMessage> history,
        [EnumeratorCancellation] CancellationToken ct = default)
    {
        var options = new ChatOptions
        {
            AdditionalProperties = new() { ["client_state"] = _state.Value }
        };

        await foreach (var update in _client.GetStreamingResponseAsync(history, options).WithCancellation(ct))
        {
            if (update.Content is TextContent text)
            {
                yield return new ChatResponseItem
                {
                    Type = ResponseType.Text,
                    Content = text.Text
                };
            }
            else if (update.Content is FunctionCallContent tool)
            {
                yield return new ChatResponseItem
                {
                    Type = ResponseType.ToolCall,
                    Content = tool.Name
                };
            }
            else if (update.Content is FunctionApprovalRequestContent approval)
            {
                yield return new ChatResponseItem
                {
                    Type = ResponseType.ApprovalRequest,
                    ToolName = approval.Name,
                    Arguments = approval.Arguments
                };
            }
            else if (update.Content is DataContent data && data.MediaType == "application/json")
            {
                var snapshot = JsonSerializer.Deserialize<StateSnapshot>(data.Data);
                _dispatcher.Dispatch(new UpdateStateAction(snapshot!));
            }
        }
    }
}
```

### 18.4 Fluxor State Definitions

```csharp
// Agent State
[FeatureState]
public record AgentState
{
    public AgentStatus Status { get; init; } = AgentStatus.Idle;
    public StateSnapshot? LastSnapshot { get; init; }
}

public enum AgentStatus { Idle, Thinking, ExecutingTool, WaitingForApproval }

// Chat State (DAG-based)
[FeatureState]
public record ChatState
{
    public ImmutableList<ChatNode> Nodes { get; init; } = [];
    public string ActiveBranchId { get; init; } = "main";
}

public record ChatNode
{
    public string Id { get; init; } = Guid.NewGuid().ToString();
    public string BranchId { get; init; } = "main";
    public string? ParentId { get; init; }
    public ChatMessage Message { get; init; } = default!;
    public DateTimeOffset Timestamp { get; init; } = DateTimeOffset.UtcNow;
}

// Plan State
[FeatureState]
public record PlanState
{
    public string Objective { get; init; } = string.Empty;
    public ImmutableList<PlanTask> Tasks { get; init; } = [];
    public int PercentComplete => Tasks.Count == 0 ? 0
        : (int)(Tasks.Count(t => t.Status == TaskStatus.Completed) * 100.0 / Tasks.Count);
}

public record PlanTask(string Id, string Title, string Description, TaskStatus Status);
public enum TaskStatus { Pending, Running, Completed, Failed }
```

---

## 19. Works Cited

[^1]: Agentic Design Patterns — Bijit Ghosh, Medium. https://medium.com/@bijit211987/agentic-design-patterns-cbd0aae2962f

[^1a]: The "Golden Triangle" of Agentic Development with Microsoft Agent Framework — Semantic Kernel Blog. https://devblogs.microsoft.com/semantic-kernel/the-golden-triangle-of-agentic-development-with-microsoft-agent-framework-ag-ui-devui-opentelemetry-deep-dive/

[^2]: AG-UI Integration with Agent Framework — Microsoft Learn. https://learn.microsoft.com/en-us/agent-framework/integrations/ag-ui/

[^3]: AI Agent Design Patterns: A Strategic Guide for CXOs — Lightrains. https://lightrains.com/blogs/ai-agent-design-patterns-cxo/

[^3a]: Backend Tool Rendering with AG-UI — Microsoft Learn. https://learn.microsoft.com/en-us/agent-framework/integrations/ag-ui/backend-tool-rendering

[^3b]: Agent design pattern catalogue — ResearchGate. https://www.researchgate.net/publication/385826836_Agent_design_pattern_catalogue_A_collection_of_architectural_patterns_for_foundation_model_based_agents

[^4]: Getting Started with AG-UI — Microsoft Learn. https://learn.microsoft.com/en-us/agent-framework/integrations/ag-ui/getting-started

[^5]: Top 4 Agentic AI Design Patterns — Analytics Vidhya. https://www.analyticsvidhya.com/blog/2024/10/agentic-design-patterns/

[^5a]: AgentFx-AIWebChatApp-AG-UI README — GitHub. https://github.com/microsoft/Generative-AI-for-beginners-dotnet/blob/main/samples/AgentFx/AgentFx-AIWebChatApp-AG-UI/README.md

[^6]: AG-UI + Agent Framework + .NET + Aspire — El Bruno. https://elbruno.com/2025/11/18/ag-ui-agent-framework-net-aspire-web-enabling-your-intelligent-agents-blog-demo-code/

[^6a]: Blazor Blueprint (shadcn/ui inspired) — Reddit r/Blazor. https://www.reddit.com/r/Blazor/comments/1qvp45q/i_built_blazor_blueprint_a_shadcnui_inspired/

[^7]: The Streaming Backbone of LLMs: Why SSE Still Wins in 2026. https://procedure.tech/blogs/the-streaming-backbone-of-llms-why-server-sent-events-(sse)-still-wins-in-2025

[^7a]: Blazor Blueprint — r/dotnet. https://www.reddit.com/r/dotnet/comments/1qwjxr3/blazor_blueprint_shadcnui_inspired_component/

[^8]: Using server-sent events — MDN Web Docs. https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events

[^9]: Server-Sent Events in ASP.NET Core and .NET 10 — Milan Jovanovic. https://www.milanjovanovic.tech/blog/server-sent-events-in-aspnetcore-and-dotnet-10

[^10]: Running Agents — Microsoft Learn. https://learn.microsoft.com/en-us/agent-framework/user-guide/agents/running-agents

[^11]: State Management with AG-UI — Microsoft Learn. https://learn.microsoft.com/en-us/agent-framework/integrations/ag-ui/state-management

[^12]: Dark Mode UI: Essential Tips for Color Palettes and Accessibility. https://www.wildnetedge.com/blogs/dark-mode-ui-essential-tips-for-color-palettes-and-accessibility

[^13]: AGUIChatClient Class — Microsoft Learn. https://learn.microsoft.com/en-us/dotnet/api/microsoft.agents.ai.agui.aguichatclient?view=agent-framework-dotnet-latest

[^14]: Blazor Splitter Overview — Telerik. https://www.telerik.com/blazor-ui/documentation/components/splitter/overview

[^15]: Blazorise Splitter component. https://blazorise.com/docs/extensions/splitter

[^16]: Blazor Splitter — Syncfusion. https://www.syncfusion.com/blazor-components/blazor-splitter

[^17]: Toolbelt.Blazor.SplitContainer — GitHub. https://github.com/jsakamoto/Toolbelt.Blazor.SplitContainer

[^18]: Code Highlight with Blazor — Laszlo. https://blog.ladeak.net/posts/blazor-code-highlight2

[^19]: BlazorMonaco — GitHub. https://github.com/serdarciplak/BlazorMonaco

[^20]: Monaco Editor — Microsoft. https://microsoft.github.io/monaco-editor/

[^22]: Monaco Editor: How to Input Content at Certain Positions — Medium. https://heliosyuhanliu.medium.com/monaco-editor-how-to-input-content-at-certain-positions-4166b1e4f233

[^24]: Dynamically-rendered ASP.NET Core Razor components — Microsoft Learn. https://learn.microsoft.com/en-us/aspnet/core/blazor/components/dynamiccomponent?view=aspnetcore-10.0

[^25]: ASP.NET Core Blazor advanced scenarios (render tree construction) — Microsoft Learn. https://learn.microsoft.com/en-us/aspnet/core/blazor/advanced-scenarios?view=aspnetcore-10.0

[^27]: Fluxor.Undo — GitHub. https://github.com/Pjotrtje/Fluxor.Undo

[^28]: Human-in-the-Loop with AG-UI — Microsoft Learn. https://learn.microsoft.com/en-us/agent-framework/integrations/ag-ui/human-in-the-loop

[^29]: Blazor Blueprint UI — Resizable component. https://blazorblueprintui.com/docs/components/resizable
