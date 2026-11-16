# GitHub Copilot Prompt Files Reference

**Verified against:** https://code.visualstudio.com/docs/agent-customization/prompt-files — **Verification date:** November 16, 2026 (VS Code 1.146 stable)

## Overview & Status

Prompt files (`.prompt.md`) are reusable Markdown files that you invoke manually as slash commands in chat. Unlike custom instructions, which apply automatically, prompt files run only when triggered with `/`.

> **Deprecated path:** prompt files run only in **Local** harness sessions, and the Local harness is deprecated (removal planned **February 2027**). Before then, convert prompt files to skills for use with the Copilot harness: https://code.visualstudio.com/docs/agent-customization/migrate-customizations. For new reusable workflows, create an agent skill instead: https://code.visualstudio.com/docs/agent-customization/agent-skills. Use this reference when maintaining existing prompt files or answering questions about them.

## Locations

| Scope | Default location |
| --- | --- |
| Workspace | `.github/prompts/` folder |
| User profile | User data for the current VS Code profile |

- User prompt files sync across devices via Settings Sync (**Settings Sync: Configure** → **Prompts and Instructions**).
- In a monorepo, enable `chat.useCustomizationsInParentRepositories` to discover prompt files from a parent repository root.

## Comparison: Instructions vs. Prompt Files vs. Skills

| Feature | Instruction Files (`.instructions.md`) | Prompt Files (`.prompt.md`) | Skills (`SKILL.md`) |
| :--- | :--- | :--- | :--- |
| **Primary Goal** | Persistent rules and constraints | Standardized, reusable prompts | Reusable multi-step workflows |
| **Activation** | **Automatic**: applied to matching context | **Manual**: triggered via `/` command | Invoked by name or discovered by the agent |
| **Storage Path** | `.github/instructions/` | `.github/prompts/` | Skill folder (see the agent-skills doc) |
| **Harness support** | Copilot and Local | Local only (deprecated) | Copilot harness |

## File Format

### 1. Header (YAML Frontmatter)

All fields are optional:

| Field | Description |
| --- | --- |
| `name` | The command name used after `/` in chat. Defaults to the file name. |
| `description` | Short summary shown in the `/` command list. |
| `argument-hint` | Placeholder text shown in the chat input field. The current field name is `argument-hint`; the older `arg-hint` spelling does not appear in the current VS Code source. |
| `agent` | Agent used to run the prompt: `ask`, `agent`, `plan`, or a custom agent name. Defaults to the current agent; if `tools` is specified, the default is `agent`. |
| `model` | Language model used when running the prompt. Defaults to the model picker selection. |
| `tools` | Tools available to the prompt: built-in tools, MCP tools (`<server name>/*` covers a whole server), or extension tools. Tool-set references are deprecated. Unavailable tools are ignored. |

### 2. Body

The Markdown body contains the instructions sent to the AI. Use it to specify goals, requirements, and output formats.

## Context Syntax

### Documented variables and references
- `${selection}`: content of the active editor selection.
- `${input:variableName}`: prompts the user for a value.
- `${input:variableName:placeholder}`: prompts with a suggested placeholder (the current docs call it a placeholder, not a default value).
- Markdown links to instruction files, e.g. `[coding standards](../instructions/coding.instructions.md)`.
- `#file:<path>`: reference a file; use workspace-relative paths, or `~/...` for the user home folder.
- `#tool:<tool-name>`: reference an agent tool, e.g. `#tool:browser`.
- Use Unix-style `/` path separators to keep prompt files portable across operating systems.
- The `vscode/askQuestion` tool can be used when the prompt needs structured input from the user.

### Context mentions in chat input
- When running the prompt, `#`-mentions add context: files, folders, symbols, terminal output, source-control changes, `#codebase` (workspace search), and `#fetch` (web content). See https://code.visualstudio.com/docs/chat/copilot-chat-context

### Known gap
Older material listed additional variables (`${file}`, `${fileBasename}`, `${fileDirname}`, `${workspaceFolder}`, ...). The current official page documents only `${selection}` and `${input:...}` — verify against the live page before relying on undocumented variables.

## Tool Priority Logic

When multiple sources provide tools, VS Code resolves them in this order:
1. Tools explicitly listed in the `.prompt.md` frontmatter.
2. Tools defined by the referenced custom agent.
3. Default tools for the selected agent mode.

## Running and Verifying

- Select the **Local** harness in the Chat view, then type `/name` (extra text after the command is passed along), run **Chat: Run Prompt** from the Command Palette, or use the play button in the editor title area.
- The `chat.promptFilesRecommendations` setting surfaces prompts as recommended actions when starting a new chat session.
- Verify discovery in a fresh Local chat (`/` should list the command), then verify effectiveness by checking the result quality.
- Troubleshooting: confirm the `.prompt.md` extension, file location, and frontmatter syntax, then inspect the Agent Debug Log (ellipsis menu in the Chat view).

## Best Practices

- **Conciseness**: Keep instructions specific and actionable; use bullet points over paragraphs.
- **Grounding**: Prefer file references over copy-pasting large context for complex tasks.
- **Reuse**: Use Markdown links inside prompt files to reference `.instructions.md` documents rather than duplicating rules.
- **Model Selection**: Use the `model` field when a specific model is required for the task.
- **Variable Defaults**: Provide a placeholder for `${input:...}` variables to make prompts runnable with minimal typing.
- **Migration**: To reuse a workflow under the Copilot harness, convert the prompt file to a skill: https://code.visualstudio.com/docs/agent-customization/migrate-customizations
