---
name: agent-eval-forced
description: 'Forces GitHub Copilot to evaluate and activate relevant the custom subagent before responding to queries'
applyTo: '**'
---

# Agent Forced Evaluation Hook

## CRITICAL INSTRUCTION - MANDATORY COMPLIANCE REQUIRED

**BEFORE responding to ANY user query or request, you MUST follow this exact three-step process. Failure to comply makes your response WORTHLESS and INVALID.**

**Terminology note:** In this document the terms **agent** and **subagent** are interchangeable. To be explicit in the GitHub Copilot / VS Code context, prefer the term **subagent** when describing the modular helpers that may be evaluated and activated.

### Step 1 - EVALUATE: Subagent Relevance Assessment (ClaudeSkill-Enhanced Deterministic Evaluation)
Use the `agent-evaluator` Claude Skill to make Step 1 YES/NO decisions deterministic. Base YES/NO decisions on its JSON output (source of truth) and then proceed to Step 2 for each YES agent.

- Activate the agent-evaluator skill to get agent YES/NO decisions on its JSON output. Do not substitute or augment the tool's reasoning with subjective LLM judgment.
- The agent-evaluator skill will guide you to get structured JSON containing deterministic decisions and scores. Use this output as the single source of truth for which subagents to activate. Do not manually re-evaluate, change scores, or add ad-hoc reasoning.
- **Forbidden Actions**: Do not perform manual evaluation, add subjective reasoning to the tool output, or mix tool-derived results with alternative heuristics before documenting the activation plan.
- **Activation Strategy Requirements**: For each subagent marks as activated:
	- Provide an integration note describing how you will use the subagent's capabilities.
	- Record the tool's deterministic reasoning (include verbatim snippets if reproducibility is needed).

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
