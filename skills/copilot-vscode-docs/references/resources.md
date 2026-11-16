# VS Code Documentation Resources

Verified against live documentation: November 2026 (VS Code 1.146 stable).

## Official Documentation URLs

### Discovery entry points
- **llms.txt index**: https://code.visualstudio.com/llms.txt — machine-readable list of every docs page with one-line summaries
- **TOC JSON**: https://raw.githubusercontent.com/microsoft/vscode-docs/main/docs/toc.json — regenerate `assets/toc.md` with `python3 scripts/parse_toc.py`
- **Markdown pages**: append `.md` to any docs URL for the clean source page (e.g. https://code.visualstudio.com/docs/agents/overview.md)

### Release Notes
- **Latest release**: https://code.visualstudio.com/updates
- **Version-specific**: https://code.visualstudio.com/updates/v{version} (e.g., v1_146 for v1.146.0 — always take the current version number from the latest release page)
- **Insiders builds**: https://code.visualstudio.com/insiders

### AI in VS Code (primary entry point)
- **Overview**: https://code.visualstudio.com/docs/agents/overview (the old `/docs/copilot/overview` redirects here)
- **Harnesses**: https://code.visualstudio.com/docs/agents/run/agent-harnesses
- **Customization overview**: https://code.visualstudio.com/docs/agent-customization/overview
- **Custom instructions**: https://code.visualstudio.com/docs/agent-customization/custom-instructions
- **Custom instructions reference**: https://code.visualstudio.com/docs/agents/reference/custom-instructions-reference
- **Prompt files**: https://code.visualstudio.com/docs/agent-customization/prompt-files
- **Agent skills**: https://code.visualstudio.com/docs/agent-customization/agent-skills
- **Custom agents**: https://code.visualstudio.com/docs/agent-customization/custom-agents
- **Migrate customizations**: https://code.visualstudio.com/docs/agent-customization/migrate-customizations
- **MCP servers**: https://code.visualstudio.com/docs/agent-customization/mcp-servers
- **Language models / BYOK**: https://code.visualstudio.com/docs/agent-customization/language-models
- **Chat context (#-mentions)**: https://code.visualstudio.com/docs/chat/copilot-chat-context
- **Inline suggestions**: https://code.visualstudio.com/docs/editing/ai-powered-suggestions
- **Troubleshooting**: https://code.visualstudio.com/docs/agents/agent-troubleshooting/troubleshooting

### GitHub-side Copilot (platform, not the VS Code editor)
- **Product page**: https://github.com/features/copilot
- **GitHub Docs**: https://docs.github.com/en/copilot — plans, policies, enterprise administration

### Docs source repository
- **GitHub repo**: https://github.com/microsoft/vscode-docs/ — source of `toc.json` and every published page

## URL Stability Warning

The AI documentation was reorganized in 2026: `/docs/copilot/*` moved to `/docs/agents/*`, `/docs/agent-customization/*`, `/docs/chat/*`, and `/docs/editing/*`. Legacy deep links may return 404 instead of redirecting. Discover pages via `assets/toc.md` or `llms.txt`, and verify a URL before citing it.

## Documentation Structure

Top-level areas as rendered in `assets/toc.md` (regenerate after each major release):

- **Setup / Get Started / Configure** — installation, UI, settings, keybindings, profiles, accessibility
- **Editor / Write code / Debugging & Testing / Terminal / Source Control / Remote** — core VS Code features
- **AI in VS Code** — Overview; Get Started; Work with AI (plan and run tasks, sessions, permissions and security); Choose Models and Agents; Customize and Extend; Work Across Apps and Machines; Tutorials & Guides; Concepts; Reference and Help
- **Languages & Runtimes / Extension Docs / Enterprise / Advanced Setup** — specialized topics

## Content Types

- **Guides**: Step-by-step tutorials
- **Reference**: API documentation and configuration options
- **Learn**: Interactive learning paths under https://code.visualstudio.com/learn/
- **Troubleshooting**: Common issues and solutions