# **Implementing Agentic UX/UI Patterns with “Blazor Blueprint UI Library”: A Comprehensive Architectural Blueprint**

## **Executive Summary**

The emergence of Agentic Artificial Intelligence represents a fundamental shift in human-computer interaction, moving beyond the simple request-response paradigm of generative chat toward autonomous systems capable of reasoning, planning, tool execution, and collaborative problem-solving. This transition necessitates a radical reimagining of the User Experience (UX) layer. The traditional "chat stream" interface is insufficient for observing and controlling agents that operate non-linearly, maintain complex internal states, and interact with external systems. Users now require interfaces that provide high-fidelity observability into the agent's thought process, granular control over tool execution, and persistent visibility into long-running plans.

This report provides an exhaustive implementation strategy for constructing these advanced interfaces using the **Blazor Blueprint UI** library. Selected for its alignment with the "shadcn/ui" philosophy—emphasizing headless primitives, accessible defaults, and opt-in styling—Blazor Blueprint offers the requisite flexibility to build bespoke agentic components without the constraints of opinionated "Enterprise" frameworks like Material Design or Fluent UI.

We present a detailed architectural and design specification for implementing four core Agentic UX patterns: **Reflection**, **Tool Use**, **Planning**, and **Multi-Agent Collaboration**. Furthermore, we define a concrete, modern design system—codenamed **"Nebula"**—which leverages Blazor Blueprint's CSS variable infrastructure to deliver a sleek, high-contrast aesthetic in both light and dark modes, optimized for the cognitive demands of AI-assisted workflows. This document serves as a definitive guide for.NET architects and frontend engineers tasked with building the next generation of intelligent applications.

## ---

**1\. The Agentic UX Paradigm: From Chatbots to Systems**

The prevailing model of AI interaction, popularized by ChatGPT and Copilot, is the linear chat stream. This model assumes a synchronous, stateless exchange: the user provides a prompt, and the model returns a completion. However, **Agentic AI** breaks this model.1 Agents do not merely complete text; they perform loops of thought, execute code, query databases, and correct their own errors before presenting a final result.

### **1.1 The Limitations of Linear Chat**

In a standard chat interface, an agent's internal reasoning, tool outputs, and error recovery steps are either hidden (creating a "Black Box" that erodes trust) or dumped into the stream as raw text (creating "Cognitive Overload"). When an agent is tasked with a complex objective—such as "Refactor this legacy microservice"—it engages in a multi-step process that may span minutes or hours. A linear stream fails to capture the *structure* of this work. It cannot effectively display the hierarchical relationship between a high-level plan and the low-level execution logs, nor can it clearly distinguish between the "voice" of the planner, the executor, and the reviewer in a multi-agent system.3

### **1.2 The Four Pillars of Agentic Interaction**

Research into autonomous systems identifies four critical behavioral patterns that the UI must visualize to ensure usability and safety 1:

1. **Reflection (Self-Correction):** The agent generates a draft, critiques it against constraints, and refines the output. The UI must distinguish between the "rough work" and the "final product," allowing the user to inspect the reasoning without cluttering the main view.  
2. **Tool Use (External Action):** Agents interact with the outside world via APIs and scripts. The UI must serve as a "flight recorder" for these actions, providing clear visualization of inputs and outputs, and acting as a security gate for sensitive operations.  
3. **Planning (Decomposition):** Complex goals are broken down into sequential steps. The UI must render this plan as a persistent, mutable object—a dynamic roadmap that updates as the agent progresses, encounters blockers, or re-plans.  
4. **Multi-Agent Collaboration (Orchestration):** Specialized agents collaborate to solve problems. The UI must clarify *who* is acting at any given moment, separating the "Manager" from the "Worker" to help the user understand the division of labor.

### **1.3 The Role of Blazor Blueprint UI**

To implement these complex patterns, the component library must offer composability and customization. **Blazor Blueprint UI** 6 is uniquely suited for this task. Unlike monolithic libraries that enforce a rigid visual style (e.g., MudBlazor's implementation of Material Design), Blazor Blueprint follows the "shadcn" architecture. It provides:

* **Headless Primitives:** Components that handle logic and accessibility (focus management, keyboard navigation) but allow full control over markup and styling. This is essential for creating novel agentic components like "Thought Accordions" or "Plan Drawers."  
* **Tailwind/CSS Utility Integration:** The library uses standard CSS variables and utility classes, making it trivial to implement complex theming engines like the one proposed in this report.7  
* **Rich Iconography:** Integrated support for Lucide icons allows for precise semantic labeling of agent actions (e.g., distinguishing "Thinking" from "Searching" or "Writing").7

## ---

**2\. The Architectural Canvas: Blazor Blueprint UI Configuration**

Before diving into the specific UX patterns, we must establish the technical foundation. Blazor Blueprint UI is not just a collection of widgets; it is a framework for building design systems. Its architecture relies on the separation of *structure* (Razor components) from *style* (CSS variables and utility classes).

### **2.1 Library Philosophy and Selection Rationale**

In the context of.NET development, the choice of UI library often dictates the application's look and feel. Traditional options like **MudBlazor** or **Radzen** 8 are excellent for internal enterprise dashboards but struggle to achieve the "sleek," consumer-grade aesthetic required for modern AI tools. Their heavy reliance on inline styles and rigid DOM structures makes it difficult to implement the subtle transitions, glassmorphism, and custom layouts that define the "Nebula" theme.

**Blazor Blueprint**, conversely, acts as a thin wrapper around accessible HTML primitives. It mimics the **Radix UI** primitives used in the React ecosystem, which dominates the current wave of AI applications (e.g., Vercel's AI SDK demos). By adopting Blazor Blueprint, we bring this modern, flexible architecture to Blazor Server and WebAssembly.6 This allows us to build interfaces that are visually indistinguishable from top-tier React applications while leveraging the type safety and performance of C\# and.NET.7

### **2.2 Project Setup and Dependency Injection**

To begin, the project structure must support the granular customization required by the agentic patterns. We recommend a modular architecture where UI components are decoupled from the agent logic.

**Nuget Packages:**

* BlazorBlueprint.Components: The core library containing the Razor components.  
* BlazorBlueprint.Icons: The Lucide icon set integration.7  
* Fluxor.Blazor.Web: For managing the complex state of the agent (e.g., current plan status, reflection history).

**Service Registration:**

In Program.cs, we register the Blueprint services along with our custom theming service. The theming service will be responsible for hot-swapping CSS variables based on user preference, a critical requirement for the "Light/Dark" mode requested.

C\#

builder.Services.AddBlazorBlueprint();  
builder.Services.AddScoped\<IThemeService, ThemeService\>();  
builder.Services.AddFluxor(options \=\> options.ScanAssemblies(typeof(Program).Assembly));

### **2.3 The CSS Architecture**

Blazor Blueprint relies on a global app.css that defines CSS variables for semantic colors (e.g., \--primary, \--secondary, \--muted). This is the control plane for our design system. Instead of hardcoding hex values into components, we will map every component property to these variables. This abstraction layer allows us to implement the "Nebula" theme by simply changing the variable values at the :root level, without touching a single line of Razor code.10

## ---

**3\. The Visual Design System: Project "Nebula"**

To support the high cognitive load of agentic workflows, the visual design must be unobtrusive yet information-dense. We define the **"Nebula"** design system, a custom implementation of the Blazor Blueprint tokens. "Nebula" is characterized by deep, receded backgrounds that minimize eye strain, coupled with luminous, high-contrast accents that guide attention to active agent processes.12

### **3.1 Design Theory: Sleek Modernism**

The "Sleek" aesthetic demanded by the user query 12 is not merely about dark colors; it is about *precision*. It involves:

* **Reduction of Borders:** Using distinct background shades (--card vs \--background) rather than heavy borders to define layout.  
* **Subtle Depth:** Utilizing the backdrop-filter: blur() property (Glassmorphism) to create a sense of layering. This is particularly effective for floating elements like the "Plan Drawer" or "Tool Approval Dialog," suggesting they exist *above* the chat stream.  
* **Typography:** We select **Inter** for the UI font due to its excellent readability at small sizes and **JetBrains Mono** for code blocks and agent logs. The juxtaposition of variable-width and fixed-width fonts helps visually distinguish "human" conversational text from "machine" technical output.

### **3.2 The Color Palette**

We define two high-fidelity modes: **"Deep Space"** (Dark) and **"Ceramic"** (Light). These palettes are implemented as CSS variables that override the Blazor Blueprint defaults.

#### **3.2.1 Dark Mode: "Deep Space"**

This mode is designed for prolonged usage. The background is not pure black (\#000000) but a very dark zinc (\#09090b), which is softer on the eyes. The primary accent is an "Electric Violet" to "Cyan" gradient, representing the synthetic nature of the AI.13

| Variable Token | Hex Value | Usage Context |
| :---- | :---- | :---- |
| \--background | \#09090b | Main application canvas. |
| \--foreground | \#fafafa | Primary text content. |
| \--card | \#18181b | Background for chat bubbles and panels. |
| \--card-foreground | \#fafafa | Text within cards. |
| \--popover | \#09090b | Dropdowns and dialogs. |
| \--primary | \#8b5cf6 | **Electric Violet**. Used for "Submit" buttons and active states. |
| \--primary-foreground | \#ffffff | Text on primary buttons. |
| \--secondary | \#27272a | Muted buttons, inactive tabs. |
| \--secondary-foreground | \#a1a1aa | Text on secondary elements. |
| \--muted | \#27272a | Backgrounds for "Thinking" blocks. |
| \--muted-foreground | \#71717a | Metadata, timestamps, non-essential text. |
| \--destructive | \#7f1d1d | Error states or "Stop Generation" actions. |
| \--border | \#27272a | Subtle dividers. |
| \--ring | \#8b5cf6 | Focus rings for accessibility. |

#### **3.2.2 Light Mode: "Ceramic"**

The light mode mimics the aesthetic of a clean laboratory. It uses high-brightness whites and cool grays, with a "Deep Azure" accent to maintain contrast and professionalism.

| Variable Token | Hex Value | Usage Context |
| :---- | :---- | :---- |
| \--background | \#ffffff | Pure white canvas. |
| \--foreground | \#09090b | High-contrast black text. |
| \--card | \#ffffff | White cards with subtle shadow (no borders). |
| \--primary | \#2563eb | **Deep Azure**. Professional, trustworthy blue. |
| \--primary-foreground | \#ffffff | White text on primary. |
| \--secondary | \#f4f4f5 | Very light gray for secondary grouping. |
| \--muted | \#f4f4f5 | Backgrounds for secondary content. |
| \--muted-foreground | \#52525b | Medium gray for metadata. |
| \--border | \#e4e4e7 | Light gray dividers. |

### **3.3 Implementation in CSS**

The following CSS block illustrates how these variables are defined to work with Blazor Blueprint's component classes. Note the use of the .dark class selector, which allows for instant theme switching via JavaScript interop.10

CSS

:root {  
    /\* Default Light Mode ("Ceramic") \*/  
    \--background: 0 0% 100%;  
    \--foreground: 240 10% 3.9%;  
    \--card: 0 0% 100%;  
    \--card-foreground: 240 10% 3.9%;  
    \--popover: 0 0% 100%;  
    \--popover-foreground: 240 10% 3.9%;  
    \--primary: 221.2 83.2% 53.3%;  
    \--primary-foreground: 210 40% 98%;  
    \--secondary: 240 4.8% 95.9%;  
    \--secondary-foreground: 240 5.9% 10%;  
    \--muted: 240 4.8% 95.9%;  
    \--muted-foreground: 240 3.8% 46.1%;  
    \--accent: 240 4.8% 95.9%;  
    \--accent-foreground: 240 5.9% 10%;  
    \--destructive: 0 84.2% 60.2%;  
    \--destructive-foreground: 0 0% 98%;  
    \--border: 240 5.9% 90%;  
    \--input: 240 5.9% 90%;  
    \--ring: 221.2 83.2% 53.3%;  
    \--radius: 0.5rem;  
}

.dark {  
    /\* Dark Mode ("Deep Space") \*/  
    \--background: 240 10% 3.9%;  
    \--foreground: 0 0% 98%;  
    \--card: 240 10% 3.9%;  
    \--card-foreground: 0 0% 98%;  
    \--popover: 240 10% 3.9%;  
    \--popover-foreground: 0 0% 98%;  
    \--primary: 263.4 70% 50.4%; /\* Electric Violet \*/  
    \--primary-foreground: 210 40% 98%;  
    \--secondary: 240 3.7% 15.9%;  
    \--secondary-foreground: 0 0% 98%;  
    \--muted: 240 3.7% 15.9%;  
    \--muted-foreground: 240 5% 64.9%;  
    \--accent: 240 3.7% 15.9%;  
    \--accent-foreground: 0 0% 98%;  
    \--destructive: 0 62.8% 30.6%;  
    \--destructive-foreground: 0 0% 98%;  
    \--border: 240 3.7% 15.9%;  
    \--input: 240 3.7% 15.9%;  
    \--ring: 263.4 70% 50.4%;  
}

This setup ensures that all Blazor Blueprint components—buttons, inputs, dialogs—automatically inherit the "Nebula" theme without needing individual styling.

## ---

**4\. Pattern I: Reflection (The "Glass Box" Interface)**

The Reflection pattern addresses the issue of trust in AI responses. When an agent produces an answer immediately, the user has no insight into the validity of that answer. By visualizing the **Reflection Loop**—the process where an agent critiques its own work—we convert latency into a trust-building mechanism.1 The UI must effectively display the "Internal Monologue" separately from the "External Response."

### **4.1 Architectural Challenge**

The challenge lies in representing a recursive process within a linear stream. An agent might draft a response, critique it, realize it's missing a citation, search for the citation, update the draft, and then finalize it. A standard chat bubble cannot contain this complexity without becoming unreadable.

### **4.2 Blazor Implementation: The Collapsible Thought Stream**

We utilize the **Accordion** component from Blazor Blueprint to create a "Thought Stream" container. This container sits *above* the final response bubble, collapsed by default, but pulsing gently to indicate activity during generation.

**Component Structure:**

* AgentResponseContainer.razor: The parent wrapper.  
* ThoughtStream.razor: Uses the Accordion component.  
* FinalContent.razor: Uses the Card component.

**Key Visual Indicators:**

1. **Draft State:** While the agent is "thinking," the Accordion is active. We use a CSS animation on the border color (animate-pulse) using the \--primary variable to show liveness.  
2. **Critique Blocks:** Inside the expanded accordion, individual steps of the reflection are rendered as small, distinct blocks. We use the Badge component to label the *type* of reflection (e.g., \<Badge Variant="Outline"\>Critique\</Badge\>, \<Badge Variant="Secondary"\>Revision\</Badge\>).  
3. **Finalization:** Once the reflection loop concludes, the Accordion automatically collapses (or stays collapsed), and the FinalContent card fades in (opacity-0 to opacity-100 transition).

### **4.3 Detailed Code Strategy**

The ThoughtStream component binds to a generic list of ReflectionStep objects. As the agent streams these steps via SignalR, the UI updates in real-time.

Razor CSHTML

@if (Steps.Any())  
{  
    \<Accordion Type="AccordionType.Single" Collapsible="true" Class="mb-4 border border-border rounded-lg bg-muted/50"\>  
        \<AccordionItem Value="thoughts"\>  
            \<AccordionTrigger Class="px-4 py-2 text-sm text-muted-foreground hover:text-foreground transition-colors"\>  
                \<div class="flex items-center gap-2"\>  
                    \<LucideBrain Class="w-4 h-4" /\>  
                    \<span\>Process Log (@Steps.Count steps)\</span\>  
                    @if (IsThinking)  
                    {  
                        \<LucideLoader2 Class="w-3 h-3 animate-spin text-primary" /\>  
                    }  
                \</div\>  
            \</AccordionTrigger\>  
            \<AccordionContent\>  
                \<div class="p-4 space-y-3"\>  
                    @foreach (var step in Steps)  
                    {  
                        \<div class="flex flex-col gap-1"\>  
                            \<div class="flex items-center gap-2"\>  
                                \<Badge Variant="BadgeVariant.Outline" Class="text-xs"\>@step.Type\</Badge\>  
                                \<span class="text-xs text-muted-foreground"\>@step.Timestamp\</span\>  
                            \</div\>  
                            \<p class="text-sm font-mono text-foreground/80 pl-2 border-l-2 border-border"\>  
                                @step.Content  
                            \</p\>  
                        \</div\>  
                    }  
                \</div\>  
            \</AccordionContent\>  
        \</AccordionItem\>  
    \</Accordion\>  
}

**Insight:** By using the monospace font (font-mono) for the reflection content, we visually reinforce that this is "machine thought," distinct from the "human-like" conversation in the final response. This subtle typographic cue helps users mentally categorize the information, reducing cognitive load while maintaining transparency.

## ---

**5\. Pattern II: Tool Use (The Cockpit Interface)**

The Tool Use pattern represents the agent's ability to affect the external world. This is the most dangerous capability and thus requires the strictest UI controls. The interface acts as a **Cockpit**, offering instruments to monitor tool execution and controls to authorize or abort actions.1

### **5.1 Architectural Challenge**

Tools vary wildly in their input/output structure. A "Weather" tool returns simple JSON; a "Database" tool returns rows and columns; a "File System" tool might return a diff. The UI cannot be a static template. It must be polymorphic, adapting its presentation to the specific tool being used. Furthermore, for sensitive tools (e.g., DELETE FROM users), the UI must enforce a **Human-in-the-Loop** authorization step.

### **5.2 Blazor Implementation: Command, Dialog, and DataTable**

We leverage three specific Blazor Blueprint components to manage the tool lifecycle:

1. **Discovery (The Command Palette):**  
   The **Command** component (modeled after the cmd+k interface) allows users to see which tools are available to the agent. This is not just a menu; it is an active state viewer. If an agent is searching for a tool, the Command palette can programmatically open to show the search process.  
   * *Implementation:* A global CommandDialog component that lists tools categorized by domain (e.g., "Data Access", "System", "Communication").  
2. **Authorization (The Approval Dialog):**  
   When an agent invokes a sensitive tool, the workflow pauses. We use the **Dialog** component to create a modal interruption.  
   * *Design:* The dialog must be alarming but clear. We use the \--destructive color variable for the "Approve" button if the action is destructive.  
   * *Content:* The dialog body displays the raw arguments of the tool call in a code block, ensuring the user knows exactly *what* is about to happen.  
3. **Observability (The Result Table):** For tools that return structured data, dumping JSON is unacceptable. We use the **DataTable** component.8 This component supports sorting, filtering, and pagination out of the box.  
   * *Strategy:* When a tool returns a list of objects, we dynamically reflect over the properties to generate the DataTable columns. This allows the agent to display a list of Jira tickets, SQL rows, or weather forecasts using a single, reusable UI component.

### **5.3 Detailed Code Strategy: Dynamic Tool Rendering**

We create a ToolOutputRenderer.razor that acts as a factory, choosing the right visualization based on the tool's return type.

Razor CSHTML

@switch (Output.Type)  
{  
    case ToolOutputType.Text:  
        \<div class="bg-muted p-3 rounded-md text-sm font-mono"\>@Output.Data\</div\>  
        break;

    case ToolOutputType.Json:  
        \<pre class="bg-muted p-3 rounded-md text-xs overflow-x-auto"\>@Output.Data\</pre\>  
        break;

    case ToolOutputType.Table:  
        \<div class="border rounded-md"\>  
            \<Table\>  
                \<TableHeader\>  
                    \<TableRow\>  
                        @foreach (var header in Output.Headers)  
                        {  
                            \<TableHead\>@header\</TableHead\>  
                        }  
                    \</TableRow\>  
                \</TableHeader\>  
                \<TableBody\>  
                    @foreach (var row in Output.Rows)  
                    {  
                        \<TableRow\>  
                            @foreach (var cell in row)  
                            {  
                                \<TableCell\>@cell\</TableCell\>  
                            }  
                        \</TableRow\>  
                    }  
                \</TableBody\>  
            \</Table\>  
        \</div\>  
        break;  
}

**Insight:** By rendering tool outputs as rich UI elements (tables, charts) rather than text, we empower the user to *verify* the agent's findings. If the agent says "I found 5 users," the user can glance at the Table to confirm. This eliminates the "hallucination gap" where an agent misinterprets the data it retrieved.

## ---

**6\. Pattern III: Planning (The Dynamic Roadmap)**

Planning is the hallmark of advanced agentic systems. It involves breaking a high-level goal ("Build a website") into a dependency graph of sub-tasks.1 In a typical chat, the plan scrolls off-screen, causing the user (and often the agent, via context window loss) to lose track of the broader objective. The UI solution is **Persistence**.

### **6.1 Architectural Challenge**

The plan is not static text; it is a mutable state machine. Tasks change from Pending ![][image1] InProgress ![][image1] Completed or Failed. New tasks are injected; redundant tasks are pruned. The UI must represent this dynamism without disorienting the user.

### **6.2 Blazor Implementation: The Persistent Sheet**

We use the **Sheet** component (also known as a Drawer or Slide-over) from Blazor Blueprint to house the plan. Unlike a sidebar, the Sheet can be toggled to overlay the content or sit alongside it, providing a persistent context zone.

**Visual Structure:**

1. **Global Progress:** At the top of the Sheet, a **Progress** bar shows the overall completion percentage of the plan. This provides an immediate "health check" on the mission.  
2. **The Task Graph:** We use a nested list of **Card** components to represent the task hierarchy.  
3. **Status Icons:** We lean heavily on Lucide icons to convey state:  
   * Circle: Pending (Gray)  
   * Loader2: In Progress (Blue, Animate-Spin)  
   * CheckCircle2: Completed (Green)  
   * XCircle: Failed (Red)

### **6.3 Detailed Code Strategy: Reactive Plan Updates**

The PlanSheet.razor component subscribes to the AgentPlanState via Fluxor. When the agent updates its internal plan (e.g., marks task 2 as done), the UI re-renders automatically.

Razor CSHTML

\<Sheet @bind-Open="IsOpen"\>  
    \<SheetContent Side="Side.Right" Class="w-\[400px\] sm:w-\[540px\] overflow-y-auto"\>  
        \<SheetHeader\>  
            \<SheetTitle\>Mission Plan\</SheetTitle\>  
            \<SheetDescription\>  
                Current objective: @CurrentObjective  
            \</SheetDescription\>  
        \</SheetHeader\>  
          
        \<div class="py-6 space-y-6"\>  
            \<div class="space-y-2"\>  
                \<div class="flex justify-between text-sm"\>  
                    \<span\>Progress\</span\>  
                    \<span class="text-muted-foreground"\>@PercentComplete%\</span\>  
                \</div\>  
                \<Progress Value="@PercentComplete" Class="h-2" /\>  
            \</div\>

            \<div class="space-y-4"\>  
                @foreach (var task in Tasks)  
                {  
                    \<Card Class="@GetTaskClass(task)"\>  
                        \<CardHeader Class="p-4 flex flex-row items-start gap-3 space-y-0"\>  
                            \<div class="mt-1"\>  
                                @if (task.Status \== TaskStatus.Running)  
                                {  
                                    \<LucideLoader2 Class="w-5 h-5 text-primary animate-spin" /\>  
                                }  
                                else if (task.Status \== TaskStatus.Completed)  
                                {  
                                    \<LucideCheckCircle2 Class="w-5 h-5 text-green-500" /\>  
                                }  
                                else  
                                {  
                                    \<LucideCircle Class="w-5 h-5 text-muted-foreground" /\>  
                                }  
                            \</div\>  
                              
                            \<div class="flex-1 space-y-1"\>  
                                \<CardTitle Class="text-sm font-medium leading-none"\>  
                                    @task.Title  
                                \</CardTitle\>  
                                \<CardDescription\>  
                                    @task.Description  
                                \</CardDescription\>  
                            \</div\>  
                        \</CardHeader\>  
                    \</Card\>  
                }  
            \</div\>  
        \</div\>  
    \</SheetContent\>  
\</Sheet\>

**Insight:** The use of the Sheet component is strategic. By placing the plan in a separate visual layer (the "Meta-Layer"), we reinforce that the Plan is the *controller* of the chat stream, not a product of it. It allows the user to browse the plan while the agent is generating text in the main window, facilitating multi-tasking and review.

## ---

**7\. Pattern IV: Multi-Agent Orchestration (The Council Interface)**

Multi-agent systems introduce the complexity of "Who is speaking?" A system might have a "Researcher" agent, a "Coder" agent, and a "Reviewer" agent.3 A linear chat that mixes these voices creates confusion. The UI must provide clear **Attribution** and **Context Isolation**.

### **7.1 Architectural Challenge**

Each agent has its own context (memory), tools, and persona. The UI needs to group messages by agent and potentially show the hand-off process ("Manager Agent delegates task to Coder Agent").

### **7.2 Blazor Implementation: Avatars, Badges, and Swimlanes**

We use a combination of components to create a structured conversation view:

1. **Identity (Avatars & Badges):**  
   Every message block is prefixed with an **Avatar** component. We use distinct icons (not just photos) to represent roles: a LucideTerminal for the Coder, a LucideBook for the Researcher. Next to the name, a **Badge** (e.g., Variant="Secondary") explicitly states the role.  
2. **Context Switching (Tabs):**  
   For advanced debugging, we offer a **Tabs** component in the sidebar. This allows the user to switch views and see the *private* context of each agent.  
   * *Tab 1: Main Stream* (The public conversation)  
   * *Tab 2: Researcher Memory* (See what documents it has indexed)  
   * *Tab 3: Coder Workspace* (See the file definitions it is holding)  
3. **Handoff Visualization:**  
   When control passes from one agent to another, we insert a specialized Separator component with a label, creating a visual break in the stream.

### **7.3 Detailed Code Strategy: The Agent Message Component**

This component encapsulates the identity and content of a single turn in the conversation.

Razor CSHTML

\<div class="flex gap-4 p-4 group hover:bg-muted/50 transition-colors"\>  
    \<div class="flex-shrink-0 flex flex-col items-center gap-2"\>  
        \<Avatar Class="w-10 h-10 border border-border"\>  
            \<AvatarImage Src="@Agent.AvatarUrl" /\>  
            \<AvatarFallback\>@Agent.Initials\</AvatarFallback\>  
        \</Avatar\>  
        \<Badge Variant="BadgeVariant.Outline" Class="text-\[10px\] px-1 py-0 h-5"\>  
            @Agent.Role  
        \</Badge\>  
    \</div\>

    \<div class="flex-1 space-y-2 min-w-0"\>  
        \<div class="flex items-center justify-between"\>  
            \<span class="font-semibold text-sm"\>@Agent.Name\</span\>  
            \<span class="text-xs text-muted-foreground"\>@Timestamp\</span\>  
        \</div\>  
          
        \<div class="prose prose-sm dark:prose-invert max-w-none"\>  
            @Content  
        \</div\>

        @if (HasAttachments)  
        {  
            \<div class="mt-4 pt-4 border-t border-border"\>  
                @ChildContent  
            \</div\>  
        }  
    \</div\>  
\</div\>

**Insight:** The vertical alignment of the Avatar with the content creates a "Swimlane" effect. Even without distinct background colors, the spatial arrangement helps the user track the conversation flow. The Badge provides a quick semantic lookup ("Oh, the *Reviewer* is speaking now, so this is a critique").

## ---

**8\. Technical Integration and State Management**

Implementing these four patterns requires a robust backend architecture to drive the Blazor UI. The UI cannot simply "react" to text chunks; it must react to *state changes*.

### **8.1 State Management with Fluxor**

We recommend **Fluxor** (a Redux implementation for Blazor) to manage the application state. The agentic workflow is too complex for standard CascadingParameter passing.

**Store Structure:**

* AgentState: Holds the current status (Idle, Thinking, ExecutingTool).  
* ChatState: Holds the list of messages (polymorphic list including TextMessage, ToolMessage, ThoughtMessage).  
* PlanState: Holds the hierarchy of tasks for the Planning pattern.

**Action Dispatching:**

When the backend agent (e.g., running via Semantic Kernel or LangChain) emits an event, we dispatch a Fluxor action:

* AgentStartedThinkingAction ![][image1] Triggers the Accordion pulse animation.  
* ToolExecutionRequestedAction ![][image1] Opens the Dialog modal.  
* PlanUpdatedAction ![][image1] Refreshes the Sheet content.

### **8.2 Streaming and Latency**

Agentic responses can be slow. Blazor Server uses SignalR, which is ideal for streaming. However, rendering Markdown in real-time can be CPU intensive.

* **Optimization:** Use Markdig for parsing Markdown but implement a "debounce" mechanism in the UI. Only re-render the MarkupString every 50-100ms, rather than on every single token, to prevent UI freeze during high-speed generation.

### **8.3 Mobile Responsiveness**

The "Nebula" theme and Blazor Blueprint components are mobile-first (via Tailwind).

* **Adaptation:**  
  * The Sheet (Plan) behaves as a slide-over on desktop but should act as a bottom-sheet on mobile.  
  * The Command palette should take up the full screen on mobile devices.  
  * Table components in the Tool Use pattern must enable horizontal scrolling (overflow-x-auto) on small screens to prevent layout breakage.

## ---

**9\. Conclusion**

The transition from "Chatbot" to "Agent" is not merely an algorithmic upgrade; it is an interface revolution. By adopting **Blazor Blueprint UI**, we gain the architectural freedom to build the novel components this revolution requires—**Reflection Streams**, **Tool Cockpits**, **Dynamic Plans**, and **Collaborative Swimlanes**.

The "Nebula" design system proposed here ensures that these complex interactions are presented with clarity and elegance. By leveraging deep contrast, semantic color coding, and rigorous typographic hierarchy, we create an environment where users can trust and effectively collaborate with autonomous AI systems. This blueprint provides the necessary foundation for engineering teams to move beyond the experimental phase and deliver production-grade, agentic AI applications within the.NET ecosystem.

This report confirms that the "shadcn" philosophy of headless primitives combined with Tailwind utility classes is the optimal path for the rapid, high-fidelity development required in the fast-moving AI sector. The specific implementation of the four UX patterns outlined above transforms the "Black Box" of AI into a "Glass Box," ensuring that as our systems become more intelligent, they also become more intelligible.

#### **Works cited**

1. Agentic Design Patterns. From reflection to collaboration… | by Bijit Ghosh \- Medium, accessed February 8, 2026, [https://medium.com/@bijit211987/agentic-design-patterns-cbd0aae2962f](https://medium.com/@bijit211987/agentic-design-patterns-cbd0aae2962f)  
2. Agentic AI Systems \- Fireworks AI, accessed February 8, 2026, [https://fireworks.ai/blog/agentic-ai-systems](https://fireworks.ai/blog/agentic-ai-systems)  
3. AI Agent Design Patterns \-A Strategic Guide for CXOs \- Lightrains, accessed February 8, 2026, [https://lightrains.com/blogs/ai-agent-design-patterns-cxo/](https://lightrains.com/blogs/ai-agent-design-patterns-cxo/)  
4. Agent design pattern catalogue: A collection of architectural patterns for foundation model based agents | Request PDF \- ResearchGate, accessed February 8, 2026, [https://www.researchgate.net/publication/385826836\_Agent\_design\_pattern\_catalogue\_A\_collection\_of\_architectural\_patterns\_for\_foundation\_model\_based\_agents](https://www.researchgate.net/publication/385826836_Agent_design_pattern_catalogue_A_collection_of_architectural_patterns_for_foundation_model_based_agents)  
5. Top 4 Agentic AI Design Patterns for Architecting AI Systems \- Analytics Vidhya, accessed February 8, 2026, [https://www.analyticsvidhya.com/blog/2024/10/agentic-design-patterns/](https://www.analyticsvidhya.com/blog/2024/10/agentic-design-patterns/)  
6. I built Blazor Blueprint — a shadcn/ui inspired component library for Blazor (65+ components, free & open source) \- Reddit, accessed February 8, 2026, [https://www.reddit.com/r/Blazor/comments/1qvp45q/i\_built\_blazor\_blueprint\_a\_shadcnui\_inspired/](https://www.reddit.com/r/Blazor/comments/1qvp45q/i_built_blazor_blueprint_a_shadcnui_inspired/)  
7. Blazor Blueprint — shadcn/ui inspired component library with 65+ components (free, open source) : r/dotnet \- Reddit, accessed February 8, 2026, [https://www.reddit.com/r/dotnet/comments/1qwjxr3/blazor\_blueprint\_shadcnui\_inspired\_component/](https://www.reddit.com/r/dotnet/comments/1qwjxr3/blazor_blueprint_shadcnui_inspired_component/)  
8. r/Blazor \- Reddit, accessed February 8, 2026, [https://www.reddit.com/r/Blazor/rising/](https://www.reddit.com/r/Blazor/rising/)  
9. A fully customizable and extensible all-purpose diagrams library for Blazor \- GitHub, accessed February 8, 2026, [https://github.com/Blazor-Diagrams/Blazor.Diagrams](https://github.com/Blazor-Diagrams/Blazor.Diagrams)  
10. Build a dark mode switch | Calcite Design System \- Esri Developer, accessed February 8, 2026, [https://developers.arcgis.com/calcite-design-system/tutorials/build-a-dark-mode-switch/](https://developers.arcgis.com/calcite-design-system/tutorials/build-a-dark-mode-switch/)  
11. UI Guidelines \- digital blueprint handbook, accessed February 8, 2026, [https://handbook.digital-blueprint.org/frameworks/frontend/dev/ui\_guideline/](https://handbook.digital-blueprint.org/frameworks/frontend/dev/ui_guideline/)  
12. Dark Mode UI: Essential Tips for Color Palettes and Accessibility, accessed February 8, 2026, [https://www.wildnetedge.com/blogs/dark-mode-ui-essential-tips-for-color-palettes-and-accessibility](https://www.wildnetedge.com/blogs/dark-mode-ui-essential-tips-for-color-palettes-and-accessibility)  
13. The Best 20+ Color Combinations For Better Landing Pages (2026) | LandingPageFlow, accessed February 8, 2026, [https://www.landingpageflow.com/post/best-color-combinations-for-better-landing-pages](https://www.landingpageflow.com/post/best-color-combinations-for-better-landing-pages)  
14. Top 10 UI Trends in 2025 You Must Follow 🚀 \- DEV Community, accessed February 8, 2026, [https://dev.to/ananiket/top-10-ui-trends-in-2025-you-must-follow-3l64](https://dev.to/ananiket/top-10-ui-trends-in-2025-you-must-follow-3l64)  
15. Introducing dark mode for Datadog, accessed February 8, 2026, [https://www.datadoghq.com/blog/introducing-datadog-darkmode/](https://www.datadoghq.com/blog/introducing-datadog-darkmode/)  
16. Dark Mode in 3 Lines of CSS and Other Adventures \- DEV Community, accessed February 8, 2026, [https://dev.to/madsstoumann/dark-mode-in-3-lines-of-css-and-other-adventures-1ljj](https://dev.to/madsstoumann/dark-mode-in-3-lines-of-css-and-other-adventures-1ljj)  
17. r/Blazor \- Reddit, accessed February 8, 2026, [https://www.reddit.com/r/Blazor/top/](https://www.reddit.com/r/Blazor/top/)

[image1]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABMAAAAXCAYAAADpwXTaAAAAbklEQVR4XmNgGAWjgGpADIgXQmmKAScQbwZiD3QJckEGEC9DF6QEmEEx1cB9II4CYmZkwUdk4i9A/B+I7zBQCLiBeAYDJEIoAoxA3AzErOgS5ABjID6OLkgOEAHi/UCsiS5BDgDFnDCUHgWDCQAAE6YW9xAxdJUAAAAASUVORK5CYII=>