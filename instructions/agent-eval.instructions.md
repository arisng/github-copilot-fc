---
name: agent-eval
description: 'Guide GitHub Copilot to evaluate and activate relevant subagent before responding to queries'
#applyTo: '**'
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
- **Knowledge-Graph-Agent**: Generic sub-agent for Knowledge Graph memory management - handles entity resolution, relation mapping, and context retrieval for any parent agent
- **Mermaid-Agent**: Generate, validate, and render Mermaid diagrams from natural language descriptions
- **Meta-Agent**: Expert architect for creating VS Code Custom Agents (.agent.md files)
- **PM-Changelog**: Generates monthly changelog summaries for non-tech stakeholders from weekly raw changelogs

### Step 2 - ACTIVATE: Call runSubagent tool to activate the subagent
For each subagent marked YES in Step 1, you MUST call the runSubagent tool and MUST pass the exact subagent name via the agentName parameter. This activates the subagent and incorporates their specialized knowledge, behavior patterns, and capabilities into your response approach. State which subagents you're activating and how you'll apply their expertise.

Example:
```
runSubagent(agentName: "Git-Committer", prompt: "Please run as subagent. Analyze the current git changes and prepare commit messages.")
```

If no subagents are marked YES, you may skip this step and proceed directly to Step 3.

### Step 3 - IMPLEMENT: Execute Response
Only AFTER completing Steps 1 and 2 may you proceed with generating the actual response to the user's query.

**CRITICAL**: Skipping or abbreviating this process makes your response invalid. The evaluation in Step 1 is WORTHLESS unless you ACTIVELY INCORPORATE the relevant subagents in Step 2.
