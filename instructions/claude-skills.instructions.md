---
name: claude-skills
description: Guidelines for coordinating domain specific skills to perform tasks accurately
#uncomment applyTo auto-apply this file
#applyTo: '**'
---

# Claude Skills Guidelines

## Summary
Always check for relevant Claude Skills in user-level (`${env:USERPROFILE}\.claude\skills\`) and workspace-specific (`\.claude\skills\`) directories before responding to requests involving domain-specific knowledge, calculations, or data lookups. Each skill includes a description and file path with detailed instructions. If found, read and follow the skill instructions to complete the request accurately.

## Conventions
Follow these steps to resolve skills for user requests:

- **User Skills Discovery**: Use the `mcp_filesystem_list_directory` tool to list skills in `${env:USERPROFILE}\.claude\skills\` (user-level skills outside the current workspace).
- **Workspace Skills Discovery**: Use the `read_file` tool to check current workspace skills in `\.claude\skills\` (workspace-specific skills). Do not use `mcp_filesystem_list_directory` for workspace skills.
- **Activate Skill**: If a relevant skill is found, use `mcp_filesystem_read_text_file` for user-level skills or `read_file` for workspace skills to read the instructions, then apply them.
- **Skill Priority**: Prioritize workspace-specific skills over user-level ones if duplicates exist.
- **Fallback**: If no relevant skill is found, inform the user: "I do not have a specific Skill for this task yet. Would you like me to attempt it using general knowledge?"

**Examples**: 
- For a request like "Calculate Vietnamese payroll taxes," first discover skills (e.g., check `vn-payroll/` in workspace skills), read the `SKILL.md`, and follow its calculation instructions.
- For a request like "Discuss latest Github Copilot updates" first discover skills (e.g., check `vscode-docs-researcher/` in user-level skills), read the `SKILL.md`, and follow its research instructions.

## Do / Don't
- **Do**: Always use skills for domain-specific knowledge, calculations, or data lookups (e.g., financial computations, API integrations).
- **Do**: Only read skill files after confirming their relevance to the user request.
- **Do**: Prioritize workspace-specific skills over user-level skills when both are available.
- **Do**: Only fallback to general knowledge or external tools if no relevant skills are found.
- **Don't**: Solely rely on skill names and descriptions from attachments, as they may be unreliable.
- **Don't**: Use `mcp_filesystem_list_directory` to read files in the current workspace's skills directory.
- **Don't**: Use `mcp_filesystem_read_text_file` for skill files in the current workspace.
- **Don't**: Read a SKILL.md file without first verifying its relevance to the request.

<reminderInstructions>
When writing a task into the manage_todo_list to track your process, always add first task as "Before conducting web searches, always discover user-level and workspace-specific skills before responding to user requests that may require domain specific knowledge. If any skills found, then use those relevant skills to complete the user request" before any other tasks. Then add second task as "If no relevant skills found, then use available tools to complete the user request".
</reminderInstructions>

<importanReminder>
Before performing web searches or using external tools, always discover user-level and workspace-specific skills to see if any relevant skills are available to complete the user request. If found relevant skills, use them to complete the task instead of relying on web searches or external tools.
</importanReminder>