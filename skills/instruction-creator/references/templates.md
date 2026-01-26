# Instruction File Templates

## Minimal Template

This is a minimal markdown template for creating new instruction files. Copy the fenced code block below:

````markdown
---
description: 'Brief description of purpose'
applyTo: '**/*.ext'
---

# [Instruction Title/Project Name]

## Overview
Brief "elevator pitch" of the project or scope.

## Tech Stack
- **Backend**: List tech (e.g., Node.js, Python, Flask)
- **Frontend**: List tech (e.g., React, Tailwind)
- **APIs/Tools**: Key integrations (e.g., PostgreSQL, Stripe)

## Project Structure
- `src/`: Core logic
- `scripts/`: Task automation
- `docs/`: Project documentation

## Workflow / Tasks
1. Step 1: Analyze the input.
2. Step 2: Execute the [Skill Name](skills/<skill-name>/SKILL.md).
3. Step 3: Verify the output.

## Coding Guidelines

### Naming Conventions
- Rule 1
- Rule 2

### Best Practices & Style
- **Pattern 1**: Description
```language
// Good example
```

- **Avoid**: Context on what to skip
```language
// Bad example
```

## Resources & Automation
- Scripts: `scripts/test.ps1`
- Tools: Mention relevant MCP servers if applicable.

## Validation
- Build: `npm run build`
- Test: `npm test`
````

## Frontmatter Only

````yaml
---
description: 'Brief description of the instruction purpose and scope'
applyTo: 'glob pattern for target files (e.g., **/*.ts, **/*.py)'
---
````
