---
name: custom-agent
description: 'Guidelines for creating Custom Agents, Instructions, and Skills using the Custom Agent Architecture'
applyTo: '**/*.agent.md, **/*.instructions.md, skills/**/SKILL.md'
---

# Custom Agent Architecture Guidelines

Instructions for designing and building high-quality Custom Agents using the **Agent -> Instruction -> Skill** architectural pattern.

## Architecture Overview

We follow a **Composed Architecture** pattern that strictly separates concerns into three hierarchical levels:

### Level 1: Custom Agent (`*.agent.md`)
- **Role**: The **Orchestrator** & **Interface**.
- **Responsibility**: Defines the Persona, Mission, and workflow orchestration. Registers **MCP Servers**.
- **Tooling**: Registers MCP tools; directly uses them for steering and discovery.
- **Dependency**: `Agent -> Instruction`.

### Level 2: Custom Instruction (`*.instructions.md`)
- **Role**: The **Policy Maker**.
- **Responsibility**: Defines workflow steps, decision logic, and constraints.
- **Tooling**: Can reference MCP tools for intermediate steps and directs Skills for execution.
- **Dependency**: `Instruction -> Skill` or `Instruction -> Instruction`.

### Level 3: Claude Skill (`skills/*/SKILL.md`)
- **Role**: The **Executor**.
- **Responsibility**: Defines the Mechanism for deterministic execution.
- **Tooling**: Tightly coupled **Scripts** (Python/PowerShell) located in `scripts/` subfolder.
- **Nature**: "Hard" skills with predictable outputs.

---

## Level 1: Creating Custom Agents (`.agent.md`)

Agents are the entry point. They define *who* is doing the work and *what* tools they have access to.

### File Location
- `agents/<agent-name>.agent.md`

### YAML Frontmatter

| Field | Required | Description |
|-------|----------|-------------|
| `name` | No | Display name. Defaults to filename. |
| `description` | Yes | Brief description shown in chat input. |
| `argument-hint` | No | Hint text for user interaction. |
| `tools` | Yes | List of available tools. |

**Tool Selection Guidelines:**
- **Read-only agents**: `['read/readFile', 'read/problems', 'search']`
- **Implementation agents**: `['edit/editFiles', 'edit/createFile', 'execute/runInTerminal']`
- **Research agents**: `['search', 'brave-search/brave_web_search', 'context7/*']`
- **Orchestration agents**: `['agent/runSubagent']`

### Body Structure

The body should be minimalist, focusing on persona and delegation.

```markdown
# [Agent Name]

## Version
Version: [Version]
Created At: [Timestamp]

## Persona
You are [Role Name].
[Brief description of persona and mission]

## Instructions
Strictly follow the workflow defined in:
- [[Instruction Name]](instructions/<instruction-name>.instructions.md)

## Capabilities
[Brief list of what this agent can do]
```

**Key Rule**: Do not include detailed workflow steps in the Agent file. Delegate to Instructions.

---

## Level 2: Creating Custom Instructions (`.instructions.md`)

Instructions define the *how*. They contain the logic, rules, and step-by-step procedures.

### File Location
- `instructions/<instruction-name>.instructions.md`

### YAML Frontmatter

```yaml
---
description: 'Brief description of purpose'
applyTo: 'glob pattern (e.g., **/*.ts)'
---
```

### Body Structure

```markdown
# [Instruction Title]

## Overview
[Brief introduction]

## Workflow
1. Step 1
2. Step 2 (Use [Skill Name](skills/<skill-name>/SKILL.md))
3. Step 3

## Rules & Constraints
- **Avoid Circular Dependencies**: Do not create instruction loops (A -> B -> A).
- **Validate Links**: Ensure all referenced `.instructions.md` and `SKILL.md` files exist.
- Rule 1
- Rule 2

## Examples
### Good Example
...
```

**Key Rule**: Use Semantic Linking to reference Skills.
> "To perform [Task], execute the [Skill Name](skills/<skill-name>/SKILL.md)."

### Content Guidelines

#### Writing Style
- **Imperative Mood**: Use "Use", "Implement", "Avoid" instead of "You should".
- **Specific**: Avoid ambiguous terms like "might" or "possibly".
- **Concise**: Use bullet points and lists.

#### Best Practices
- **Show Why**: Explain reasoning when it adds value.
- **Use Tables**: For comparing options or listing rules.
- **Include Examples**: Real code snippets are better than descriptions.
- **Link Resources**: Reference official docs.

#### Common Patterns
- **Good/Bad Examples**: Contrast recommended vs discouraged patterns.
- **Conditional Guidance**: "For small projects use X, for large use Y".

---

## Level 3: Creating Skills (`skills/*/SKILL.md`)

Skills define the *mechanism*. They are deterministic executors.

### File Location
- `skills/<skill-name>/SKILL.md`
- `skills/<skill-name>/scripts/` (Implementation scripts)

### Structure
Follow the standard Skill structure defined in `skills/skill-creator/SKILL.md`.

### Determinism Rules
- **Deterministic**: Use Python/PowerShell scripts for calculations, formatting, and data transformation.
- **Non-Deterministic**: Use LLMs for reasoning, summarization, and creative generation.
- **Goal**: Maximize deterministic pathways.

---

## Best Practices

1. **Separation of Concerns**:
   - Agent: "I am the Issue Writer."
   - Instruction: "Here is the format for issues."
   - Skill: "I run the script to generate the issue file."

2. **Semantic Linking**:
   - Always use Markdown links to reference Instructions and Skills.
   - `[Link Text](path/to/file.md)`

3. **Tool Usage**:
   - Use `#tool:toolName` syntax in instructions to enforce specific tool usage.
   - Example: "Use `#tool:read/readFile` to inspect the file."

4. **Dual Roles (Main vs Subagent)**:
   - Design instructions to handle both interactive (Main) and autonomous (Subagent) modes.
   - Subagents should run to completion without asking for user feedback.
