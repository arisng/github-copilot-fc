# Custom Toolsets Reference

Custom toolsets provide a way to group related tools for easier management and reference in GitHub Copilot chat prompts in VS Code.

## Overview

Custom toolsets allow users to define collections of tools that can be referenced as a single entity in chat interactions. This helps organize tools by functionality or domain, making it easier to enable or disable groups of related tools at once.

Toolsets are defined in JSONC configuration files and can include built-in tools, MCP server tools, and extension-contributed tools.

## Configuration File Structure

Toolsets are defined in `.toolsets.jsonc` files with the following structure:

```jsonc
{
  "toolset-name": {
    "tools": ["tool1", "tool2", "tool3"],
    "description": "Brief description of the toolset's purpose",
    "icon": "icon-name"
  }
}
```

### Properties

| Property    | Type   | Required | Description                                                                                                     |
| ----------- | ------ | -------- | --------------------------------------------------------------------------------------------------------------- |
| tools       | array  | Yes      | Array of tool names to include in the toolset. Tool names can be built-in tools, MCP tools, or extension tools. |
| description | string | No       | User-friendly description displayed in the tools picker.                                                        |
| icon        | string | No       | Icon identifier for the toolset, using VS Code's product icon reference.                                        |

## Creating Toolsets

Toolsets are created through the VS Code interface:

1. Run the `Chat: Configure Tool Sets` command from the Command Palette.
2. Select `Create new tool sets file`.
3. Define toolsets in the opened `.jsonc` file.

Alternatively, create the file manually in your workspace or user settings.

## Using Toolsets

Toolsets can be referenced in chat prompts by typing `#` followed by the toolset name:

- `"Analyze the codebase #reader"`
- `"Search for issues #search"`

In the tools picker, toolsets appear as collapsible groups, allowing selection or deselection of entire groups.

## Tool Types

Toolsets can include:

- **Built-in tools**: Core VS Code tools like `changes`, `codebase`, `problems`.
- **MCP tools**: Tools provided by installed MCP servers.
- **Extension tools**: Tools contributed by VS Code extensions.

## Constraints

- Tool names must be exact matches to available tools.
- A single chat request cannot exceed 128 tools total.
- Toolsets are workspace-specific unless defined in user settings.

## Related References

- [Chat Tools Documentation](https://code.visualstudio.com/docs/copilot/chat/chat-tools)
- [MCP Servers](https://code.visualstudio.com/docs/copilot/customization/mcp-servers)