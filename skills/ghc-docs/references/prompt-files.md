# GitHub Copilot Prompt Files Reference (Jan 2026)

**Documentation Date:** January 22, 2026  
**Source:** Official VS Code Documentation (v1.108+)

## Overview

Prompt files (`.prompt.md`) are reusable Markdown files that define standalone prompts for common development tasks. They enabling the creation of standardized, shareable development workflows that can be triggered on-demand in Chat.

## Location & Scope

- **Workspace Prompts**: Stored in `.github/prompts/`. Only available within the specific workspace.
- **User Prompts**: Stored in the VS Code user profile. Available across all workspaces.
- **Extension Prompts**: Contributed by installed extensions.

## Comparison: Prompt Files vs. Instruction Files

| Feature          | Instruction Files (`.instructions.md`)        | Prompt Files (`.prompt.md`)            |
| :--------------- | :-------------------------------------------- | :------------------------------------- |
| **Primary Goal** | Persistent rules and constraints.             | Standardized, reusable workflows.      |
| **Activation**   | **Automatic**: Applied implicitly to queries. | **Manual**: Triggered via `/` command. |
| **Storage Path** | `.github/instructions/`                       | `.github/prompts/`                     |
| **Variables**    | Static context.                               | Dynamic context (`${variables}`).      |
| **Use Case**     | Project style, security standards.            | Component generation, code reviews.    |

## File Structure

### 1. Header (YAML Frontmatter)

The optional header configures how the prompt is executed and presented in the UI.

| Field         | Description                                                                          |
| ------------- | ------------------------------------------------------------------------------------ |
| `name`        | The command name used after `/` in chat. Defaults to filename if omitted.            |
| `description` | Short summary shown in the `/` command list.                                         |
| `agent`       | Execution mode/agent: `ask`, `edit`, `agent`, or a custom agent name.                |
| `model`       | Specific LLM to use (e.g., `gpt-4o`, `claude-3.5-sonnet`, `o1`).                     |
| `tools`       | Array of tools available to the agent (e.g., `['read_file']` or `['mcp-server/*']`). |
| `arg-hint`    | Placeholder text shown in the chat input field to guide the user.                    |

### 2. Body

The Markdown body contains the instructions sent to the AI. Use it to specify goals, requirements, and output formats.

## Context Variables & Syntax

### Dynamic Inputs

- `${input:variableName}`: Prompts the user for a value.
- `${input:variableName:defaultValue}`: Prompts with a suggested default.

### Selection & Current File

- `${selection}` / `${selectedText}`: Content of the active editor selection.
- `${file}`: Active file path.
- `${fileBasename}`: Filename with extension.
- `${fileBasenameNoExtension}`: Filename without extension.
- `${fileDirname}`: Absolute path to the file's directory.

### Workspace Context

- `${workspaceFolder}`: Absolute path to the workspace root.
- `${workspaceFolderBasename}`: Name of the workspace folder.

### Integrated Context Items (#)

These can be used in the prompt body to ground the AI in specific data:
- `#codebase`: Triggers an indexed search of the entire workspace.
- `#file`: Explicitly references a file for context.
- `#terminal`: Includes recent terminal output.
- `#git`: Includes current git status or staged changes.
- `#tool:<tool-name>`: References a specific agent tool.

## Tool Priority Logic

When multiple tools are available, VS Code resolves them in this order:
1. Tools explicitly listed in the `.prompt.md` frontmatter.
2. Tools defined by the referenced custom agent.
3. Default tools for the selected agent mode.

## Best Practices

- **Conciseness**: Keep instructions specific and actionable; use bullet points over paragraphs.
- **Grounding**: Always prefer referencing files or `#codebase` over manual copy-pasting for complex tasks.
- **Reuse**: Use Markdown links inside prompt files to reference `.instructions.md` documents rather than duplicating rules.
- **Model Selection**: Use reasoning models (`o1`, `claude-3.7-thinking`) for planning and fast models (`gemini-2.0-flash`) for simple generation.
- **Variable Defaults**: Provide `defaultValue` for inputs to make prompts "runnable" with minimal typing.
