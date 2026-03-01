# GitHub Copilot Prompt Files (.prompt.md) Reference

**Documentation Date:** January 22, 2026  
**Source:** Official VS Code Documentation (v1.108+)

## Overview

Prompt files (`.prompt.md`) are reusable Markdown documents that define standalone AI prompts for VS Code GitHub Copilot. They provide a structured way to package instructions, context variables, and tool configurations for specific development tasks.

## Anatomy of a Prompt File

### YAML Frontmatter (Header)

The header is an optional YAML block that configures the execution environment and user interface behavior.

| Field         | Type     | Description                                                               |
| ------------- | -------- | ------------------------------------------------------------------------- |
| `name`        | string   | The command name triggered by `/` in chat. Defaults to filename.          |
| `description` | string   | Brief summary displayed in the command suggestion list.                   |
| `agent`       | enum     | Execution mode: `ask`, `edit`, `agent`, or a custom agent name.           |
| `model`       | string   | Target LLM (e.g., `gpt-4o`, `claude-3.5-sonnet`, `o1`).                   |
| `tools`       | string[] | Tools accessible in `agent` mode (e.g., `['read_file', 'mcp-server/*']`). |
| `arg-hint`    | string   | Placeholder hint shown in the chat input to guide user input.             |

### Body

The body contains the instruction text sent to the LLM. It supports Markdown and specific variable interpolation.

## Context Variables

### Dynamic Input Variables

| Variable                   | Description                                  |
| -------------------------- | -------------------------------------------- |
| `${input:varName}`         | Prompts user for a custom string.            |
| `${input:varName:default}` | Prompts user with a suggested default value. |

### Editor Context Variables

| Variable                     | Value                                          |
| ---------------------------- | ---------------------------------------------- |
| `${selection}`               | Content of the active highlighted code.        |
| `${file}`                    | Full path to the active file.                  |
| `${fileBasename}`            | Filename with extension.                       |
| `${fileBasenameNoExtension}` | Filename without extension.                    |
| `${fileDirname}`             | Full path to the directory of the active file. |

### Workspace Variables

| Variable                     | Value                             |
| ---------------------------- | --------------------------------- |
| `${workspaceFolder}`         | Full path to the workspace root.  |
| `${workspaceFolderBasename}` | The name of the workspace folder. |

## Integrated Context Symbols (#)

Symbols used in the prompt body to ground responses in specific workspace data:

- `#codebase`: Invokes an indexed semantic search across the entire workspace.
- `#file`: Explicitly references a specific file path for context.
- `#terminal`: Captures the most recent buffer and state from active terminals.
- `#git`: Includes current git diffs, branch info, or commit history.
- `#tool:<tool-name>`: Explicitly signals the use of a specific integrated tool.

## Comparison: Prompt Files vs. Instruction Files

GitHub Copilot supports two distinct types of customization files. Choosing the correct one depends on whether the guidance should be persistent or on-demand.

| Feature           | Instruction Files (`.instructions.md`)                                                            | Prompt Files (`.prompt.md`)                                                            |
| :---------------- | :------------------------------------------------------------------------------------------------ | :------------------------------------------------------------------------------------- |
| **Primary Goal**  | Persistent domain rules, style guides, and constraints.                                           | Standardized, reusable task workflows and sequences.                                   |
| **Activation**    | **Automatic & Implicit**: Applied automatically to all queries (or specific files via `applyTo`). | **Manual & Explicit**: Triggered by the user in chat using the `/` command.            |
| **Storage Path**  | `.github/instructions/`                                                                           | `.github/prompts/`                                                                     |
| **Frontmatter**   | Focuses on `applyTo` (glob patterns) and `description`.                                           | Focuses on `agent`, `model`, `tools`, and `arg-hint`.                                  |
| **Context**       | Usually static rules that apply globally.                                                         | Dynamic context using `${variables}` for inputs and selections.                        |
| **Best Used For** | "Always use tabs," "Follow project naming conventions," "Use library X version Y."                | "Generate a new React component," "Perform a code review," "Setup a new API endpoint." |

## Execution Constraints

### Tool Priority

1. **Direct**: Tools specified in the `.prompt.md` frontmatter.
2. **Inherited**: Tools from the referenced custom `agent`.
3. **Global**: Default tools associated with the selected chat mode.

### Scope and Storage

- **Workspace-Level**: Located in `.github/prompts/`. Restricted to the specific repository.
- **Profile-Level**: Stored in VS Code User Profile. Available across all workspaces and synced via Settings Sync.

## Related References

- [Official Prompt Engineering Guide](https://code.visualstudio.com/docs/copilot/guides/prompt-engineering-guide)
- [Custom Instructions Reference](https://code.visualstudio.com/docs/copilot/customization/custom-instructions)
- [Copilot Chat Tools Reference](https://code.visualstudio.com/docs/copilot/chat/chat-tools)
