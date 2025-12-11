# Claude Skills Factory

This repository serves as a factory for creating and managing Claude Skills that can be published to your personal skills folder for reuse across all projects.

## Overview

The skills factory provides automated tools to publish skills from the project workspace (`.claude/skills/`) to your personal skills directory (`~/.claude/skills/`) for global availability in VS Code and Claude Code.

## Publishing Methods

### 1. Copy Method (Recommended)
- **Description**: Creates a full copy of skills in your personal folder
- **Pros**: Works across different drives, no admin privileges needed
- **Cons**: Changes in factory don't automatically reflect in personal folder
- **Use Case**: Most reliable for cross-platform compatibility

### 2. Link Method (Windows Only)
- **Description**: Creates symbolic links from personal folder to project folder
- **Pros**: Automatic updates when factory skills change
- **Cons**: Requires admin privileges, doesn't work across drives
- **Use Case**: Development and testing of skills

### 3. Sync Method (Advanced)
- **Description**: Uses robocopy for incremental synchronization
- **Pros**: Efficient updates, preserves file timestamps
- **Cons**: Windows-specific, more complex
- **Use Case**: Large skill collections with frequent updates

## Usage

### Via VS Code Tasks (Recommended)

1. Open Command Palette (`Ctrl+Shift+P`)
2. Run "Tasks: Run Task"
3. Choose from:
   - **Publish Skills to Personal (Copy)**: Copy all skills
   - **Publish Skills to Personal (Link)**: Create symbolic links
   - **Check for Skill Updates**: See which skills have updates
   - **Update Personal Skills**: Apply available updates

### Via PowerShell Scripts

```powershell
# Publish all skills using copy method
.\scripts\publish-skills.ps1 -Method Copy

# Publish specific skills using link method
.\scripts\publish-skills.ps1 -Method Link -Skills "git-committer", "issue-writer"

# Check for updates without applying
.\scripts\update-personal-skills.ps1 -CheckOnly

# Update all personal skills
.\scripts\update-personal-skills.ps1
```

### Via Command Line

```bash
# Copy method
powershell -ExecutionPolicy Bypass -File scripts/publish-skills.ps1 -Method Copy

# Link method (requires admin)
powershell -ExecutionPolicy Bypass -File scripts/publish-skills.ps1 -Method Link

# Check updates
powershell -ExecutionPolicy Bypass -File scripts/update-personal-skills.ps1 -CheckOnly
```

## Skill Development Workflow

1. **Create/Edit Skills**: Work on skills in `.claude/skills/` directory
2. **Test Locally**: Skills are automatically available in this project
3. **Publish**: Use one of the publishing methods to make skills globally available
4. **Update**: When skills are improved, use update scripts to sync changes

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
    ├── git-committer/         # Copied/linked from factory
    └── issue-writer/
```

## Best Practices

### For Skill Authors
- Keep skills focused on single responsibilities
- Write clear, specific descriptions for better discovery
- Include examples and usage instructions in SKILL.md
- Test skills thoroughly before publishing

### For Publishing
- Use **Copy method** for production/stable skills
- Use **Link method** during development for automatic updates
- Regularly check for updates using the update scripts
- Backup your personal skills folder before major operations

### For Team Collaboration
- Commit skill improvements to the factory repository
- Use the update scripts to sync personal skills
- Document breaking changes in skill descriptions
- Consider semantic versioning for major skill updates

## Troubleshooting

### Common Issues

**"Access denied" when using Link method**
- Run PowerShell as Administrator
- Or use Copy method instead

**Skills not appearing in VS Code**
- Ensure `chat.useClaudeSkills` setting is enabled
- Restart VS Code after publishing
- Check that SKILL.md has valid YAML frontmatter

**Updates not detected**
- Check file timestamps in both directories
- Ensure you're running update from the correct project directory
- Verify skill names match between directories

### Recovery
```powershell
# Force republish all skills
.\scripts\publish-skills.ps1 -Method Copy -Force

# Clean personal skills and republish
Remove-Item "$env:USERPROFILE\.claude\skills\*" -Recurse -Force
.\scripts\publish-skills.ps1 -Method Copy
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