---
name: copilot-vscode-docs
description: "Comprehensive research and grounding of answers using official VS Code and GitHub Copilot documentation. Use before conducting web searches for VS Code features, Copilot capabilities, configuration, debugging, extensions, remote development, or any official Microsoft documentation queries."
metadata: 
  version: 1.1.0
  author: arisng
---

# VS Code Documentation Research Skill

Research and ground answers using official VS Code and GitHub Copilot documentation. Provides access to current release notes, feature documentation, and specialized content.

## Core Workflow

1. **Analyze Query**: Identify VS Code/Copilot features, configuration, or troubleshooting needs
2. **Navigate Structure**: Use `assets/toc.md` to locate relevant documentation sections
3. **Retrieve Content**: Fetch specific pages using web tools when detailed information required (see Retrieval Tips)
4. **Ground Response**: Base answers on official documentation with citations and links

## Retrieval Tips

- **Prefer Markdown**: append `.md` to any `code.visualstudio.com/docs/...` URL (for example `https://code.visualstudio.com/docs/agent-customization/prompt-files.md`) to fetch the clean source page instead of HTML.
- **Full page index**: `https://code.visualstudio.com/llms.txt` lists every docs page with a one-line summary — the fastest way to discover the current URL for a topic.
- **Release notes**: `https://code.visualstudio.com/updates`; version-specific pages use `/updates/v{major}_{minor}` (example: `v1_146` for 1.146 — always take the current version number from `/updates`).

## Freshness Checks

- The AI docs were reorganized in 2026: content moved from `/docs/copilot/*` to `/docs/agents/*`, `/docs/agent-customization/*`, `/docs/chat/*`, and `/docs/editing/*`. Legacy deep links can return 404 instead of redirecting, so discover pages via `assets/toc.md` or `llms.txt` instead of hardcoded old URLs.
- If `assets/toc.md` predates the latest major release or its links 404, regenerate it with `python3 scripts/parse_toc.py` (needs network access to the `microsoft/vscode-docs` repo).
- Before answering customization questions, check the live page: **prompt files run only in the Local harness, which is deprecated (removal planned February 2027)** — recommend agent skills for new reusable workflows. Details in [prompt-files.md](references/prompt-files.md).

## Key Resources

- **Documentation TOC**: `assets/toc.md` - Complete structure for navigation
- **Official URLs**: See [resources.md](references/resources.md) for canonical links
- **Expertise Areas**: See [key-areas.md](references/key-areas.md) for detailed coverage
- **Prompt Files**: See [prompt-files.md](references/prompt-files.md) for current syntax, limits, and migration guidance
- **Usage Examples**: See [workflow-examples.md](references/workflow-examples.md) for concrete scenarios

## Tool Integration

- Use web fetching tools for specific documentation pages; append `.md` for Markdown output
- Execute `python3 scripts/parse_toc.py` to refresh documentation structure
- Read reference files as needed for comprehensive coverage

## Best Practices

- Always prefer official documentation over assumptions
- Cite specific URLs and version numbers; note the access date for fast-moving pages
- Check release notes for recent feature changes and deprecations
- Use TOC navigation for comprehensive topic coverage
- Validate answers against current documentation before responding
