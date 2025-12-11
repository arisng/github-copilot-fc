---
name: vscode-docs
description: Skill for researching and grounding answers from official VS Code documentation, focusing on TOC navigation, release notes, and GitHub Copilot features. Use when answering questions about VS Code features, especially GitHub Copilot, or when needing up-to-date information from official docs.
---

# VS Code Docs Research Skill

This skill enables comprehensive research and grounding of answers using official VS Code documentation. It provides access to the latest release notes, detailed feature documentation, and specialized content for GitHub Copilot features.

## Primary Resources

### Documentation TOC

The table of contents is preloaded in `assets/toc.md` for quick navigation. This LLM-friendly markdown file contains the complete structure of VS Code documentation, including nested sections.

**To access TOC:** Read `assets/toc.md` to understand the documentation structure and find relevant sections for user queries.

### Release Notes

- Latest release: [https://code.visualstudio.com/updates](https://code.visualstudio.com/updates) (canonical URL)
- Specific versions: [https://code.visualstudio.com/updates/v1_107](https://code.visualstudio.com/updates/v1_107) (example for v1.107.0)

### GitHub Repository

- Docs source: [https://github.com/microsoft/vscode-docs/](https://github.com/microsoft/vscode-docs/)
- TOC JSON: [https://github.com/microsoft/vscode-docs/blob/main/docs/toc.json](https://github.com/microsoft/vscode-docs/blob/main/docs/toc.json)

## Usage Workflow

1. **Understand Query**: Analyze the user's question about VS Code features or GitHub Copilot.

2. **Navigate TOC**: Read `assets/toc.md` to identify the most relevant documentation sections.

3. **Fetch Content**: Use web fetching tools to retrieve specific documentation pages when detailed information is needed.

4. **Ground Answers**: Base responses on official documentation content, citing sources and providing links.

## Key Areas of Expertise

### GitHub Copilot Features

- Chat functionality and sessions
- Inline suggestions and completions
- Customization options (instructions, prompt files, agents)
- Guides for prompt engineering, debugging, testing
- Security and FAQ

### Core VS Code Features

- Setup and configuration
- Editing, debugging, and testing
- Language support and extensions
- Terminal, source control, and remote development
- Dev containers and deployment

### Release Information

- New features and improvements
- Breaking changes and deprecations
- Bug fixes and performance updates

## Refreshing Documentation

The TOC changes infrequently, but to update `assets/toc.md` with the latest structure:

```bash
python scripts/parse_toc.py
```

This fetches the current toc.json from GitHub and regenerates the markdown file.

## Best Practices

- Always prefer official documentation over assumptions
- Cite specific URLs when providing feature explanations
- For complex features, fetch multiple related pages
- Keep answers current by checking release notes for recent changes
- Use TOC navigation to find comprehensive coverage of topics
