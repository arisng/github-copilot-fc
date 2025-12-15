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

### Step 1 - EVALUATE: Agent Relevance Assessment
For EACH of the following available agents, state YES/NO with brief reasoning (2-3 words) based on the current query:

- **Diataxis-Documentation-Expert**: Specialized agent for creating and organizing documentation using the Diátaxis framework
- **Generic-Research-Agent**: Expert researcher delivering validated, implementation-ready findings across any domain using available tools
- **Git-Committer**: Analyzes all changes (staged and unstaged), groups them into logical commits, and guides you through committing with conventional messages
- **Instruction-Writer**: Creates path-specific GitHub Copilot `*.instructions.md` files that follow the official frontmatter (`applyTo`) format, include examples, and validate common glob targets
- **Issue-Writer**: Drafts punchy, one-page technical documents (Issues, Features, RFCs, ADRs, Work Items) in the _docs/issues/ folder
- **Knowledge-Graph-Agent**: Generic sub-agent for Knowledge Graph memory management - handles entity resolution, relation mapping, and context retrieval for any parent agent
- **Mermaid-Agent**: Generate, validate, and render Mermaid diagrams from natural language descriptions
- **Meta-Agent**: Expert architect for creating VS Code Custom Agents (.agent.md files)
- **PM-Changelog**: Generates monthly changelog summaries for non-tech stakeholders from weekly raw changelogs

### Step 2 - ACTIVATE: Agent Incorporation
For each agent marked YES in Step 1, you MUST explicitly reference and incorporate their specialized knowledge, behavior patterns, and capabilities into your response approach. State which agents you're activating and how you'll apply their expertise.

### Step 3 - IMPLEMENT: Execute Response
Only AFTER completing Steps 1 and 2 may you proceed with generating the actual response to the user's query.

**CRITICAL**: Skipping or abbreviating this process makes your response invalid. The evaluation in Step 1 is WORTHLESS unless you ACTIVELY INCORPORATE the relevant agents in Step 2.</content>
<parameter name="filePath">c:\Workplace\Agents\github-copilot-fc\instructions\agent-forced-eval.instructions.md