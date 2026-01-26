# Instruction Creation Guidelines

## Architecture Context

This file defines **Level 2: Custom Instruction** in the **Agent -> Instruction -> Skill** architecture.

- **Role**: The **Policy Maker**.
- **Responsibility**: Defines workflow steps, decision logic, and constraints.
- **Dependency**: Referenced by Agents (`*.agent.md`); References Skills (`skills/*/SKILL.md`).

## Frontmatter Guidelines

- **description**: Single-quoted string, 1-500 characters, clearly stating the purpose.
- **applyTo**: Glob pattern(s) specifying which files these instructions apply to.
  - Single pattern: `'**/*.ts'`
  - Multiple patterns: `'**/*.ts, **/*.tsx, **/*.js'`
  - Specific files: `'src/**/*.py'`
  - All files: `'**'`

## Content Guidelines

### The "5 Tips" Foundation (2026 Update)
Based on latest official recommendations, effective instruction files should include:
- **Project Overview**: The "elevator pitch" for the app. What is it? Who is it for? Key features?
- **Tech Stack**: Explicit list of backend, frontend, APIs, and tools in use.
- **Project Structure**: High-level map of where key files/directories live.
- **Coding Guidelines**: Specific rules for naming, style, security, and performance.
- **Resources**: Pointers to internal scripts (build, test, deploy) and integrated MCP servers.

### Writing Style
- Use clear, concise language.
- Write in imperative mood ("Use", "Implement", "Avoid").
- Be specific and actionable.
- Avoid ambiguous terms like "should", "might", "possibly".
- Use bullet points and lists for readability.

### Formatting & Structure
- **Sections**: Use distinct headings (`##`) to separate topics.
- **Examples**: Provide concrete code snippets showing both correct and incorrect patterns.
- **Conciseness**: Keep individual files focused. Limit a single file to ~1,000 lines.
- **Imperative Directives**: Use short, direct commands instead of long narrative paragraphs.

### Semantic Linking & Memory
- **Link to Skill**: `To perform [Task], execute the [Skill Name](skills/<skill-name>/SKILL.md).`
- **Link to Instruction**: `Follow the [Sub-Process](instructions/<name>.instructions.md).`
- **Link to Local Resources**: Reference local scripts and tools explicitly (e.g., `scripts/deploy.ps1`).

### Code Review Specifics
When writing instructions for code review (`*.instructions.md`), include:
- **Security Critical Issues**: Specific things to look for (secrets, injection, etc.).
- **Performance Red Flags**: N+1 queries, inefficient loops, resource cleanup.
- **Review Style**: Instructions on how Copilot should comment (e.g., "Explain the 'why'", "Acknowledge good patterns").

## Patterns to Avoid
- **Overly verbose explanations**: Keep it concise and scannable.
- **External Links**: Copilot cannot follow external URLs; copy-paste relevant standards directly if needed.
- **UI/UX Customization**: Instructions trying to change Copilot's UI/Emoji/Formatting are not supported.
- **Vague Directives**: Avoid "Be more accurate" or "Don't miss issues".
- **Ambiguous guidelines**: Be specific about what to do or avoid.
- **Missing examples**: Abstract rules without concrete code examples.
- **Contradictory advice**: Ensure repository-wide and path-specific instructions don't conflict.
