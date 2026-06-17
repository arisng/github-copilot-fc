# Issue Relevance Check — Evaluation Guide

This document defines the complete evaluation framework used by the `/issue-relevance-check` slash command.

## 1. Gather Information

- Read the full issue or pull request details, including the title, body, all comments, and any linked items.
- Look at the current state of the codebase — check if the files, classes, or packages mentioned still exist and whether the problem described has already been addressed.
- Review recent commits and pull requests to see if related changes have been merged.
- Check if there are duplicate or related issues that cover the same topic.

## 2. Evaluate Relevance

Consider these factors:

- **Still applicable?** Does the described bug, feature request, or change still apply to the current codebase?
- **Already resolved?** Has the issue been fixed or the feature implemented in a subsequent commit or PR, even if this item was never explicitly closed?
- **Superseded?** Has a newer issue or PR replaced this one?
- **Stale context?** Are the referenced APIs, dependencies, or architectural patterns still in use, or has the project moved on?
- **Actionability?** Is there enough information to act on this item, or is it too vague or outdated to be useful?

## 3. Provide Your Analysis

Post a single comment with your analysis using this structure:

**Relevance Assessment: [Still Relevant | Likely Outdated | Needs Discussion]**

- **Summary**: A 1-2 sentence verdict.
- **Evidence**: Bullet points with concrete findings (e.g., "The class `XYZParser` referenced in the issue was removed in commit abc1234" or "This feature was implemented in PR #42").
- **Recommendation**: One of:
  - ✅ **Keep open** — the item is still valid and actionable.
  - 🗄️ **Consider closing** — the item appears resolved or no longer applicable. Explain why.
  - 💬 **Needs maintainer input** — you found mixed signals and a human should decide.

## Constraints

- Be concise, factual, and cite specific commits, PRs, files, or code when possible.
- Do not make changes to the repository — the only action is to comment with the analysis.
