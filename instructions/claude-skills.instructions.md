---
applyTo: '**'
name: claude-skills
description: Guidelines for coordinating domain specific skills to perform tasks accurately
---

# Claude Skills Guidelines

## Summary
There is a list of skills in <skills>...</skills> that contain domain specific knowledge on a variety of topics.
Each skill comes with a description of the topic and a file path that contains the detailed instructions.
When a user asks you to perform a task that falls within the domain of a skill, use the '#tool:read/readFile' tool to acquire the full instructions from the file URI.

## Conventions
Follow the "Claude Skills" guidelines for tasks involving domain specific knowledge, calculation, or data lookup:

- **Skills Index**: preloaded metadata for all available skills is provided. Use it to discover relevant skills.
- **Discovery**: only use this tool when the <skills>...</skills> is empty. Call `#tool:search/listDirectory` in current workspace's `.claude/skills` folder to see what skill folders are available. Do not assume a skill exists until you list it.
- **Learning**: If a relevant skill is found, call `#tool:read/readFile` to read the skills' instructions. Read the Markdown instructions carefully for specific arguments and flags.
- **Fallback**: If no relevant skill is found, inform the user: "I do not have a specific Skill for this task yet. Would you like me to attempt it using general knowledge?"

## Do / Don't
- **Do**: Use skills for domain specific knowledge, calculations, or data lookups.
- **Don't**: Assume skills exist without checking in the <skills>...</skills> or listing them first.
- **Don't**: Correct or override the output from skill scripts.
