# **Architectural Specification for Agentic User Experiences: Integrating Blazor, AG-UI, and Generative Components**

## **1\. Introduction: The Paradigm Shift to Agentic Interfaces**

The evolution of software interfaces is currently undergoing a seismic shift, transitioning from the static, imperative command-and-control models of the last decade to the dynamic, intent-driven paradigms of "Agentic" User Experience (UX). In traditional applications, the user interface (UI) is a fixed map of the application's capabilities; users must navigate menus, forms, and buttons to translate their intent into actions the system can understand. Agentic UX inverts this relationship. The interface becomes a fluid, collaborative canvas where the user declares an intent, and an Artificial Intelligence (AI) agent orchestrates the necessary tools, data retrieval, and interface generation to fulfill that intent.

This report provides an exhaustive architectural specification for implementing such a system within the.NET ecosystem. Specifically, it focuses on the convergence of **Blazor**—Microsoft’s framework for building interactive client-side web UI with.NET—and the **AG-UI (Agent Gateway User Interface)** protocol, a standardized mechanism for decoupling AI reasoning from frontend presentation. The objective is to define a blueprint for a robust, scalable system capable of supporting complex "Dual-Pane" layouts (context vs. artifact) and "Generative UI" (interfaces constructed at runtime by the agent).

The analysis draws upon the latest developments in the Microsoft Agent Framework,.NET Aspire orchestration, and advanced Blazor rendering techniques. It addresses the "Golden Triangle" of agentic development: the integration of a reactive Development UI (DevUI), the standardized communication protocol (AG-UI), and deep observability (OpenTelemetry).1 This report is intended for senior software architects and engineering leads, detailing the necessary infrastructure, protocol mechanics, and component design to build the next generation of intelligent applications.

## **2\. The Architectural Core: Decoupling Brain and Body**

The fundamental principle of the proposed architecture is the strict separation of the "Brain" (the cognitive agent) from the "Body" (the user interface). In legacy chatbot implementations, AI logic was often tightly coupled with the UI controller, leading to monolithic, unmaintainable codebases where UI latency could block AI reasoning and vice versa. The AG-UI protocol resolves this by establishing a contract-based distributed system.

### **2.1 The Distributed Agent Pattern**

The architecture necessitates a distributed system where the Agent Backend and the Blazor Frontend operate as independent services, orchestrated by a unifying host.

**The Agent Backend Service** The "Brain" resides in a dedicated ASP.NET Core web service. Its sole responsibility is to host the AI agent, manage the context window, execute server-side tools, and maintain the reasoning loop. By utilizing Microsoft.Agents.AI.Hosting.AGUI.AspNetCore, this service exposes the agent's capabilities via standard HTTP endpoints.2 This separation allows the compute-heavy and potentially sensitive operations of the LLM (Large Language Model) to remain secure on the server, insulated from the client browser.

**The Blazor Frontend Client** The "Body" is a Blazor Web App (supporting both Server and WebAssembly hosting models). It is the rendering engine, responsible for the "Last Mile" of the user experience. It utilizes the Microsoft.Agents.AI.AGUI client library to connect to the backend.4 The frontend is "dumb" in the sense that it does not contain business logic for the agent's reasoning; however, it is "smart" in its ability to dynamically adapt its layout and render interactive components based on instructions received from the Brain.

**Orchestration via.NET Aspire** To manage the complexity of these distributed services,.NET Aspire serves as the orchestration layer.5 Aspire handles service discovery, ensuring the Blazor frontend can locate the Agent backend without fragile hardcoded URLs. It injects configuration dynamically (e.g., AGUI\_SERVER\_URL) via environment variables, facilitating seamless transitions between local development environments and cloud deployments (e.g., Azure Container Apps).6

### **2.2 The AG-UI Protocol: Server-Sent Events (SSE) vs. SignalR**

A critical architectural decision in building real-time agentic interfaces is the choice of transport protocol. While SignalR (WebSockets) has long been the default for real-time.NET applications, the AG-UI protocol and the broader GenAI industry have coalesced around Server-Sent Events (SSE).2

#### **2.2.1 The Case for SSE in LLM Streaming**

The interaction pattern of Generative AI is distinct: a single, small user prompt triggers a massive, continuous download of tokens, often lasting several seconds or minutes. This is fundamentally a unidirectional "Server Push" scenario.

| Feature                 | Server-Sent Events (SSE)             | SignalR (WebSockets)          | Agentic UX Suitability                      |
| :---------------------- | :----------------------------------- | :---------------------------- | :------------------------------------------ |
| **Directionality**      | Unidirectional (Server to Client)    | Bidirectional (Full Duplex)   | High (matches Token Streaming profile)      |
| **Connection Overhead** | Low (Single HTTP Request)            | High (Handshake, Keep-Alives) | SSE is preferred for latency sensitivity 7  |
| **Protocol**            | Standard HTTP/1.1 or HTTP/2          | Custom Protocol over TCP      | SSE passes easily through firewalls/proxies |
| **Reconnection**        | Native Browser Support (EventSource) | Requires Client Library Logic | SSE simplifies client complexity 8          |
| **Statefulness**        | Stateless HTTP (conceptually)        | Stateful "Hubs"               | SSE aligns better with RESTful agent APIs   |

Research indicates that SSE is superior for this specific use case because it eliminates the complexity of managing WebSocket connections and "sticky sessions" in load-balanced environments.9 The AG-UI protocol leverages this by using the text/event-stream MIME type to push AgentResponseUpdate objects to the client.4 This ensures that the user perceives the agent as "thinking" and "speaking" in real-time, significantly improving perceived latency compared to request-response models.

## **3\. Server-Side Implementation Strategy**

The server-side architecture is built upon the Microsoft.Agents.AI.Hosting.AGUI library. This library provides the middleware necessary to serialize agent events into the SSE stream defined by the AG-UI protocol.

### **3.1 Middleware Configuration and Routing**

The implementation of the server requires a precise configuration of the ASP.NET Core pipeline. The MapAGUI extension method is the primary entry point. It creates an endpoint that accepts POST requests (containing the chat history) and returns the SSE stream.

To ensure maintainability and testability, agents should not be instantiated directly in Program.cs. Instead, an "Agent Factory" pattern is recommended. This allows for the injection of scoped services—such as database contexts or vector search clients—into the agent's lifecycle.

The server setup involves registering the AG-UI services using builder.Services.AddAGUI() and then mapping the specific agent instance to a route, for example, app.MapAGUI("/agent", agentInstance).11 This mapping automatically handles the serialization of the AgentResponseUpdate objects, which serve as the envelope for all communication from the server to the client.

### **3.2 Tool Registration and Execution Models**

A defining feature of the AG-UI protocol is its support for "Backend Tool Rendering." In this model, the tools (C\# functions) are defined and executed on the server. The client is agnostic to the implementation details of these tools.

When an agent decides to call a tool (e.g., SearchDatabase), the server executes the function logic. The result is then streamed back to the client as part of the conversation history. However, the protocol also supports transmitting the *execution status* to the client. This allows the Blazor frontend to display granular status updates (e.g., "Scanning database...", "Processing results...") without knowing the internal logic of the tool.3 This transparency is crucial for user trust in agentic systems.

## **4\. Client-Side Integration: The Blazor AGUIChatClient**

The Blazor client is the consumer of the AG-UI stream. The integration point is the AGUIChatClient class, provided by the Microsoft.Agents.AI.AGUI package.4 This class implements the IChatClient interface, providing a standard surface area for interacting with the remote agent.

### **4.1 Dependency Injection and Lifecycle**

The AGUIChatClient relies on HttpClient for the underlying connection. In a Blazor Server application, the client should be registered as a Scoped service to ensure it is reused within a user's circuit but isolated between users. In Blazor WebAssembly, a Transient or Singleton registration is appropriate, depending on the authentication state management.

The client requires the base URL of the backend agent service. This URL is injected via the.NET Aspire configuration, ensuring that the frontend can dynamically locate the backend across different environments (dev, test, prod).6

### **4.2 Streaming Consumption with IAsyncEnumerable**

The core interaction loop in the Blazor component uses the GetStreamingResponseAsync method (or RunStreamingAsync in some preview versions).4 This method returns an IAsyncEnumerable\<AgentResponseUpdate\>.

Handling this stream requires careful attention to Blazor's rendering lifecycle. A naive implementation that calls StateHasChanged() for every incoming token (character) of text can lead to significant performance degradation, known as "render thrashing."

**Optimization Strategy:**

1. **Buffering:** Accumulate incoming text tokens into a buffer.  
2. **Throttling:** Update the UI state only after a set time interval (e.g., every 50ms) or after a certain number of tokens have been received.  
3. **Virtualization:** If the conversation history is long, use Blazor's \<Virtualize\> component to render only the visible messages, preventing the DOM from becoming bloated.

The AgentResponseUpdate object is polymorphic, containing different types of content that the client must handle:

* **TextContent:** The raw text of the agent's response.  
* **FunctionCallContent:** An instruction for the client to execute a client-side tool (discussed in Section 8).  
* **DataContent (State Snapshot):** A JSON representation of the agent's internal state, used for synchronization.10

## **5\. Dual-Pane Layout Architecture**

Agentic interfaces differ from standard chatbots by introducing a persistent "Artifact" area. The "Context" (chat) is on the left, and the "Artifact" (code, document, dashboard) is on the right. Implementing this in Blazor requires a robust Splitter component.

### **5.1 Component Selection: Splitter Libraries**

The research identifies three primary candidates for the Splitter component, each with distinct trade-offs for an enterprise-grade agentic application.

| Library                               | Component       | Key Features                                                                 | Suitability for Agentic UX                                                                          |
| :------------------------------------ | :-------------- | :--------------------------------------------------------------------------- | :-------------------------------------------------------------------------------------------------- |
| **Blazor Blueprint UI** (recommended) | Resizable       | Resizable panel layout with draggable handles and min/max constraints.29     | **High.** Open source, easy to customize, simple API, good performance, and easy state persistence. |
| **Telerik UI for Blazor**             | TelerikSplitter | Events for resize/collapse, min/max constraints, state persistence.14        | **High.** Robust eventing is crucial for saving layout preference.                                  |
| **Syncfusion Blazor**                 | SfSplitter      | Nested panes, collapsible capability, highly customizable API.16             | **High.** Nested panes allow for "Terminal" windows below the canvas.                               |
| **Blazorise**                         | Splitter        | Lightweight, integrates with Bootstrap/Bulma. Good for responsive styling.15 | **Medium.** Excellent if already using Blazorise for theming.                                       |

For this specification, the architectural recommendation is to use a component that supports **programmatic control** over pane sizes. This is essential because the agent may decide to "Expand the Canvas" to show a wide data grid, and the application must be able to respond to this intent by adjusting the splitter position programmatically.

### **5.2 State Persistence and Responsiveness**

Users expect their layout preferences to persist. The architecture must utilize Blazored.LocalStorage to save the splitter position.17

* **Mechanism:** Subscribe to the OnResize event of the splitter. Debounce the event (wait 500ms after the last drag) to avoid flooding the storage API. Save the percentage width of the sidebar.  
* **Initialization:** On OnInitializedAsync, retrieve the value and bind it to the Splitter's Size parameter.

**Mobile Responsiveness:**

Dual-pane layouts fail on mobile devices. The architecture requires a "Mode Switcher" service.

* **Desktop:** Render the Splitter with both panes visible.  
* **Mobile:** Render a single pane with a toggle button (Tab or Drawer) to switch between "Chat" and "Artifact" views. This detection can be done via CSS media queries or JavaScript Interop to query the viewport width.

## **6\. The Monaco Editor: The Core Artifact Component**

For agents capable of generating code or structured text (markdown), a simple text area is insufficient. The architecture mandates the integration of the **Monaco Editor** (the engine powering VS Code) to provide a rich, IDE-like experience.

### **6.1 Integration via BlazorMonaco**

BlazorMonaco is the standard wrapper for integrating Monaco into Blazor. It provides StandaloneCodeEditor and StandaloneDiffEditor components.18

**Critical Constraints:**

* **Render Mode:** Monaco is a JavaScript-heavy component. It requires an interactive render mode (InteractiveServer or InteractiveWebAssembly). It will fail to initialize in Static Server Rendering (SSR).19  
* **Enhanced Navigation:** Blazor's enhanced navigation (introduced in.NET 8\) interferes with the lifecycle of JavaScript components. The data-enhance-nav="false" attribute must be applied to links navigating to the editor page, or the editor must be manually disposed and re-initialized.19

### **6.2 The Diff Editor Pattern**

A key Agentic workflow is the "Review Changes" pattern. The agent proposes an edit, and the user views a side-by-side diff before accepting.

The StandaloneDiffEditor requires two distinct models: Original and Modified.

* **Original:** Represents the current state of the file.  
* **Modified:** Represents the agent's proposed state. To update the diff view programmatically, the application must use the SetModel API via the ref of the editor component.20

### **6.3 Programmatic Edits and executeEdits**

When the user clicks "Apply," the application must merge the changes. While replacing the entire text is simple (SetValue), preserving the user's undo stack requires the executeEdits API.

* **Mechanism:** Construct an IdentifiedSingleEditOperation in C\# that maps to the Monaco API. This operation defines the Range (start line/column, end line/column) and the Text to insert.  
* **Challenge:** The executeEdits API is complex to bridge via JS Interop.  
* **Recommendation:** For full-file replacements generated by an agent, SetValue is acceptable. For small, cursor-based insertions (e.g., "Insert code here"), executeEdits is required.22

## **7\. Generative UI: Dynamic Component Rendering**

The most advanced capability of an Agentic UX is **Generative UI**: the ability of the agent to construct user interfaces on the fly to best suit the data it is presenting. This moves beyond rendering static Markdown tables to rendering interactive Blazor components.

### **7.1 The DynamicComponent Architecture**

Blazor's \<DynamicComponent\> is the vehicle for this capability. It accepts a Type (the component class) and a Dictionary\<string, object\> (parameters).24

**The Component Registry:**

The architecture requires a registry service that maps "Tool Names" to "Component Types."

1. **Agent Action:** The agent executes a tool called ShowWeatherWidget with arguments {"city": "London"}.  
2. **Mapping:** The frontend registry looks up ShowWeatherWidget and finds the C\# type WeatherCard.razor.  
3. **Rendering:** The \<DynamicComponent\> is instantiated with Type=typeof(WeatherCard) and Parameters=new Dictionary\<string, object\> { { "City", "London" } }.

This decoupling allows the agent to "hallucinate" UI requirements (e.g., "I should show a chart here") by calling a tool, which the frontend then fulfills with a concrete component implementation.

### **7.2 Recursive UI Generation via RenderTreeBuilder**

For scenarios where the agent needs to generate a complex form (e.g., "Create a data entry form for this specific SQL schema"), \<DynamicComponent\> is too flat. The architecture must utilize the low-level RenderTreeBuilder.25

This enables the creation of a **JSON Schema Renderer**.

* **Input:** A JSON Schema provided by the agent.  
* **Process:** The renderer iterates recursively through the schema properties.  
* **Output:** It dynamically builds a render tree, injecting MudTextField, MudSelect, or MudDatePicker components based on the data types defined in the schema.25 This technique allows the application to render interfaces for data structures that did not exist when the application was compiled, providing true generative capability.

## **8\. State Management and Time Travel**

Agentic conversations are rarely linear. Users often want to edit a previous prompt, branching the conversation.

### **8.1 The Temporal State Graph**

The state cannot be a simple List\<Message\>. It must be modeled as a Directed Acyclic Graph (DAG) where each node is a message state.

* **Fluxor Integration:** The **Fluxor** library (a Redux implementation for Blazor) is recommended for managing this complex state.27  
* **Actions:** Dispatch(new EditMessageAction(id, newText)).  
* **Reducers:** The reducer does not mutate the existing message. It creates a new message node and links it as a sibling to the original, creating a new "branch."

### **8.2 Synchronization via AG-UI Snapshots**

The AG-UI protocol supports **Shared State** via STATE\_SNAPSHOT events.2

* **Event:** The server emits a JSON snapshot of the agent's internal memory (e.g., {"user\_preference": "dark\_mode"}).  
* **Handler:** The Blazor client listens for DataContent with the MIME type application/json.  
* **Action:** When received, the client dispatches a Fluxor action UpdateAgentStateAction, which updates the client-side store. This ensures that if the agent learns something new about the user, the UI (e.g., the theme or settings panel) updates immediately to reflect this knowledge.

## **9\. Human-in-the-Loop (HITL) Workflow**

For agents performing sensitive actions (e.g., modifying database records), the architecture must enforce a Human-in-the-Loop approval workflow.

### **9.1 The Approval Protocol**

AG-UI formalizes this process.28

1. **Interception:** When the agent attempts to execute a protected tool, the server-side middleware intercepts the call.  
2. **Request:** The server sends a FunctionApprovalRequestContent to the client instead of executing the tool.  
3. **UI Rendering:** The Blazor client detects this content type and renders an **Approval Card** in the chat stream. This card displays the tool name and the arguments the agent intends to use.  
4. **Decision:** The user clicks "Approve" or "Deny."  
5. **Response:** The client sends the decision back to the server as a ToolResult. If approved, the server executes the logic; if denied, it returns an error to the agent, allowing the agent to self-correct (e.g., "I understand, I will not proceed with the deletion.").

## **10\. Orchestration and Observability**

The complexity of this distributed system requires robust operational tooling.

### **10.1 The Golden Triangle**

The "Golden Triangle" methodology combines **DevUI** (for local debugging), **AG-UI** (for production protocol), and **OpenTelemetry** (for observability).1

* **DevUI:** During development, the agent can be tested using the simplified DevUI provided by the framework to verify tool logic in isolation.  
* **OpenTelemetry:** The architecture must instrument both the Agent Backend and the Blazor Frontend with OpenTelemetry. This provides distributed tracing, allowing developers to see a request start in the Blazor button click, travel through the AG-UI stream, trigger an LLM inference, execute a backend tool, and return the result. This is critical for debugging latency and token usage.

## **11\. Conclusion**

The implementation of an Agentic UX Spec using Blazor and AG-UI represents a convergence of modern distributed systems, real-time protocol engineering, and advanced frontend rendering. By leveraging **Server-Sent Events** for low-latency streaming, **Monaco Editor** for artifact manipulation, and **DynamicComponent** for generative interfaces, developers can build applications where the AI is not merely a chatbot, but a fully integrated partner in the user's workflow.

The architecture defined herein—strict separation of concerns, robust state management via Fluxor/AG-UI Snapshots, and orchestration via.NET Aspire—provides the necessary foundation for enterprise-grade Agentic applications. This approach ensures scalability, maintainability, and a user experience that is both responsive and profoundly capable.

## **12\. Implementation Guide: Core Components and Code Structures**

This section translates the architectural concepts into specific code patterns and component structures required for implementation.

### **12.1 AG-UI Client Service Wrapper**

This wrapper encapsulates the AGUIChatClient and manages the complexity of the stream.

```csharp
public class AgentService  
{  
    private readonly IChatClient _client;  
    private readonly IState<AgentState> _state; // Fluxor State

    public AgentService(IChatClient client, IState<AgentState> state)  
    {  
        _client = client;  
        _state = state;  
    }

    public async IAsyncEnumerable<ChatResponseItem> StreamResponseAsync(List<ChatMessage> history)  
    {  
        var options = new ChatOptions   
        {   
            // Pass current client state to the agent context  
            AdditionalProperties = new() { ["client_state"] = _state.Value }   
        };

        await foreach (var update in _client.GetStreamingResponseAsync(history, options))  
        {  
            // Map AG-UI update types to internal UI models  
            if (update.Content is TextContent text)  
            {  
                yield return new ChatResponseItem { Type = ResponseType.Text, Content = text.Text };  
            }  
            else if (update.Content is FunctionCallContent tool)  
            {  
                yield return new ChatResponseItem { Type = ResponseType.ToolCall, Content = tool.Name };  
            }  
            // Handle State Snapshots  
            else if (update.Content is DataContent data && data.MediaType == "application/json")  
            {  
                var snapshot = JsonSerializer.Deserialize<StateSnapshot>(data.Data);  
                // Dispatch action to update Fluxor store  
                _dispatcher.Dispatch(new UpdateStateAction(snapshot));  
            }  
        }  
    }  
}
```

### **12.2 The Generative Component Renderer**

This component is the engine for the "Dynamic Component" feature.

```csharp
@using Microsoft.AspNetCore.Components.Rendering

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
                // Render a Text Input  
                builder.OpenComponent(seq++, typeof(MudTextField<string>));  
                builder.AddAttribute(seq++, "Label", prop.Title);  
                builder.AddAttribute(seq++, "Value", Data[prop.Name]);  
                //... Binding Logic...  
                builder.CloseComponent();  
            }  
            else if (prop.Type == "array")  
            {  
                // Render a Data Grid  
                builder.OpenComponent(seq++, typeof(MudDataGrid<object>));  
                //... Configuration for columns based on array items...  
                builder.CloseComponent();  
            }  
        }  
    }  
}
```

This structural approach ensures that the application is built on solid engineering principles, ready to handle the complexity and potential of the next generation of AI-driven software.

#### **Works cited**

1. The "Golden Triangle" of Agentic Development with Microsoft Agent Framework: AG-UI, DevUI & OpenTelemetry Deep Dive | Semantic Kernel, accessed February 4, 2026, [https://devblogs.microsoft.com/semantic-kernel/the-golden-triangle-of-agentic-development-with-microsoft-agent-framework-ag-ui-devui-opentelemetry-deep-dive/](https://devblogs.microsoft.com/semantic-kernel/the-golden-triangle-of-agentic-development-with-microsoft-agent-framework-ag-ui-devui-opentelemetry-deep-dive/)  
2. AG-UI Integration with Agent Framework \- Microsoft Learn, accessed February 4, 2026, [https://learn.microsoft.com/en-us/agent-framework/integrations/ag-ui/](https://learn.microsoft.com/en-us/agent-framework/integrations/ag-ui/)  
3. Backend Tool Rendering with AG-UI \- Microsoft Learn, accessed February 4, 2026, [https://learn.microsoft.com/en-us/agent-framework/integrations/ag-ui/backend-tool-rendering](https://learn.microsoft.com/en-us/agent-framework/integrations/ag-ui/backend-tool-rendering)  
4. Getting Started with AG-UI \- Microsoft Learn, accessed February 4, 2026, [https://learn.microsoft.com/en-us/agent-framework/integrations/ag-ui/getting-started](https://learn.microsoft.com/en-us/agent-framework/integrations/ag-ui/getting-started)  
5. Generative-AI-for-beginners-dotnet/samples/AgentFx/AgentFx-AIWebChatApp-AG-UI/README.md at main \- GitHub, accessed February 4, 2026, [https://github.com/microsoft/Generative-AI-for-beginners-dotnet/blob/main/samples/AgentFx/AgentFx-AIWebChatApp-AG-UI/README.md](https://github.com/microsoft/Generative-AI-for-beginners-dotnet/blob/main/samples/AgentFx/AgentFx-AIWebChatApp-AG-UI/README.md)  
6. AG-UI \+ Agent Framework \+ .NET \+ Aspire: Web-Enabling Your Intelligent Agents (Blog \+ Demo \+ Code\!) \- El Bruno, accessed February 4, 2026, [https://elbruno.com/2025/11/18/%F0%9F%9A%80-ag-ui-agent-framework-net-aspire-web-enabling-your-intelligent-agents-blog-demo-code/](https://elbruno.com/2025/11/18/%F0%9F%9A%80-ag-ui-agent-framework-net-aspire-web-enabling-your-intelligent-agents-blog-demo-code/)  
7. The Streaming Backbone of LLMs: Why Server-Sent Events (SSE) Still Wins in 2026, accessed February 4, 2026, [https://procedure.tech/blogs/the-streaming-backbone-of-llms-why-server-sent-events-(sse)-still-wins-in-2025](https://procedure.tech/blogs/the-streaming-backbone-of-llms-why-server-sent-events-\(sse\)-still-wins-in-2025)  
8. Using server-sent events \- Web APIs | MDN, accessed February 4, 2026, [https://developer.mozilla.org/en-US/docs/Web/API/Server-sent\_events/Using\_server-sent\_events](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events)  
9. Server-Sent Events in ASP.NET Core and .NET 10 \- Milan Jovanović, accessed February 4, 2026, [https://www.milanjovanovic.tech/blog/server-sent-events-in-aspnetcore-and-dotnet-10](https://www.milanjovanovic.tech/blog/server-sent-events-in-aspnetcore-and-dotnet-10)  
10. Running Agents \- Microsoft Learn, accessed February 4, 2026, [https://learn.microsoft.com/en-us/agent-framework/user-guide/agents/running-agents](https://learn.microsoft.com/en-us/agent-framework/user-guide/agents/running-agents)  
11. State Management with AG-UI | Microsoft Learn, accessed February 4, 2026, [https://learn.microsoft.com/en-us/agent-framework/integrations/ag-ui/state-management](https://learn.microsoft.com/en-us/agent-framework/integrations/ag-ui/state-management)  
12. 未来已来| 写给.NET 开发者的2025 年度总结- 「圣杰」 \- 博客园, accessed February 4, 2026, [https://www.cnblogs.com/sheng-jie/p/19402252/goodbye-2025-welcome-2026](https://www.cnblogs.com/sheng-jie/p/19402252/goodbye-2025-welcome-2026)  
13. AGUIChatClient Class (Microsoft.Agents.AI.AGUI) \- Microsoft Learn, accessed February 4, 2026, [https://learn.microsoft.com/en-us/dotnet/api/microsoft.agents.ai.agui.aguichatclient?view=agent-framework-dotnet-latest](https://learn.microsoft.com/en-us/dotnet/api/microsoft.agents.ai.agui.aguichatclient?view=agent-framework-dotnet-latest)  
14. Blazor Splitter Overview \- Telerik.com, accessed February 4, 2026, [https://www.telerik.com/blazor-ui/documentation/components/splitter/overview](https://www.telerik.com/blazor-ui/documentation/components/splitter/overview)  
15. Blazorise Splitter component, accessed February 4, 2026, [https://blazorise.com/docs/extensions/splitter](https://blazorise.com/docs/extensions/splitter)  
16. Blazor Splitter | Resizable Collapsible Panel \- Syncfusion, accessed February 4, 2026, [https://www.syncfusion.com/blazor-components/blazor-splitter](https://www.syncfusion.com/blazor-components/blazor-splitter)  
17. jsakamoto/Toolbelt.Blazor.SplitContainer: A Blazor component to create panes separated by a slidable splitter bar. \- GitHub, accessed February 4, 2026, [https://github.com/jsakamoto/Toolbelt.Blazor.SplitContainer](https://github.com/jsakamoto/Toolbelt.Blazor.SplitContainer)  
18. Code Highlight with Blazor \- Laszlo, accessed February 4, 2026, [https://blog.ladeak.net/posts/blazor-code-highlight2](https://blog.ladeak.net/posts/blazor-code-highlight2)  
19. serdarciplak/BlazorMonaco: Blazor component for Microsoft's Monaco Editor which powers Visual Studio Code. \- GitHub, accessed February 4, 2026, [https://github.com/serdarciplak/BlazorMonaco](https://github.com/serdarciplak/BlazorMonaco)  
20. Monaco Editor, accessed February 4, 2026, [https://microsoft.github.io/monaco-editor/](https://microsoft.github.io/monaco-editor/)  
21. Blazor Server Monaco DiffEditor setup \- Stack Overflow, accessed February 4, 2026, [https://stackoverflow.com/questions/73063440/blazor-server-monaco-diffeditor-setup](https://stackoverflow.com/questions/73063440/blazor-server-monaco-diffeditor-setup)  
22. Monaco Editor: How to Input Content at Certain Positions | by Yuhan "Helios" Liu, accessed February 4, 2026, [https://heliosyuhanliu.medium.com/monaco-editor-how-to-input-content-at-certain-positions-4166b1e4f233](https://heliosyuhanliu.medium.com/monaco-editor-how-to-input-content-at-certain-positions-4166b1e4f233)  
23. How to edit a Range programmatically in Monaco Editor? \- Stack Overflow, accessed February 4, 2026, [https://stackoverflow.com/questions/77012177/how-to-edit-a-range-programmatically-in-monaco-editor](https://stackoverflow.com/questions/77012177/how-to-edit-a-range-programmatically-in-monaco-editor)  
24. Dynamically-rendered ASP.NET Core Razor components \- Microsoft Learn, accessed February 4, 2026, [https://learn.microsoft.com/en-us/aspnet/core/blazor/components/dynamiccomponent?view=aspnetcore-10.0](https://learn.microsoft.com/en-us/aspnet/core/blazor/components/dynamiccomponent?view=aspnetcore-10.0)  
25. ASP.NET Core Blazor advanced scenarios (render tree construction) \- Microsoft Learn, accessed February 4, 2026, [https://learn.microsoft.com/en-us/aspnet/core/blazor/advanced-scenarios?view=aspnetcore-10.0](https://learn.microsoft.com/en-us/aspnet/core/blazor/advanced-scenarios?view=aspnetcore-10.0)  
26. $recursiveRef (2019-09) \- Learn JSON Schema, accessed February 4, 2026, [https://www.learnjsonschema.com/2019-09/core/recursiveref/](https://www.learnjsonschema.com/2019-09/core/recursiveref/)  
27. Pjotrtje/Fluxor.Undo: Easy undo/redo for Fluxor \- GitHub, accessed February 4, 2026, [https://github.com/Pjotrtje/Fluxor.Undo](https://github.com/Pjotrtje/Fluxor.Undo)  
28. Human-in-the-Loop with AG-UI \- Microsoft Learn, accessed February 4, 2026, [https://learn.microsoft.com/en-us/agent-framework/integrations/ag-ui/human-in-the-loop](https://learn.microsoft.com/en-us/agent-framework/integrations/ag-ui/human-in-the-loop)
29. Blazor Blueprint UI - Resizable panel groups built for creating flexible layouts. https://blazorblueprintui.com/docs/components/resizable