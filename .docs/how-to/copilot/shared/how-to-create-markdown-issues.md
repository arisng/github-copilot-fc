---
category: how-to
---

# How to Create Markdown Issues

This guide shows how to create repository-local issue documents under `.issues/` without accidentally turning the drafting step into implementation work.

## When to Use This Guide

Use this when you want to:

- capture a feature request, task, RFC, or bug as a markdown issue
- use the workspace prompt and issue-writing skill as drafting helpers
- keep issue creation separate from issue resolution

## Prerequisites

- the workspace is open at the repository root
- `.issues/` exists
- the markdown issue workflow prompt and issue-writing skill are available in your runtime

## Steps

### 1. Start from the markdown issue workflow prompt

Use the `createMarkdownIssue.prompt.md` workflow when you want the agent to draft an issue file from your request.

### 2. Describe the problem or proposal

Give the prompt enough detail to produce:

- a clear objective
- scoped tasks or acceptance criteria
- relevant references
- a severity and status that match the current stage

### 3. Keep drafting separate from implementation

During issue creation, the agent should:

- structure the issue
- follow the repository's markdown issue template guidance
- return the created file path

During issue creation, the agent should **not**:

- resolve the issue immediately
- make unrelated code changes
- blur drafting and execution into one step

### 4. Reindex issues after adding or changing one

```powershell
pwsh -NoProfile -File scripts/issues/extract-issue-metadata.ps1
```

This updates `.issues/index.md` so the new issue is discoverable.

## Troubleshooting

**Problem: the issue is too implementation-heavy**

Reduce the scope to the problem statement, acceptance criteria, and references. Leave the fix for a later implementation task.

**Problem: the new issue is missing from the index**

Run the metadata extraction script again from the repository root and verify the file has valid frontmatter.

## See Also

- [scripts/issues/extract-issue-metadata.ps1](../../../../../scripts/issues/extract-issue-metadata.ps1)
- [Task: Design workflow to track Copilot release issues via GitHub query](../../../../../.issues/260315_design-workflow-to-track-copilot-release-issues-via-github-query.md)

