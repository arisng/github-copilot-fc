# Agent Skills Factory

This repository serves as a factory for creating and publishing agent skills to personal skills folders for reuse across Copilot, Codex, and Claude.

**Note**: This workspace also provides automated publishing for **Agents**, **Instructions**, and **Prompts** via separate scripts. See the workspace's README.md for complete documentation.

## Overview

The skills factory provides automated tools to publish skills from the project workspace (`skills/`) to your personal skills directories (`~/.claude/skills/`, `~/.codex/skills/`, `~/.copilot/skills/`) for global availability.

### Why `skills/` instead of personal skill folders?

**By Design**: Skills are intentionally located in `skills/` (not `.claude/skills/`, `.codex/skills/`, `.copilot/skills/`) to prevent duplication when tools scan for skills.

When skill discovery is enabled, tools scan both personal and workspace locations. Since this workspace publishes skills to personal locations, having them in both places would cause duplication. Using `skills/` ensures tools only see the published versions.

## Publishing

Publishing copies skills from `skills/` to personal skill folders for Copilot, Codex, and Claude.

## Usage

### Via VS Code Tasks (Recommended)

1. Open Command Palette (`Ctrl+Shift+P`)
2. Run "Tasks: Run Task"
3. Choose from:
    - **Publish Skills**: Copy all skills to personal folders

### Via PowerShell Scripts

```powershell
# Publish all skills
.\scripts\publish\publish-skills.ps1

# Publish specific skills
.\scripts\publish\publish-skills.ps1 -Skills "git-committer", "issue-writer"

# Force overwrite
.\scripts\publish\publish-skills.ps1 -Force
```

### Via Command Line

```bash
powershell -ExecutionPolicy Bypass -File scripts/publish/publish-skills.ps1
```

## Skill Development Workflow

1. **Create/Edit Skills**: Work on skills in `skills/` directory
2. **Test Locally**: Skills are automatically available in this project
3. **Publish**: Copy skills to personal folders for global availability
4. **Re-publish**: Run the publish script again after updates

## Directory Structure

```
.claude/
└── skills/                    # Project skills (factory)
    ├── git-committer/         # Individual skill
    │   └── SKILL.md          # Required skill definition
    ├── issue-writer/
    │   ├── SKILL.md
    │   └── references/
    └── ...

~/.claude/
└── skills/                    # Personal skills (published)
    ├── git-committer/         # Copied from factory
    └── issue-writer/

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

- Re-run the publish script after changes
- Use `-Force` only when you intend to overwrite
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
# Force republish all skills
.\scripts\publish\publish-skills.ps1 -Force

# Clean personal skills and republish
Remove-Item "$env:USERPROFILE\.claude\skills\*" -Recurse -Force
.\scripts\publish\publish-skills.ps1
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