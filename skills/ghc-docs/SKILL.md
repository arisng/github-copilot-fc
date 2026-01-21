---
name: vscode-docs-researcher
description: Comprehensive research and grounding of answers using official VS Code and GitHub Copilot documentation. Use before conducting web searches for VS Code features, Copilot capabilities, configuration, debugging, extensions, remote development, or any official Microsoft documentation queries.
---

# VS Code Documentation Research Skill

Research and ground answers using official VS Code and GitHub Copilot documentation. Provides access to current release notes, feature documentation, and specialized content.

## Core Workflow

1. **Analyze Query**: Identify VS Code/Copilot features, configuration, or troubleshooting needs
2. **Navigate Structure**: Use `assets/toc.md` to locate relevant documentation sections
3. **Retrieve Content**: Fetch specific pages using web tools when detailed information required
4. **Ground Response**: Base answers on official documentation with citations and links

## Key Resources

- **Documentation TOC**: `assets/toc.md` - Complete structure for navigation
- **Official URLs**: See [RESOURCES.md](references/resources.md) for canonical links
- **Expertise Areas**: See [KEY-AREAS.md](references/key-areas.md) for detailed coverage
- **Usage Examples**: See [WORKFLOW-EXAMPLES.md](references/workflow-examples.md) for concrete scenarios

## Tool Integration

- Use web fetching tools for specific documentation pages
- Execute `scripts/parse_toc.py` to refresh documentation structure
- Read reference files as needed for comprehensive coverage

## Best Practices

- Always prefer official documentation over assumptions
- Cite specific URLs and version numbers
- Check release notes for recent feature changes
- Use TOC navigation for comprehensive topic coverage
- Validate answers against current documentation before responding
