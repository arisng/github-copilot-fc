# VS Code Expertise Areas

## AI in VS Code (GitHub Copilot & Agents)

### Ways to Work
- **Inline suggestions**: completions and next-edit suggestions as you type
- **Chat view**: conversational agent alongside the editor
- **Inline chat & Quick Chat**: focused edits without leaving the editor
- **Agents window**: delegate tasks and manage multiple agent sessions across projects
- **Automations**: reusable scheduled or event-driven runs, local or cloud

### Harnesses & Models
- Harnesses: **Copilot** (default for new sessions since VS Code 1.143), **Claude**, and **Codex**; the **Local harness is deprecated and scheduled for removal in February 2027**
- Models from multiple providers through Copilot, BYOK API keys, and supported local models
- A harness provides the tools and workflow around a model; choosing a model does not switch the harness

### Customization
- **Instructions**: `.github/copilot-instructions.md` or `AGENTS.md` project-wide; scoped `.github/instructions/*.instructions.md` with `applyTo` patterns
- **Prompt files**: `.prompt.md` slash commands — Local harness only (deprecated path); migrate to skills (see prompt-files.md)
- **Skills**: reusable multi-step workflows packaged as `SKILL.md`
- **Custom agents**: specialized roles with their own tools and model settings
- **Hooks, plugins, MCP servers, connectors**: extend behavior and connect external tools

### Context
- `#`-mentions for files, folders, symbols, terminal output, source-control changes, plus `#codebase` (workspace search) and `#fetch` (web content)
- `@`-mentions, direct URLs, images, and browser content as additional context

### Safety & Operations
- Approval flows and URL confirmation before external access
- Managed sandbox and permission policies on the Copilot harness
- Session continuity across the editor window, Agents window, and cloud sessions
- Agent Debug Log and Cache Explorer for diagnosing prompts and token use

## Core VS Code Features

### Development Workflow
- **Editor**: Multi-cursor editing, IntelliSense, refactoring
- **Debugging**: Breakpoints, watch expressions, call stacks
- **Testing**: Integrated test runners, coverage reports
- **Terminal**: Integrated terminal with shell integration

### Language Support
- **Built-in languages**: JavaScript, TypeScript, Python, etc.
- **Extensions**: Language servers, linters, formatters
- **Frameworks**: React, Angular, Vue, .NET, Java, etc.

### Remote Development
- **SSH**: Remote server development
- **Dev Containers**: Consistent development environments
- **WSL**: Windows Subsystem for Linux integration
- **GitHub Codespaces**: Cloud-based development

### Source Control
- **Git integration**: Commit, push, pull, merge
- **GitHub/GitLab integration**: Pull requests, issues
- **Branch management**: Create, switch, compare branches

## Release Information

### Version Tracking
- **Major releases**: New features, breaking changes
- **Minor releases**: Feature additions, improvements
- **Patch releases**: Bug fixes, security updates

### Update Channels
- **Stable**: Production-ready releases
- **Insiders**: Daily builds with latest features
- **Exploration**: Experimental features and APIs

### Migration Guides
- **Breaking changes**: Migration instructions
- **Deprecations**: Timeline for removed features — e.g. Local harness removal (February 2027), with customization migration steps at https://code.visualstudio.com/docs/agent-customization/migrate-customizations
- **New features**: Adoption guides and tutorials in release notes