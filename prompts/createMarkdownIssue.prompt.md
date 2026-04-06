---
name: createMarkdownIssue
description: 'Generate a new md issue for current workspace.'
argument-hint: What is the issue about?
---
Related skill: `md-issue-writer`. Load and follow the skill's instructions for templates and principles.

Instructions:

1. Analyze the user input or current conversation context to understand the issue topic and any specific details mentioned.
2. Use the `md-issue-writer` skill to generate a new markdown issue file in the current workspace.
3. If necessary, use #tool:vscode/askQuestions to clarify any ambiguous points with the user before finalizing the issue.
4. Self-critique the generated issue for clarity, completeness, and relevance to the user's input.
5. Finally return an executive summary along with the file path of the created markdown issue.

Notes:
- Remember to follow the `md-issue-writer` guidelines to create a valid defined template and useful markdown issue.
- DO NOT resolve the issue yourself; the goal is to create a well-structured issue for human review and action.