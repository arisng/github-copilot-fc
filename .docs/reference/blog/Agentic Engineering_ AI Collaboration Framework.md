Here is an analysis of the video "Agentic Engineering: Working With AI, Not Just Using It" by Brendan O'Leary \[[00:00](http://www.youtube.com/watch?v=BEKc4P87XKo&t=0)\], structured through the requested four thinking mindsets and synthesized into a comprehensive knowledge management framework.

### **Step 1: Apply Strategic Thinking**

**Goal:** Shift the paradigm from merely *using* AI as an autocomplete tool to *working* collaboratively with AI ("Agentic Engineering") to gain significant engineering leverage (e.g., gaining 30% more time in a day) \[[04:05](http://www.youtube.com/watch?v=BEKc4P87XKo&t=245)\].

**Challenges:** The primary obstacle is the illusion of productivity—jumping straight into coding with AI often leads to wrong assumptions, wasted time, and frustration \[[12:28](http://www.youtube.com/watch?v=BEKc4P87XKo&t=748)\]. Furthermore, more context does not mean better results; filling a context window past 50% degrades model reasoning \[[05:26](http://www.youtube.com/watch?v=BEKc4P87XKo&t=326)\].

**Strategy:** Prioritize "Context Engineering." Shift human effort away from syntax generation and toward high-leverage activities: problem definition, context curation, and reviewing outputs \[[17:06](http://www.youtube.com/watch?v=BEKc4P87XKo&t=1026)\].

### **Step 2: Apply Systems Thinking**

**System Map:** The modern development environment is an interconnected system of the Developer, the AI Agent, the Codebase, and external integrations like MCP (Model Context Protocol) servers \[[23:20](http://www.youtube.com/watch?v=BEKc4P87XKo&t=1400)\].

**Feedback Loops & Bottlenecks:**

* **The Context Trap (Negative Loop):** Adding excessive files, long chat histories, or unnecessary MCP servers bloats the context window. This creates a tipping point where the model becomes "dumber," hallucinating or losing the thread \[[05:33](http://www.youtube.com/watch?v=BEKc4P87XKo&t=333)\].  
* **The Poisoned Well:** If a developer goes down the wrong path and tries to steer the AI back in the same session, the AI still "sees" the bad context, causing negative patterns to compound \[[06:20](http://www.youtube.com/watch?v=BEKc4P87XKo&t=380)\].  
* **Iterative Isolation (Positive Loop):** Splitting work across parallel agents or fresh sessions isolates context. Using Git as a local "pull request" loop with the AI allows humans to catch errors before they compound \[[16:44](http://www.youtube.com/watch?v=BEKc4P87XKo&t=1004)\].

### **Step 3: Apply First Principles Thinking**

**Fundamental Truth:** AI coding models do not possess human reasoning, business context, or architectural judgment \[[03:44](http://www.youtube.com/watch?v=BEKc4P87XKo&t=224)\]. They are highly efficient statistical token predictors.

**Deconstruction:** If AI lacks judgment but excels at pattern matching, we must decouple the *thinking* phase from the *typing* phase. "A bad line of research can potentially be hundreds of lines of bad code" \[[13:33](http://www.youtube.com/watch?v=BEKc4P87XKo&t=813)\].

**Reconstruction:** Rebuild the workflow to restrict the AI from coding until the exact constraints are defined. We enforce a strict separation of concerns: Research (understanding the system) \-\> Plan (writing the steps) \-\> Implement (executing the code) \[[11:45](http://www.youtube.com/watch?v=BEKc4P87XKo&t=705)\].

### **Step 4: Apply Second Principles Thinking**

**Cross-Domain Analogy (Management):** Treat your AI agent as an energetic, enthusiastic, extremely well-read, but confidently wrong *junior developer* \[[03:21](http://www.youtube.com/watch?v=BEKc4P87XKo&t=201)\]. Just as you wouldn't hand a vague wireframe to a junior dev and expect a production-ready app without giving them specific architectural constraints \[[10:21](http://www.youtube.com/watch?v=BEKc4P87XKo&t=621)\], you must explicitly manage an AI's scope.

**Established Patterns:** \* Use conventional project documentation tailored for AI, such as an agents.md file (the de facto standard for persistent rules and project context) \[[19:48](http://www.youtube.com/watch?v=BEKc4P87XKo&t=1188)\].

* Utilize "Skills" (reusable playbooks) for repeatable, domain-specific tasks \[[20:18](http://www.youtube.com/watch?v=BEKc4P87XKo&t=1218)\].

### **Step 5: Integrate and Synthesize**

Systems thinking reveals that excessive context breaks the AI, while first principles show that AI cannot inherently filter bad context from good. Therefore, strategically, we must act as strict managers (second principles) of the AI's environment. We synthesize this into the **Research-Plan-Implement Loop**. By forcing the AI into read-only "Ask Mode" during research \[[14:02](http://www.youtube.com/watch?v=BEKc4P87XKo&t=842)\], we build a highly curated plan document. We then pass *only* that plan into a fresh implementation session \[[16:13](http://www.youtube.com/watch?v=BEKc4P87XKo&t=973)\]. This completely bypasses the systemic bottleneck of context degradation, ensuring the AI operates within a constrained, high-fidelity environment.

### ---

**Step 6: Capture Knowledge into Buckets**

#### **Factual Knowledge**

* **Working Memory:** \* **Agentic Engineering:** Working *with* AI as a collaborator, not a tool \[[02:29](http://www.youtube.com/watch?v=BEKc4P87XKo&t=149)\].  
  * **Context Engineering:** The delicate art of filling a context window with only what is strictly necessary \[[04:42](http://www.youtube.com/watch?v=BEKc4P87XKo&t=282)\].  
  * **MCP (Model Context Protocol):** Servers that give agents tools to interact with APIs (e.g., GitHub, Postgres) \[[22:58](http://www.youtube.com/watch?v=BEKc4P87XKo&t=1378)\].  
* **Reference Facts:** \* Model quality degrades when the context window is \>50% full \[[05:26](http://www.youtube.com/watch?v=BEKc4P87XKo&t=326)\].  
  * agents.md is the emerging standard file for persistent agent rules and project guidelines \[[19:48](http://www.youtube.com/watch?v=BEKc4P87XKo&t=1188)\].

#### **Procedural Knowledge (The R-P-I Playbook)**

1. **Research (Ask Mode):** Open a read-only chat session. Ask the agent to explore the codebase, trace data flows, and identify edge cases without writing code \[[14:08](http://www.youtube.com/watch?v=BEKc4P87XKo&t=848)\]. Output: A research summary doc.  
2. **Plan (Architect Mode):** Based on the research, define explicit next steps. Outline files to change, test commands to verify, and strictly define what is *out of scope*. Output: A clear plan file saved in the repository \[[15:37](http://www.youtube.com/watch?v=BEKc4P87XKo&t=937)\].  
3. **Implement (Code Mode):** Start a **brand new session** \[[16:13](http://www.youtube.com/watch?v=BEKc4P87XKo&t=973)\]. Feed the agent *only* the plan file and relevant isolated files.  
4. **Review:** Commit frequently. Treat your local Git tree as a Pull Request review between you and the AI \[[16:44](http://www.youtube.com/watch?v=BEKc4P87XKo&t=1004)\].  
5. **Reset:** If the agent goes off the rails, ask it to summarize the current state, kill the session, and start a new one with the summary to shed token bloat \[[11:02](http://www.youtube.com/watch?v=BEKc4P87XKo&t=662)\].

#### **Conceptual Knowledge**

* **Mental Model \- The Confident Intern:** The AI is infinitely fast and ego-less, but has zero business judgment. You are the Engineering Manager.  
* **Context Token Economy:** Tokens \= Cost \+ Cognitive Load. Unused MCP servers or bloated history act as a "token tax" that degrades intelligence.  
* **Agent Configuration Triad:**  
  1. *Modes:* Behavior (Ask/Research, Plan, Code).  
  2. *agents.md:* Always-on global rules (conventions, test commands).  
  3. *Skills:* On-demand, reusable task workflows.

#### **Questions**

* *Resolved:* How do we fix an AI that is writing bad code based on a previous mistake? \-\> *Resolution: Do not course-correct in the same chat. Summarize, kill the session, and start fresh.*  
* *Unresolved:* How do we optimally balance the inclusion of MCP servers for large monolithic codebases without instantly hitting the 50% "dumb zone" context threshold?  
* *Unresolved:* What is the optimal structure and maximum length for an agents.md file before it becomes detrimental?

### ---

**Final Output: Proposed Reusable Artifacts**

**1\. Context Management Playbook (Markdown Checklist)**

*A reusable checklist for developers before starting a complex task.*

* \[ \] Do I understand the problem well enough to explain it?  
* \[ \] Are unnecessary MCP servers toggled off?  
* \[ \] Did I start a fresh chat session for this specific task?  
* \[ \] Have I run "Ask Mode" to trace the system before asking for code?

**2\. agents.md Boilerplate**

*A starter template to place at the root of a project.*

Markdown

\# Agent Context  
\- **\*\*Role:\*\*** You are an expert junior engineer. You write technically perfect code but rely on the user for architecture and business logic.  
\- **\*\*Tech Stack:\*\*** \[Insert Frameworks\]  
\- **\*\*Testing:\*\*** Always run \`npm run test\` before presenting a solution.  
\- **\*\*Style:\*\*** \[Insert specific linting/formatting rules\].  
\- **\*\*Constraints:\*\*** Do not modify database schemas without explicit permission.

**3\. R-P-I Architecture Diagram (Conceptual)**

*(Suggested Mermaid.js flow for internal documentation)*

Code snippet

graph TD  
    A\[Start: New Feature/Bug\] \--\> B\[Research Session: Ask Mode\]  
    B \--\> C{Human Review}  
    C \--\>|Refine| B  
    C \--\>|Approve| D\[Plan Session: Architect Mode\]  
    D \--\> E\[Generate: step-by-step plan.md\]  
    E \--\> F\[KILL SESSION / START FRESH\]  
    F \--\> G\[Implement Session: Code Mode\]  
    G \--\> H\[Local Git Commit / PR Review\]  
    H \--\>|Errors| G  
    H \--\>|Success| I\[Push to Production\]

**Relevant YouTube Link:** [https://www.youtube.com/watch?v=BEKc4P87XKo](https://www.youtube.com/watch?v=BEKc4P87XKo)

