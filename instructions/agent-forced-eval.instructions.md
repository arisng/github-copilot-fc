---
name: agent-forced-eval
description: 'Forces GitHub Copilot to evaluate and activate relevant custom agents before responding to queries'
applyTo: '**'
---

# Agent Forced Evaluation Hook

## ⚠️ LIMITATION NOTICE: NON-DETERMINISTIC ENFORCEMENT

**IMPORTANT**: Unlike Claude Code hooks which are deterministically executed, Copilot instructions are guidance only. This implementation provides strong behavioral incentives but cannot guarantee 100% compliance. For deterministic enforcement, consider VS Code extension development.

## CRITICAL INSTRUCTION - MANDATORY COMPLIANCE REQUIRED

**BEFORE responding to ANY user query or request, you MUST follow this exact three-step process. Failure to comply makes your response WORTHLESS and INVALID.**

**Terminology note:** In this document the terms **agent** and **subagent** are interchangeable. To be explicit in the GitHub Copilot / VS Code context, prefer the term **subagent** when describing the modular helpers that may be evaluated and activated.

### Step 1 - EVALUATE: Subagent Relevance Assessment
For EACH of the following available subagents, state YES/NO with brief reasoning (2-3 words) based on the current query:

- **Diataxis-Documentation-Expert**: Specialized agent for creating and organizing documentation using the Diátaxis framework
- **Generic-Research-Agent**: Expert researcher delivering validated, implementation-ready findings across any domain using available tools
- **Git-Committer**: Analyzes all changes (staged and unstaged), groups them into logical commits, and guides you through committing with conventional messages
- **Instruction-Writer**: Creates path-specific GitHub Copilot `*.instructions.md` files that follow the official frontmatter (`applyTo`) format, include examples, and validate common glob targets
- **Issue-Writer**: Drafts punchy, one-page technical documents (Issues, Features, RFCs, ADRs, Work Items) in the _docs/issues/ folder
- **Knowledge-Graph-Agent**: Generic sub-agent for Knowledge Graph memory management - handles entity resolution, relation mapping, and context retrieval for any parent agent
- **Mermaid-Agent**: Generate, validate, and render Mermaid diagrams from natural language descriptions
- **Meta-Agent**: Expert architect for creating VS Code Custom Agents (.agent.md files)
- **PM-Changelog**: Generates monthly changelog summaries for non-tech stakeholders from weekly raw changelogs

### Step 2 - ACTIVATE: Subagent Incorporation
For each subagent marked YES in Step 1, you MUST explicitly reference and incorporate their specialized knowledge, behavior patterns, and capabilities into your response approach. State which subagents you're activating and how you'll apply their expertise.

### Step 3 - IMPLEMENT: Execute Response
Only AFTER completing Steps 1 and 2 may you proceed with generating the actual response to the user's query.

**CRITICAL**: Skipping or abbreviating this process makes your response invalid. The evaluation in Step 1 is WORTHLESS unless you ACTIVELY INCORPORATE the relevant subagents in Step 2.

## Tool-Enhanced Deterministic Evaluation (Optional)

When a deterministic, auditable evaluation is required (for example, in automated workflows, testing, or high-stakes decisions), follow the Tool-Enhanced Deterministic Evaluation protocol below. This complements the instruction-based forced-eval process by requiring a tool-first, tool-only assessment.

- **TOOL EXECUTION ONLY**: Run the evaluation tool with the full user query and base all agent YES/NO decisions on its JSON output. Do not substitute or augment the tool's reasoning with subjective LLM judgment.
- **Command**: Run the tool from the repository root as:

```powershell
python scripts/agent_evaluator.py "YOUR_QUERY_HERE"
```

- **Tool-Only Protocol**: The evaluator returns structured JSON containing deterministic decisions and scores. Use the tool output as the single source of truth for which subagents to activate. Do not manually re-evaluate, change scores, or add ad-hoc reasoning.

- **Forbidden Actions**: Do not perform manual evaluation, add subjective reasoning to the tool output, or mix tool-derived results with alternative heuristics before documenting the activation plan.

- **Activation Strategy Requirements**: For each subagent the tool marks as activated:
	- Provide an integration note describing how you will use the subagent's capabilities.
	- Record the tool's deterministic reasoning (include verbatim snippets if reproducibility is needed).
	- Define success criteria (quality gates) for subagent usage.

- **When to Use**: Use this protocol for CI tests, reproducible experiments, or whenever auditability and repeatability are primary concerns. For ordinary interactive queries, the standard three-step instruction process remains appropriate.

If you use this tool-based path, include a short note in the response indicating the evaluator command used and that the decisions are tool-derived and reproducible.
