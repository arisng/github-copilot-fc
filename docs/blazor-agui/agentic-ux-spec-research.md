# **Architecting the Agentic Interface: A Comprehensive Research Report on UX/UI Patterns, Generative Protocols, and Dual-Pane Frameworks for Autonomous Systems**

Date: Feb 03, 2026

## **1\. Executive Summary: The Dawn of the Delegative Era**

The history of Human-Computer Interaction (HCI) is punctuated by paradigm shifts that fundamentally alter how our species interfaces with digital intelligence. We are currently navigating the transition from the **Conversational Era** (2023–2024), characterized by the "lonely chatbot" and linear prompt-response loops, to the **Agentic Era** (2025–2026 and beyond).1 This new epoch is defined not by passive tools that wait for commands, but by proactive, autonomous agents capable of planning, executing, and iterating on complex workflows. This shift necessitates a complete reimagining of the frontend architecture of software applications. The "Classic Chatbox"—a vestige of messaging apps designed for human-to-human communication—is proving woefully inadequate for managing the high-dimensional, multi-step outputs of modern AI.3

As enterprises transition to an "orchestrated workforce" model, where primary "orchestrator" agents direct teams of specialized sub-agents, the user interface must evolve from a simple text stream into a high-fidelity **Control Plane**.5 The "Productivity Paradox" looming in 2026 warns that without this architectural evolution, single agents will become "digital dead-end islands"—isolated curiosities that fail to scale because users cannot effectively manage, verify, or integrate their work.5 The solution lies in **Delegative UI**: interfaces designed for supervision rather than mere conversation. In this model, the human user ascends from the role of a micromanager (typing explicit commands) to that of an architect or supervisor (assigning goals and reviewing outcomes).1

This report provides an exhaustive analysis of the architectural patterns required to support this transition. We define the **Dual-Pane Architecture** as the emerging standard for complex cognitive work, separating the ephemeral "negotiation" of the chat from the persistent "state" of the artifact.7 We explore the technical backbone of **Generative UI (GenUI)**, a paradigm where agents construct their own interfaces just-in-time (JIT) to suit the context of the conversation, utilizing framework-agnostic protocols like **A2UI**, **AG-UI**, and **Adaptive Cards**.8 Furthermore, we synthesize these findings into a baseline specification for a modern, agentic web application, ensuring that the next generation of software is built on robust, scalable, and observable foundations. By moving beyond the "Black Box" and visualizing the "Chain of Thought," we aim to engineer trust directly into the pixels of the interface, turning the "magic" of AI into a manageable, reliable utility.2

## ---

**2\. The Theoretical Framework: From Chatbots to Agentic Workspaces**

To understand the necessity of the new design patterns discussed in this report, one must first appreciate the theoretical limitations of the current dominant paradigm. The "Chatbot" interface, popularized by the initial release of ChatGPT, relies on a skeuomorphic design inherited from SMS and messaging platforms. While effective for simple Q\&A, this linear format creates a "low-dimensional channel" that is ill-suited for the high-dimensional complexity of agentic work.3

### **2.1 The "Slot Machine" Interaction Model vs. Co-Creation**

In the traditional chat interface, the interaction model resembles a slot machine. The user compiles a vast amount of context—project constraints, preferences, memories, stylistic guidelines—and compresses them into a single text prompt. They then "pull the lever" (submit the prompt) and hope for a lucky result.3 If the output is 90% correct but 10% wrong, the user is often forced to restate the entire context or engage in a tedious game of "Twenty Questions" to refine the output. This "Slot Machine" dynamic invisibly adds to cognitive load, forcing the user to maintain the state of the project in their own head because the interface possesses no memory of the *artifact*, only a log of the *conversation*.3

The shift to **Agentic Systems** demands a move from this transactional model to a **Co-Creation** model. In a co-creation workspace, the AI and the human work side-by-side on a shared, persistent object. The interaction is no longer about "asking" and "receiving," but about "manipulating" and "refining." This aligns with the transition from **Conversational UI** (passive tools) to **Delegative UI** (active systems).1 In a Delegative UI, the system must support **Observable Plans**—visualizations of what the agent *intends* to do before it does it—and **Reversible Actions**, allowing the user to treat the agent's work as a draft rather than a final decree.10

### **2.2 The "Architect's Reality Check": Agency requires Governance**

As noted in the "Architect's Reality Check" for 2026, the primary cause of failure in agentic deployments is not model quality, but a lack of system architecture. Failures stem from "unbounded autonomy," "no state control," and "no observability".6 UX design, therefore, becomes a critical component of AI governance. The interface is the only mechanism through which a user can constrain, guide, and verify an autonomous agent.

Designers must move from "Empathy by Proxy" (designing for personas) to "Empathy by Pattern" (designing for intent).12 This means creating systems that can recognize the *type* of work the user is trying to do and adapting the interface accordingly. If the user is debugging code, the interface should resemble an IDE. If they are analyzing market trends, it should resemble a Bloomberg terminal. This adaptability is the core promise of **Generative UI**, which we will explore in Section 4\.

### **2.3 Object-Oriented UX (OOUX) for AI**

A critical theoretical framework for grounding agentic interfaces is **Object-Oriented UX (OOUX)**. Most current AI products feel like "feature soup" because they focus on the *verbs* (Generate, Edit, Summarize) rather than the *nouns* (The Document, The Codebase, The Schedule).13 OOUX forces designers to define the objects users actually care about *before* adding AI capabilities.

In an agentic system, the "Objects" must be first-class citizens. They cannot be buried inside a chat bubble.

* **The Chat** is a stream of metadata (discussion about the object).  
* **The Artifact** is the object itself.  
* **The Memory** is the history of the object.

By separating these concerns, we arrive at the **Dual-Pane Architecture**, which spatially segregates the "Meta-Channel" (Chat) from the "Object-Channel" (Canvas).7 This separation allows the user to maintain a mental model of the *work* distinct from the *discussion* of the work, reducing the "Black Box Anxiety" that occurs when users feel they have lost control of the process.2

## ---

**3\. The Dual-Pane Architecture: The Standard for Co-Creation**

The defining visual pattern of the Agentic Era is the **Dual-Pane Architecture** (often referred to as the "Co-Creator Workspace," "Canvas," or "Split-Screen" pattern).7 This layout acknowledges a fundamental truth of knowledge work: "talking about the work" and "doing the work" are distinct activities that require different visual affordances and state management strategies.

### **3.1 Anatomy of the Dual-Pane Layout**

In the standard implementation—observed in pioneering tools like OpenAI Canvas, Claude Artifacts, Cursor, and various "vibe coding" environments—the screen is divided vertically, creating two distinct zones of interaction.14

#### **3.1.1 The Context Pane (Left/Sidebar)**

The Context Pane serves as the **Meta-Channel**.

* **Primary Function:** Negotiation and Intent Expression.  
* **Interaction Model:** Linear, chronological, and text-heavy. This is where the standard "Chat" interface lives.  
* **State:** Ephemeral. Old messages scroll off-screen and are functionally "archived" in the user's mind, though they remain in the agent's context window.14  
* **Role in Agency:** This is the command line for the "Supervisor." It is where goals are set ("Build a dashboard"), plans are reviewed ("Here is my plan..."), and feedback is given ("Make it bluer").

#### **3.1.2 The Canvas Pane (Right/Main)**

The Canvas Pane serves as the **Object-Channel**.

* **Primary Function:** Artifact Creation and Manipulation.  
* **Interaction Model:** Spatial, non-linear, and highly interactive. Users can click, scroll, zoom, highlight, and directly edit content.  
* **State:** Persistent. This pane represents the "Current State" of the deliverable. It does not scroll away; it updates in place.  
* **Role in Agency:** This is the workbench for the "Contractor" (the Agent). It displays the code, the document, the chart, or the UI being built.

### **3.2 Comparative Analysis: Canvas vs. Artifacts vs. Integrated Editor**

While the broad strokes of Dual-Pane are consistent, subtle implementation details significantly impact the UX. We can categorize existing implementations into three sub-patterns: **The Sidecar**, **The App Generator**, and **The Integrated Editor**.

| Feature | OpenAI Canvas (The Sidecar) | Claude Artifacts (The App Generator) | Cursor / Replit (The Integrated Editor) |
| :---- | :---- | :---- | :---- |
| **Primary Metaphor** | **Google Docs \+ AI.** A collaborative document editor. | **App Store \+ AI.** Generating self-contained mini-apps. | **IDE \+ AI.** A code editor where the AI is a pair programmer. |
| **Editing Model** | **Real-time Collaboration.** User and AI edit the same text stream. | **"Look but don't touch."** Artifacts are often read-only or require re-generation to change. | **"Shadow Workspace."** Agent applies diffs directly to the file system. |
| **Context Window** | Smaller (\~75k tokens). Can lose thread in long sessions.14 | Large (200k+ tokens). Handles massive context and long conversations.14 | **Project-Wide.** "Vibe Coding" absorbs context from all files, not just the chat.16 |
| **UX Friction** | Low. Feels natural for writing and drafting. | Medium. Feels like a "separate tool." Good for visualization, bad for iteration.14 | High learning curve, but maximum power for developers. |
| **Best For...** | Writing, Marketing Copy, Simple Coding. | Prototyping, Data Viz, Single-Use Tools. | Software Engineering, Complex Systems, "Vibe Coding".16 |

**Insight:** The "Integrated Editor" model, exemplified by Cursor and Replit, represents the most mature evolution of the Dual-Pane architecture for technical tasks. It does not just "show" the work; it *is* the work environment. The AI has "actuator" access to the user's cursor and file system, blurring the line between "Agent" and "Tool".16

### **3.3 The "Shared Working Space" Heuristic & Contextual Scoping**

The killer feature of Dual-Pane architecture is **Contextual Scoping**. In a linear chat, referring to a specific part of a previous output is clumsy ("In the third paragraph of the code you wrote five messages ago..."). In a Dual-Pane system, the user utilizes **Spatial Deictic Referencing**—pointing at things.

**Interaction Pattern: Highlight-to-Prompt**

* **Mechanism:** The user highlights a section of text or code in the Canvas Pane.  
* **Response:** The interface immediately spawns a floating "Scoped Chat" or updates the context of the main chat.  
* **Agent Logic:** The agent treats the highlighted selection as the active\_context and the prompt as a transformation function applied *only* to that selection.18  
* **Benefit:** This drastically reduces token usage (no need to re-read the whole file) and eliminates ambiguity. It enables "surgical" edits rather than "nuclear" regens.

### **3.4 Managing "Context Switching" and Attention**

A risk of Dual-Pane is visual fragmentation. If the user is focused on the Canvas, movement in the Chat pane can be a distraction.

* **The "Vibe" Layer:** Emerging patterns like Cursor's "Tab-first" interaction model aim to make the AI "embedded." Instead of constantly switching to the chat pane, the AI offers "Ghost Text" completions directly in the canvas. The user accepts with Tab or rejects with Esc. This keeps the user in the "Flow State" of the Canvas, only retreating to the Chat Pane for high-level architectural discussions.16  
* **Implication:** The Chat Pane should be collapsible. When the user is in "Deep Work" mode, the Chat should disappear, leaving only the Canvas and perhaps a minimal "Agent Status" indicator.15

## ---

**4\. Generative UI (GenUI): The Technical Backbone**

If Dual-Pane is the *body* of the agentic interface, **Generative UI (GenUI)** is the *muscle*. GenUI refers to the capability of an AI agent to dynamically generate user interface elements on the fly, rather than relying solely on pre-hardcoded screens.7 This capability is essential for "General Purpose" agents that must adapt to unpredictable user needs—displaying a stock chart one minute, a flight booking form the next, and a code diff the third.

### **4.1 The Return of Server-Driven UI (SDUI)**

GenUI marks a renaissance of **Server-Driven UI (SDUI)** concepts. In the mobile era, companies like Airbnb and Uber used SDUI to update app layouts without requiring an App Store release. In the Agentic Era, we use SDUI because the "Server" (the Agent) is the only entity that knows what needs to be rendered next. The frontend client becomes a dumb "renderer" that interprets instructions from the intelligent backend.9

### **4.2 The Spectrum of Generative UI**

GenUI is not a monolith; it exists on a spectrum of flexibility versus control.7 Understanding this spectrum is crucial for architectural decisions.

#### **4.2.1 Static GenUI**

* **Description:** The agent selects from a library of pre-built, high-polish components (e.g., \<WeatherCard /\>, \<StockTicker /\>, \<FlightList /\>).  
* **Mechanism:** The agent outputs a tool call: display\_weather({ zip: "90210" }). The frontend maps this to the React component.  
* **Pros:** High visual polish, perfect brand consistency, zero security risk (no arbitrary code).  
* **Cons:** Limited vocabulary. If the agent needs to show a "3D Molecule Viewer" and you haven't built that component, the agent fails.  
* **Use Case:** Customer support bots, banking assistants, controlled enterprise apps.

#### **4.2.2 Declarative GenUI (The Sweet Spot)**

* **Description:** The agent builds a UI using a generic JSON schema (e.g., "Row containing Column A and Column B"). The client renders this using a set of atomic primitives (Box, Text, Image, Button).  
* **Mechanism:** The agent outputs a JSON tree describing the layout.  
* **Pros:** High flexibility (can build almost any form or layout), secure (no arbitrary code execution), framework-agnostic.  
* **Cons:** Hard to achieve "pixel-perfect" custom branding; usually looks like a "generic" UI.  
* **Use Case:** General-purpose assistants, business process automation, "Canvas" apps.

#### **4.2.3 Open-Ended GenUI**

* **Description:** The agent generates raw HTML/CSS/JS or executes code in a sandbox (e.g., \<iframe\> or WebContainer).  
* **Mechanism:** The agent writes a React component string, transpiles it, and injects it into the DOM.  
* **Pros:** Infinite flexibility. Can build games, physics simulations, totally novel interfaces.  
* **Cons:** High security risk (XSS, data exfiltration), performance overhead of sandboxing, potential for visual breakage.  
* **Use Case:** Prototyping tools (Claude Artifacts), coding assistants, data visualization explorers.

**Architectural Recommendation:** For a "Baseline Web App Spec," **Declarative GenUI** is the superior choice. It balances the flexibility required for agentic workflows with the security and stability required for enterprise deployment. Open-Ended GenUI should be reserved for specific "Sandbox" modes.

### **4.3 Protocol Standardization: A2UI, AG-UI, and Adaptive Cards**

To avoid vendor lock-in, developers should adopt open protocols for GenUI. Three primary standards have emerged:

#### **4.3.1 A2UI (Agent-to-UI) Protocol**

Google's **A2UI** is designed specifically for "Agent-Driven Interfaces".9

* **Philosophy:** Decouples *intent* from *implementation*. The agent says "Show a confirmation," and the client decides whether that's a Modal, a Toast, or a bottom sheet.  
* **Bidirectional Binding:** Unlike static HTML, A2UI supports closed loops. A user action (clicking "Book") sends a UserAction event back to the agent with context, allowing for multi-turn UI flows.21  
* **Client Renderers:** Available for Lit, Angular, React, and Flutter, making it truly framework-agnostic.

#### **4.3.2 AG-UI (Agent-User Interaction Protocol)**

Developed by CopilotKit, **AG-UI** focuses on the *transport* and *synchronization* layer.19

* **Key Innovation:** Uses **JSON Patch (RFC 6902\)** over Server-Sent Events (SSE).  
* **Efficiency:** If an agent generates a massive datagrid, AG-UI sends only the "Deltas" (e.g., "Change row 3, cell 2 to 'Confirmed'"). This enables real-time, low-latency updates essential for "streaming" UI.23

#### **4.3.3 Adaptive Cards (Microsoft)**

Adaptive Cards (v1.6) is the incumbent standard, widely used in Teams and Outlook.24

* **HostConfig:** Its defining feature is the HostConfig file, which allows the *same* JSON card to look like a Teams card inside Teams and a Web Chat card inside a website.  
* **Limitation:** It is excellent for "Cards" (forms, notifications) but struggles with full-page application layouts compared to A2UI.24

**Comparison Matrix for Baseline Spec:**

| Feature | A2UI | AG-UI | Adaptive Cards 1.6 | Vercel RSC |
| :---- | :---- | :---- | :---- | :---- |
| **Primary Focus** | Layout & Component Definition | State Sync & Transport | Message Cards / Widgets | React Component Streaming |
| **Format** | JSON Schema | JSON Events / Patches | JSON Schema | Serialized React Tree |
| **Framework Agnostic?** | **Yes** (Renderers for all) | **Yes** (Protocol level) | **Yes** (Renderers for all) | **No** (React Only) |
| **Interactivity** | High (Bidirectional) | High (Real-time sync) | Medium (Actions/Submit) | High (Client Components) |
| **Recommendation** | **Use for Structure** | **Use for Transport** | **Use for Widgets** | **Use if 100% Next.js** |

### **4.4 Technical Mitigation: Handling Latency and Hallucination**

Implementing GenUI introduces specific frontend challenges:

1. **The "Popcorn" Effect:** If an agent streams a UI token-by-token, the interface jitters and "pops" into existence, destroying the UX.  
   * *Solution:* **Optimistic UI & Skeleton Loaders.** Upon detecting a tool call start event, the client should immediately render a "Skeleton" of the component (e.g., a blank card with shimmering lines). The actual data is swapped in only when the payload is valid.26  
2. **Hallucinated Props:** Agents may invent properties that don't exist (e.g., passing color="chartreuse" to a component that only accepts primary or secondary).  
   * *Solution:* **Strict Schema Validation (Zod).** The client must validate the JSON against a strict schema *before* rendering. If validation fails, the error is sent back to the agent ("Error: Invalid color. Retry."), keeping the failure invisible to the user.27

## ---

**5\. Visualizing Agency: Observability, Reasoning, and Trust**

In the Agentic Era, "Explainable AI" is not just a regulatory requirement; it is a fundamental UX necessity.2 Users will not tolerate a "spinning loader" followed by a result; they demand to know *what* the agent is doing, especially when the agent is performing autonomous tool calls (e.g., "Searching database," "Deleting files," "Drafting email").

### **5.1 From "Black Box" to "Glass Box"**

We must transition from "Black Box" interfaces to "Glass Box" interfaces that expose the **Chain of Thought (CoT)** or **Execution Trace**. However, raw logs are overwhelming. The design challenge is **Progressive Disclosure**.

#### **5.1.1 The "Accordion of Thought" Pattern**

* **Default State:** A collapsed, pulsing indicator (e.g., "Thinking..." or "Planning Research...").  
* **Active State:** As the agent works, the label updates dynamically ("Searching Google...", "Reading 3 files...", "Synthesizing answer...").  
* **Expanded State:** The user can click to expand the accordion, revealing the raw "thought" logs, tool inputs, and outputs. This allows power users to debug the agent's logic.10  
* **Research Validation:** Studies from Stanford HAI show that exposing CoT in this manner reduces "black-box anxiety" by 34%.10

#### **5.1.2 Interactive Reasoning Traces**

Beyond simple logs, we can use **Space-Filling Node** visualizations.

* **Concept:** Visualize the reasoning process as a tree or graph. Each node represents a step in the agent's logic.  
* **Interaction:** Users can click a node to "inspect" the state of the agent at that moment.  
* **Correction:** Advanced interfaces allow users to "prune" the tree—clicking a node and saying "Don't go down this path, try X instead." This turns the user into an active participant in the reasoning loop.28

### **5.2 The "Memory Inspector": Visualizing Context**

Agents have "context" (short-term memory) and "knowledge" (long-term memory), but users rarely know *what* the agent currently knows. This opacity leads to frustration.

* **UI Pattern: The Brain Panel.** A dedicated drawer (often accessible via a generic "Brain" icon) that lists:  
  * **Active Facts:** "User prefers dark mode," "Project deadline is Friday."  
  * **Loaded Documents:** List of files currently in the context window.  
  * **Tool State:** Which tools are authenticated and available.  
* **Functionality:** Users can manually delete "false memories" ("Forget that I said I liked blue") or inject new context. This moves memory from a hidden variable to a managed asset.11

### **5.3 Visualizing Multi-Agent Swarms**

In "Orchestrated Workforce" models, a single request might trigger a swarm of sub-agents (e.g., a Researcher, a Writer, a Coder, and a Reviewer).5

* **Pattern: The Swarm Status Bar.**  
* **UI:** A horizontal timeline or a node-link diagram showing the "baton pass" between agents.  
* **Example:** "Researcher Agent (Active) → Data passed to Analyst → Writer (Pending)."  
* **Benefit:** This helps the user understand latency. If a request takes 45 seconds, seeing the specialized agents working in parallel keeps the user engaged and builds trust in the thoroughness of the process.30

## ---

**6\. State Management & Persistence: The "Golden Record"**

A robust agentic UI requires a state management strategy that far exceeds the complexity of typical web apps. In a standard app, the database is the source of truth. In an agentic app, the **Conversation History**, **Artifact State**, and **Agent Memory** combine to form a complex, mutable source of truth.

### **6.1 The "Golden Record" Problem**

When an agent edits a document in the Canvas, that change must be reflected in the Chat history and the Agent's memory. If these get out of sync (e.g., the Chat says "I added a column," but the Canvas doesn't show it), the illusion breaks.

* **Solution: Server-Authoritative State with JSON Patch.** The backend (Agent) holds the master state of the Artifact. It pushes updates to the frontend using JSON Patch via AG-UI/SSE.23  
* **Mechanism:** Instead of re-sending the entire 5MB document for every keystroke, the server sends: \[{"op": "replace", "path": "/data/rows/3", "value": {...}}\]. This allows for high-frequency updates without network congestion.

### **6.2 Branching Conversations & "Time Travel"**

Linear chat history is restrictive. Users often want to "fork" a conversation to explore a different hypothesis without losing the original thread (e.g., "What if we wrote this in Python instead of JS?").

* **UI Pattern: Thread Branching.**  
* **Interaction:** The user hovers over a previous message → clicks "Edit" → changes prompt → clicks "Save & New Branch."  
* **Visual:** The interface shows navigation arrows \< 2 / 5 \> on the message bubble, allowing the user to toggle between parallel "multiverses" of the conversation.31  
* **State Implication:** The "Artifact" must be versioned alongside the "Chat Branch." If the user switches to Branch B, the Canvas must revert to the state it was in during Branch B.33 This requires a **Temporal Database** approach to state management.

### **6.3 CRDTs for Human-Agent Collaboration**

In "Google Docs-style" collaboration (OpenAI Canvas), the human and the agent might edit the same document simultaneously.

* **Technology:** **Conflict-free Replicated Data Types (CRDTs)** (like Yjs or Automerge).  
* **Application:** Both the user's keystrokes and the agent's streaming tokens are treated as operations on a CRDT. This ensures that if the user fixes a typo while the agent is writing a new paragraph, the edits merge seamlessly without overwriting each other.34

## ---

**7\. Human-in-the-Loop (HITL) and Governance Patterns**

The "Gold Standard Pattern" for 2026 is the **Supervisor Agent** model, where humans serve as the ultimate check on autonomous actions.6 HITL is not just a safety feature; it is a collaborative interface pattern that transforms the AI from a "Black Box" into a manageable teammate.

### **7.1 The Approval Queue & "Pending Actions"**

For high-risk actions (e.g., DELETE \* FROM database, Send Email to CEO, Purchase Domain), the UI must interrupt the autonomous flow.

* **Anti-Pattern:** Blocking the chat input with a modal. This disrupts context and feels intrusive.  
* **Pattern: The Pending Actions Widget.** An inline card or a dedicated "Approvals" tab in the Dual-Pane sidebar.  
* **Content:**  
  * **Action:** "Send Email"  
  * **Payload:** "Subject: Hello...", "To: boss@company.com"  
  * **Risk Level:** Visual indicator (Yellow/Red) based on the action's irreversibility.  
  * **Controls:** "Approve," "Edit Payload," "Reject."  
* **Protocol Support:** AG-UI has built-in middleware for needsApproval flags. When the agent triggers a tool with this flag, the server pauses execution and sends a FunctionApprovalRequestContent event to the client, which renders the approval UI.35

### **7.2 Reversibility: The "Time Travel" UI**

Since agents are non-deterministic, they will make mistakes. The UI must support **idempotency** and **rollback**.

* **Pattern: Checkpoints.** Every time an agent modifies the Canvas (e.g., changes code), the system creates a snapshot.  
* **UI Control:** A slider or timeline (like Mac Time Machine or Google Docs History) allowing the user to "scrub" back to a previous state.10  
* **Diff Views:** Before accepting a large change, the user is presented with a "Diff View" (red/green lines) to verify the agent's work. This is critical for coding agents, where a single wrong line can break the build.10

### **7.3 The "Panic Button"**

In autonomous agent loops (e.g., "Auto-fix all bugs in this repo"), the agent might enter a destructive loop.

* **Pattern: The Kill Switch.** A prominent, always-visible "Stop Generating" button that not only halts the LLM stream but cancels any pending tool executions and reverts the file system to the pre-run state.

## ---

**8\. Mobile Adaptations: Responsive Agentic Interfaces**

Translating the Dual-Pane / Canvas architecture to mobile (small screens) is the "Responsive Design" challenge of the AI era. You cannot simply stack the panes; the cognitive load of context switching is too high. The interface must adapt to "Thumb-First" interactions and limited screen real estate.38

### **8.1 The "Drawer" and "Sheet" Patterns**

Instead of a permanent split screen, mobile agentic apps should use **modal layers**.

* **Base Layer:** The Chat (Conversation). This is the "Home" view.  
* **Overlay Layer:** The Artifact (Canvas).  
* **Interaction:** When the agent generates an artifact (e.g., a code snippet or itinerary), it appears as a "Chip" or "Card" in the chat stream. Tapping it opens the Artifact in a full-screen **Bottom Sheet** or **Slide-over Drawer**.38  
* **Gesture:** Swipe down to dismiss the artifact and return to chat. Swipe left/right to browse versions of the artifact.

### **8.2 The "Stacked View" for Dashboards**

For complex dashboards (like the "Memory Inspector"), use a **Stacked View**.

* **Header:** Shows current context/status (e.g., "Agent Status: Thinking").  
* **Body:** Shows the primary content (Chat or Artifact).  
* **Footer Controls:** "Sticky" controls for high-frequency actions (e.g., microphone, "Stop," "Approve").  
* **Constraint:** Mobile inputs should be "Selection-heavy." Avoid requiring complex typing. Use "Suggestion Chips," "Carousels," and "Steppers" to let the user guide the agent via tapping rather than typing.38

### **8.3 Mobile GenUI**

Using **Declarative GenUI** (A2UI/Adaptive Cards) is critical for mobile.

* **Why:** A JSON schema can be rendered as a \<div\> on web but as a native SwiftUI or Jetpack Compose view on mobile.20 This ensures the UI feels "native" (smooth scrolling, native inputs, haptics) rather than a clunky HTML iframe, which is often a performance bottleneck on mobile devices.20

## ---

**9\. Framework-Agnostic Component Specifications (Baseline Web App Spec)**

To build a "Baseline Web App" that supports these patterns, we define a set of **Atomic Agentic Components**. These should be implemented in the host framework (React, Vue, Svelte) but driven by a standard JSON schema (A2UI-inspired) to ensure interoperability.

### **9.1 Core Component Registry**

**1\. AgentThinking (The Observability Component)**

* **Role:** Visualizes the "Chain of Thought."  
* **Schema Input:** { status: "processing" | "idle", steps: \[{ label: string, state: "pending" | "done" }\] }  
* **Behavior:** Renders the "Accordion." Animates during "processing." Supports click-to-expand.

**2\. ArtifactContainer (The Canvas)**

* **Role:** The container for the work object.  
* **Schema Input:** { artifactId: string, type: "code" | "markdown" | "webview", content: string, version: int }  
* **Behavior:** Renders the content. Handles syntax highlighting (if code). Provides "Copy," "Download," and "History" controls. Supports "Highlight-to-Prompt" events.

**3\. ApprovalRequest (HITL)**

* **Role:** The safety gate.  
* **Schema Input:** { requestId: string, actionName: string, params: object, riskLevel: "low" | "high" }  
* **Behavior:** Renders a card with "Approve/Reject" buttons. High risk level \= Red borders/icons.

**4\. GenerativeForm (Structured Input)**

* **Role:** Solicits specific data from the user.  
* **Schema Input:** JSON Schema (Draft 7).  
* **Behavior:** Renders a dynamic form (inputs, date pickers, selects) based on the schema. Validates input client-side before sending back to the agent.

**5\. ThreadBrancher (Navigation)**

* **Role:** Manages conversation forks.  
* **Schema Input:** { currentBranch: int, totalBranches: int, parentId: string }  
* **Behavior:** Renders the \< | \> navigation controls on chat bubbles.

### **9.2 JSON Schema Example (Unified A2UI \+ HITL)**

This payload represents a single "turn" where an agent updates the canvas and requests approval.

JSON

{  
  "protocol": "A2UI/1.0",  
  "threadId": "thread\_123",  
  "events":  
}

## ---

**10\. Future Outlook: The Agent-to-Agent Interface (2026)**

Looking ahead to late 2026, the UX challenge will shift from **Human-Agent** interaction to **Agent-Agent** interaction visualization. As the "Agent-to-Agent Economy" emerges, users will employ "Gatekeeper Agents" to filter noise and negotiate on their behalf.1

### **10.1 Visualizing the "Bot Battle"**

The UI will need to visualize interactions where the user is not a participant but an observer.

* **Pattern:** The Negotiation Log.  
* **Example:** "Your Shopping Agent is negotiating with Amazon Support Bot...... Discount secured: 15%."  
* **UX Challenge:** How much detail to show? Too much \= noise; too little \= mistrust. The **Accordion** pattern will likely apply here as well.

### **10.2 Glassmorphism & Meaningful Motion**

As interfaces become denser (showing Chat, Canvas, Thinking, and Approval simultaneously), visual hierarchy becomes critical. **Glassmorphism** (translucent layers) and **Meaningful Motion** (animations that show the flow of data between agents) will become functional requirements, not just aesthetic choices. They help the user track the complex flow of information in a multi-agent system.41

## ---

**11\. Conclusion**

The transition to Agentic AI requires a fundamental architectural overhaul. We must abandon the notion that a simple chatbox is sufficient for autonomous work. By adopting the **Dual-Pane Architecture**, leveraging **Generative UI protocols (A2UI/AG-UI)**, and rigorously implementing **Human-in-the-Loop** observability, we can build interfaces that are not just "wrappers" for LLMs, but robust *workbenches* for the future of digital labor.

The specification provided in this report—rooted in state persistence, component-agnostic schemas, and observable reasoning—forms the blueprint for the next generation of enterprise software. The future of UX is not about designing better screens for humans to click on; it is about designing better shared spaces where humans and machines can think together.

**Key Takeaways for Implementation:**

1. **Adopt A2UI/AG-UI** for framework-agnostic component definitions.  
2. **Enforce Dual-Pane** layouts for any task more complex than a Q\&A.  
3. **Visualize the Chain of Thought** to build trust and reduce anxiety.  
4. **Design for Reversibility** (Time Travel) as a core safety feature.  
5. **Treat State as an Asset**, decoupling it from the ephemeral chat log.

This architecture ensures that as AI models become more powerful (2026+), the user interface scales with them, providing the necessary harness to channel raw intelligence into productive, safe, and observable work.

#### **Works cited**

1. 18 Predictions for 2026 \- UX Tigers, accessed February 1, 2026, [https://www.uxtigers.com/post/2026-predictions](https://www.uxtigers.com/post/2026-predictions)  
2. 10 UX design shifts you can't ignore in 2026 | by Arin Bhowmick, accessed February 1, 2026, [https://uxdesign.cc/10-ux-design-shifts-you-cant-ignore-in-2026-8f0da1c6741d](https://uxdesign.cc/10-ux-design-shifts-you-cant-ignore-in-2026-8f0da1c6741d)  
3. Co-constructing intent with AI agents | by TenoLiu \- UX Collective, accessed February 1, 2026, [https://uxdesign.cc/lifting-the-fog-co-constructing-intent-with-ai-agents-fbb503599ac0](https://uxdesign.cc/lifting-the-fog-co-constructing-intent-with-ai-agents-fbb503599ac0)  
4. Emergent UX patterns from the top Agent Builders : r/AI\_Agents \- Reddit, accessed February 1, 2026, [https://www.reddit.com/r/AI\_Agents/comments/1jqvdb1/emergent\_ux\_patterns\_from\_the\_top\_agent\_builders/](https://www.reddit.com/r/AI_Agents/comments/1jqvdb1/emergent_ux_patterns_from_the_top_agent_builders/)  
5. The Future of AI Agents: Top Predictions and Trends to Watch in 2026 \- Salesforce, accessed February 1, 2026, [https://www.salesforce.com/uk/news/stories/the-future-of-ai-agents-top-predictions-trends-to-watch-in-2026/](https://www.salesforce.com/uk/news/stories/the-future-of-ai-agents-top-predictions-trends-to-watch-in-2026/)  
6. Agentic AI Design Patterns(2026 Edition) | by Dewasheesh Rana \- Medium, accessed February 1, 2026, [https://medium.com/@dewasheesh.rana/agentic-ai-design-patterns-2026-ed-e3a5125162c5](https://medium.com/@dewasheesh.rana/agentic-ai-design-patterns-2026-ed-e3a5125162c5)  
7. Generative UI: Understanding Agent-Powered Interfaces \- CopilotKit, accessed February 1, 2026, [https://www.copilotkit.ai/generative-ui](https://www.copilotkit.ai/generative-ui)  
8. The Complete Guide to Generative UI Frameworks in 2026 | by Akshay Chame \- Medium, accessed February 1, 2026, [https://medium.com/@akshaychame2/the-complete-guide-to-generative-ui-frameworks-in-2026-fde71c4fa8cc](https://medium.com/@akshaychame2/the-complete-guide-to-generative-ui-frameworks-in-2026-fde71c4fa8cc)  
9. Introducing A2UI: An open project for agent-driven interfaces ..., accessed February 1, 2026, [https://developers.googleblog.com/introducing-a2ui-an-open-project-for-agent-driven-interfaces/](https://developers.googleblog.com/introducing-a2ui-an-open-project-for-agent-driven-interfaces/)  
10. Designing Trustworthy AI Agents: 30+ UX Principles that Turn “Wow” into Daily Habit, accessed February 1, 2026, [https://medium.com/techacc/designing-trustworthy-ai-agents-30-ux-principles-that-turn-wow-into-daily-habit-223da9f4d7f2](https://medium.com/techacc/designing-trustworthy-ai-agents-30-ux-principles-that-turn-wow-into-daily-habit-223da9f4d7f2)  
11. Agentic UI Patterns Beyond Chat: Canvases, Flows, and Rollback ..., accessed February 1, 2026, [https://llms.zypsy.com/agentic-ui-patterns-beyond-chat](https://llms.zypsy.com/agentic-ui-patterns-beyond-chat)  
12. How agentic AI enables a new approach to user experience design \- EY Studio, accessed February 1, 2026, [https://www.studio.ey.com/en\_gl/insights/how-agentic-AI-enables-a-new-approach-to-user-experience-design](https://www.studio.ey.com/en_gl/insights/how-agentic-AI-enables-a-new-approach-to-user-experience-design)  
13. OOUX might be the missing framework for designing AI interfaces \- Reddit, accessed February 1, 2026, [https://www.reddit.com/r/Design/comments/1qnybsj/ooux\_might\_be\_the\_missing\_framework\_for\_designing/](https://www.reddit.com/r/Design/comments/1qnybsj/ooux_might_be_the_missing_framework_for_designing/)  
14. Part 4 | ChatGPT Canvas or Claude Artifacts: How to Create SQL Database & Python Code from Simple Images \- AI Fire, accessed February 1, 2026, [https://www.aifire.co/p/detailed-comparison-for-interactive-tools-canvas-or-artifacts](https://www.aifire.co/p/detailed-comparison-for-interactive-tools-canvas-or-artifacts)  
15. A visual editor for the Cursor Browser, accessed February 1, 2026, [https://cursor.com/blog/browser-visual-editor](https://cursor.com/blog/browser-visual-editor)  
16. Cursor, “vibe coding,” and Manus: the UX revolution that AI needs | by Amy Chivavibul, accessed February 1, 2026, [https://uxdesign.cc/cursor-vibe-coding-and-manus-the-ux-revolution-that-ai-needs-3d3a0f8ccdfa](https://uxdesign.cc/cursor-vibe-coding-and-manus-the-ux-revolution-that-ai-needs-3d3a0f8ccdfa)  
17. Replit Review: Is It Worth It in 2026? \[My Honest Take\] \- Superblocks, accessed February 1, 2026, [https://www.superblocks.com/blog/replit-review](https://www.superblocks.com/blog/replit-review)  
18. Features · Cursor, accessed February 1, 2026, [https://cursor.com/features](https://cursor.com/features)  
19. Reusable agents meet agentic frontends: announcing AG-UI integration for Open Agent Specification | ai-and-datascience \- Oracle Blogs, accessed February 1, 2026, [https://blogs.oracle.com/ai-and-datascience/announcing-ag-ui-integration-for-agent-spec](https://blogs.oracle.com/ai-and-datascience/announcing-ag-ui-integration-for-agent-spec)  
20. The Complete Developer Tutorial: Building AI Agent UIs with A2UI and A2A Protocol in 2026, accessed February 1, 2026, [https://medium.com/@zh.milo/the-complete-developer-tutorial-building-ai-agent-uis-with-a2ui-and-a2a-protocol-in-2026-027cd213817b](https://medium.com/@zh.milo/the-complete-developer-tutorial-building-ai-agent-uis-with-a2ui-and-a2a-protocol-in-2026-027cd213817b)  
21. What is A2UI Protocol? : Deep Dive with code and example | by Vishal Mysore \- Medium, accessed February 1, 2026, [https://medium.com/@visrow/what-is-a2ui-protocol-deep-dive-with-code-and-example-f4385bbe865e](https://medium.com/@visrow/what-is-a2ui-protocol-deep-dive-with-code-and-example-f4385bbe865e)  
22. Introducing AG-UI: The Protocol Where Agents Meet Users | Blog \- CopilotKit, accessed February 1, 2026, [https://www.copilotkit.ai/blog/introducing-ag-ui-the-protocol-where-agents-meet-users](https://www.copilotkit.ai/blog/introducing-ag-ui-the-protocol-where-agents-meet-users)  
23. AG-UI: A Lightweight Protocol for Agent-User Interaction \- DataCamp, accessed February 1, 2026, [https://www.datacamp.com/tutorial/ag-ui](https://www.datacamp.com/tutorial/ag-ui)  
24. Using Adaptive Cards in Copilot Studio \- Microsoft Learn, accessed February 1, 2026, [https://learn.microsoft.com/en-us/microsoft-copilot-studio/adaptive-cards-overview](https://learn.microsoft.com/en-us/microsoft-copilot-studio/adaptive-cards-overview)  
25. AdaptiveCards Element \- Adaptive Cards | Microsoft Learn, accessed February 1, 2026, [https://learn.microsoft.com/en-us/adaptive-cards/schema-explorer/adaptive-card](https://learn.microsoft.com/en-us/adaptive-cards/schema-explorer/adaptive-card)  
26. AG-UI Integration with Agent Framework | Microsoft Learn, accessed February 1, 2026, [https://learn.microsoft.com/en-us/agent-framework/integrations/ag-ui/](https://learn.microsoft.com/en-us/agent-framework/integrations/ag-ui/)  
27. A2UI (Agent to UI) Protocol v0.9, accessed February 1, 2026, [https://a2ui.org/specification/v0.9-a2ui/](https://a2ui.org/specification/v0.9-a2ui/)  
28. Interactive Reasoning: Visualizing and Controlling Chain-of-Thought Reasoning in Large Language Models \- University of Washington, accessed February 1, 2026, [https://homes.cs.washington.edu/\~ypang2/papers/uist25-interactive-reasoning.pdf](https://homes.cs.washington.edu/~ypang2/papers/uist25-interactive-reasoning.pdf)  
29. ReTrace: Interactive Visualizations for Reasoning Traces of Large Reasoning Models \- arXiv, accessed February 1, 2026, [https://arxiv.org/html/2511.11187v1](https://arxiv.org/html/2511.11187v1)  
30. How we built our multi-agent research system \- Anthropic, accessed February 1, 2026, [https://www.anthropic.com/engineering/multi-agent-research-system](https://www.anthropic.com/engineering/multi-agent-research-system)  
31. AI Chat Tools Don't Match How We Actually Think: Exploring the UX of Branching Conversations | by Nikita Vergis | Medium, accessed February 1, 2026, [https://medium.com/@nikivergis/ai-chat-tools-dont-match-how-we-actually-think-exploring-the-ux-of-branching-conversations-259107496afb](https://medium.com/@nikivergis/ai-chat-tools-dont-match-how-we-actually-think-exploring-the-ux-of-branching-conversations-259107496afb)  
32. Chat History Search & Branching Conversations \- Cursor \- Community Forum, accessed February 1, 2026, [https://forum.cursor.com/t/chat-history-search-branching-conversations/59826](https://forum.cursor.com/t/chat-history-search-branching-conversations/59826)  
33. Product Idea: Enhanced Chat Dialogue with Branching (Forks) and Research Mode, accessed February 1, 2026, [https://community.openai.com/t/product-idea-enhanced-chat-dialogue-with-branching-forks-and-research-mode/1137856](https://community.openai.com/t/product-idea-enhanced-chat-dialogue-with-branching-forks-and-research-mode/1137856)  
34. Designing the infrastructure persistence layer \- .NET | Microsoft Learn, accessed February 1, 2026, [https://learn.microsoft.com/en-us/dotnet/architecture/microservices/microservice-ddd-cqrs-patterns/infrastructure-persistence-layer-design](https://learn.microsoft.com/en-us/dotnet/architecture/microservices/microservice-ddd-cqrs-patterns/infrastructure-persistence-layer-design)  
35. Human-in-the-Loop with AG-UI \- Microsoft Learn, accessed February 1, 2026, [https://learn.microsoft.com/en-us/agent-framework/integrations/ag-ui/human-in-the-loop](https://learn.microsoft.com/en-us/agent-framework/integrations/ag-ui/human-in-the-loop)  
36. AI SDK 6 \- Vercel, accessed February 1, 2026, [https://vercel.com/blog/ai-sdk-6](https://vercel.com/blog/ai-sdk-6)  
37. 2025: Replit in Review, accessed February 1, 2026, [https://blog.replit.com/2025-replit-in-review](https://blog.replit.com/2025-replit-in-review)  
38. I Turned a Complex Dashboard into a Seamless Mobile Experience — Here's What I Learned | by Pinky Jain | Muzli, accessed February 1, 2026, [https://medium.muz.li/i-turned-a-complex-dashboard-into-a-seamless-mobile-experience-heres-what-i-learned-0bb244db64cd](https://medium.muz.li/i-turned-a-complex-dashboard-into-a-seamless-mobile-experience-heres-what-i-learned-0bb244db64cd)  
39. Mobile Data Visualisation Interface Design for Industrial Automation and Control: A User-Centred Usability Study \- MDPI, accessed February 1, 2026, [https://www.mdpi.com/2076-3417/15/19/10832](https://www.mdpi.com/2076-3417/15/19/10832)  
40. Best Practices for Adapting Data Visualization for the Mobile Devices, accessed February 1, 2026, [https://datasense.to/2025/05/07/best-practices-for-adapting-data-visualization-for-the-mobile-devices/](https://datasense.to/2025/05/07/best-practices-for-adapting-data-visualization-for-the-mobile-devices/)  
41. UX/UI Design Trends for 2026 — From AI to XR to Vibe Creation | by Punit Chawla | Medium, accessed February 1, 2026, [https://blog.prototypr.io/ux-ui-design-trends-for-2026-from-ai-to-xr-to-vibe-creation-7c5f8e35dc1d](https://blog.prototypr.io/ux-ui-design-trends-for-2026-from-ai-to-xr-to-vibe-creation-7c5f8e35dc1d)