---
agent: 'agent'
description: 'Generate a new Codex Custom Prompt file (.md) with appropriate metadata and instructions.'
---

# Create a Codex Custom Prompt

You are an expert at writing prompts for Codex. Your task is to generate the content for a new Codex Custom Prompt based on the following details.

## Context
- **Name**: ${input:promptName:my-custom-prompt}
- **Description**: ${input:description:A brief description of what this prompt does}
- **Argument Hint**: ${input:argHint:[ARGUMENTS]}
- **Purpose**: ${input:purpose:Describe the goal of the prompt}

## Instructions
1.  **Format**: Generate a Markdown file starting with YAML frontmatter.
2.  **Metadata**:
    - `description`: Use the description provided.
    - `argument-hint`: Use the argument hint provided.
3.  **Content**:
    - Write clear, concise instructions for Codex.
    - Use placeholders like `$ARGUMENTS` or `$1`, `$2`, etc. if positional arguments are needed.
    - Use named placeholders (e.g., `$FILE`, `$TASK`) if appropriate.
4.  **Usage Instructions**: Provide a brief note at the end on where to save this file (`~/.codex/prompts/${promptName}.md`) and how to invoke it (`/prompts:${promptName}`).

## Reference (Codex Custom Prompt Spec)
Custom prompts live in `~/.codex/prompts/` as Markdown files with:
```yaml
---
description: ...
argument-hint: ...
---
Prompt body...
```
Invoke via `/prompts:<name>` in Codex.

### Argument Hint & Placeholder Conventions

#### Argument Hint Syntax
- **`argument-hint`**: A string shown in the slash command menu to guide the user.
- **Required Arguments**: Usually written as `KEY=<value>` (e.g., `FILE=<path>`).
- **Optional Arguments**: Wrapped in square brackets `[KEY=<value>]` (e.g., `[LANG=python]`).
- **Default Values**: Specify defaults inside the brackets for optional arguments (e.g., `[MAX_LENGTH=500]`). Note that Codex handles value substitution; if the user provides a value, it replaces the default.
- **Multiple Arguments**: Separated by spaces (e.g., `NAME=<name> [AGE=<age>]`).

#### Placeholder Types
- **Positional**: `$1` through `$9` refers to space-separated values provided after the command. `$ARGUMENTS` captures everything.
- **Named**: Uppercase names like `$FILE` or `$TICKET_ID`. Values are passed as `KEY=value`. Placeholders in the prompt body MUST match the name in the hint.
- **Literal Dollar Signs**: Use `$$` to escape a dollar sign (e.g., `$$VAR` becomes `$VAR`).

#### Hidden Conventions & Tips
- **Restart Required**: Codex scans `~/.codex/prompts/` only at startup. Restart the CLI or reload the IDE extension after changes.
- **Case Sensitivity**: While most conventions use UPPERCASE for named placeholders (e.g., `$FILE`), consistency between the prompt body and user input keys is critical.
- **No Subdirectories**: Codex only scans the top-level of the `prompts/` folder.
- **Quoting**: If an argument value contains spaces, it must be quoted in the command: `PR_TITLE="My new feature"`.

## Real-Life Examples for Inspiration

### Example 1: Commit Message Generator
**Filename**: `~/.codex/prompts/commit.md`
```markdown
---
description: Generate a conventional commit message for staged changes
argument-hint: [SCOPE=<scope>]
---
Review the staged changes and generate a concise commit message following the Conventional Commits specification.
Format: <type>($SCOPE): <description>
Use 'feat' for new features, 'fix' for bug fixes, and 'docs' for documentation.
```
**Usage**: `/prompts:commit SCOPE=ui`

### Example 2: Unit Test Boilerplate
**Filename**: `~/.codex/prompts/testgen.md`
```markdown
---
description: Create a Jest test suite for a specific function
argument-hint: FUNCTION_NAME=<name> FILE_PATH=<path>
---
Read the function $FUNCTION_NAME in $FILE_PATH.
Generate a Jest test suite with at least 3 test cases:
1. Happy path
2. Edge case (null/undefined)
3. Error handling
Include necessary imports for the file.
```
**Usage**: `/prompts:testgen FUNCTION_NAME=calculateTax FILE_PATH=src/utils/math.ts`

### Example 3: Documentation Summary
**Filename**: `~/.codex/prompts/summarize.md`
```markdown
---
description: Summarize a markdown file for a README
argument-hint: [MAX_LENGTH=500]
---
Summarize the current file content in under $MAX_LENGTH characters.
Focus on the 'Getting Started' and 'Key Features' sections.
Output the summary as a bulleted list.
```
**Usage**: `/prompts:summarize MAX_LENGTH=300`
