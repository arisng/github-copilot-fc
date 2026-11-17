---
name: create-plugin
agent: 'agent'
description: 'Create a new GitHub Copilot agent plugin by using Agent Skill copilot-plugin-creator as the single source of truth.'
argument-hint: 'Describe the plugin you want; copilot-plugin-creator will drive the full workflow'
metadata:
  version: 1.0.0
  author: arisng
---

# Create Agent Plugin

Create a new GitHub Copilot agent plugin by delegating to Agent Skill `copilot-plugin-creator`.

## User Input

```text
$ARGUMENTS
```

You MUST consider the user input before proceeding. If the request leaves key decisions unspecified, ask only the minimum clarifying questions needed to create the plugin correctly.

## Goal

Use Agent Skill `copilot-plugin-creator` as the single source of truth for plugin creation knowledge and workflow.

## Execution Rules

1. Load and follow Agent Skill `copilot-plugin-creator`.
2. Do not introduce plugin-creation rules that are not defined by the skill.
3. Ensure the skill performs deep analysis of user input and available context to infer likely plugin components.
4. Prefer proactive component gathering on behalf of the user when component lists are missing.
5. Keep implementation focused on the user request.
6. If required decisions remain ambiguous after analysis, ask concise follow-up questions.

## Output Requirements

After making changes:

- Summarize the plugin shape you created
- Summarize the inferred component decisions and why they were selected
- List any assumptions you had to make
- Provide the most relevant next validation step, such as local install, enablement, or publish script usage

## Quality Bar

- Treat Agent Skill `copilot-plugin-creator` as the only authoritative source for plugin creation behavior.
- Keep this prompt minimal and delegate all plugin-creation knowledge to the skill.