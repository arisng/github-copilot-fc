# Agent Skills Factory

This repository serves as a factory for creating and publishing agent skills to personal skills folders for reuse across Copilot. Agent Skilss are standardized across coding agents (Claude, Codex, Copilot) so skills published from this factory are also applicable to Codex and Claude.

**Note**: This workspace also provides automated publishing for **Agents**, **Instructions**, and **Prompts** via separate scripts. See the workspace's README.md for complete documentation.

## References (Official Documentation)

Periodically check official documentation for updates on skill capabilities and best practices:

- [About agent skills](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills)
- [Use Agent Skills in VS Code](https://code.visualstudio.com/docs/copilot/customization/agent-skills)

## Overview

The skills factory provides automated tools to publish skills from the project workspace (`skills/`) to your personal skills directories for global availability. The default target is `~/.agents/skills/`; Copilot (`~/.copilot/skills/`), Codex, and Claude can be enabled explicitly.

### Why `skills/` instead of personal skill folders?

**By Design**: Skills are intentionally located in `skills/` (not `.claude/skills/`, `.codex/skills/`, `.copilot/skills/`) to prevent duplication when tools scan for skills.

When skill discovery is enabled, tools scan both personal and workspace locations. Since this workspace publishes skills to personal locations, having them in both places would cause duplication. Using `skills/` ensures tools only see the published versions.

## Publishing

Publishing copies skills from `skills/` to personal skill folders. By default it publishes to `~/.agents/skills`. Use `-Targets` to include Copilot, Codex, and Claude.

> **WSL policy (2026-08)**: skills are **never** published to WSL by default. Windows personal folders are the canonical targets. WSL mirroring is opt-in only (`-IncludeWSL`) and not needed for routine publishing — do not pass it unless there is a specific reason to mirror to a Linux environment.

## Usage

### Via VS Code Tasks (Recommended)

1. Open Command Palette (`Ctrl+Shift+P`)
2. Run "Tasks: Run Task"
3. Choose from:
    - **Publish Skills**: Copy all skills to personal folders

### Via PowerShell Scripts (legacy)

> ⚠️ **Deprecated (2026-08-05)**: prefer the **Skills CLI** — `npx skills <options>` — for installing/managing skills. `publish-skills.ps1` is a legacy workspace-to-personal copy and will be removed in a future release.

```powershell
# Publish all skills (LEGACY)
.\scripts\publish\publish-skills.ps1

# Publish specific skills (LEGACY)
.\scripts\publish\publish-skills.ps1 -Skills "git-atomic-commit", "issue-md-writer"

# Publish to Agents, Copilot, Codex, and Claude (LEGACY)
.\scripts\publish\publish-skills.ps1 -Targets agents,copilot,codex,claude

# Force overwrite (LEGACY)
.\scripts\publish\publish-skills.ps1 -Force
```

### Via the Skills CLI (preferred)

```bash
# Install a skill package from GitHub
npx skills add <owner>/<repo>

# Install a specific skill from a package
npx skills add <owner>/<repo> -s <skill-name>

# List installed skills
npx skills list

# Remove a skill
npx skills remove <skill>

# Update skills
npx skills update
```

## Skill Development Workflow

1. **Create/Edit Skills**: Work on skills in `skills/` directory
2. **Test Locally**: Skills are automatically available in this project
3. **Publish**: Install to personal folders for global availability — `npx skills add <owner>/<repo>` (or legacy `publish-skills.ps1`)
4. **Re-publish**: Run the command again after updates

## Directory Structure

```
skills/
├── git-committer/            # Individual skill
│   └── SKILL.md              # Required skill definition
├── issue-md-writer/
│   ├── SKILL.md
│   └── references/
└── ...

~/.claude/
└── skills/                    # Personal skills (published)
    ├── git-committer/         # Copied from factory
    └── issue-md-writer/

~/.codex/
└── skills/                    # Personal skills (published)

~/.copilot/
└── skills/                    # Personal skills (published)
```

## Best Practices

### For Skill Authors

- Keep skills focused on single responsibilities
- Write clear, specific descriptions for better discovery
- Include examples and usage instructions in SKILL.md
- Test skills thoroughly before publishing

### For Publishing

- Prefer `npx skills <options>` (Skills CLI) over the legacy `publish-skills.ps1`
- Re-run the publish command after changes
- Use `-Force` (legacy script) only when you intend to overwrite
- Backup your personal skills folder before major operations

### For Team Collaboration

- Commit skill improvements to the factory repository
- Use the update scripts to sync personal skills
- Document breaking changes in skill descriptions
- Consider semantic versioning for major skill updates

## Troubleshooting

### Common Issues

**Skills not appearing in VS Code**
- Ensure `chat.useClaudeSkills` setting is enabled
- Restart VS Code after publishing
- Check that SKILL.md has valid YAML frontmatter

**Changes not appearing**
- Re-run the publish script
- Verify the skill exists in `skills/`

### Recovery

```powershell
# Force republish all skills (LEGACY)
.\scripts\publish\publish-skills.ps1 -Force

# Clean default Copilot target and republish (LEGACY)
Remove-Item "$env:USERPROFILE\.copilot\skills\*" -Recurse -Force
.\scripts\publish\publish-skills.ps1

# Clean all supported targets and republish everywhere (LEGACY)
Remove-Item "$env:USERPROFILE\.claude\skills\*" -Recurse -Force
Remove-Item "$env:USERPROFILE\.codex\skills\*" -Recurse -Force
.\scripts\publish\publish-skills.ps1 -Targets copilot,codex,claude
```

## Integration with VS Code

The publishing system integrates seamlessly with VS Code through:

- **Tasks**: Quick access via Command Palette
- **Git Integration**: Skills are version controlled with your code
- **Settings Sync**: Publishing preferences can be synced across machines
- **Extensions**: Can be extended with custom VS Code extensions

## Future Enhancements

- **Package Registry**: NPM-style skill packages
- **Version Management**: Semantic versioning for skills
- **Dependency Resolution**: Skills that depend on other skills
- **Cross-platform Links**: Improved symbolic link support
- **Automated Publishing**: GitHub Actions for automatic publishing